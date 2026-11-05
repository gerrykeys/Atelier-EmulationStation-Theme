# The games of ES-DE as Catalogue sees them. A game is what ES-DE lists, a file with
# one of its system's extensions or a folder named like one (which ES-DE treats as a
# file), together with every file it needs: the tracks of a cue sheet or a GD-ROM
# list, the discs of a playlist, the image beside a CloneCD or Alcohol descriptor, the
# whole content of such a folder. Files that another game needs, such as the .bin of
# a .cue, are not games of their own.
#
# A game also has what nothing names but its place tells: the files named like it or
# like a descriptor it needs, such as the .sbi of a PlayStation disc, unless ES-DE lists
# them as games or they are saves; a folder named like it with no other game in it, such
# as the CHD of an arcade set; and for a program in a folder of its own (LocalGames in
# common/scripts/windows/native.cs), all that folder holds. A descriptor is read in the
# encoding that finds its files, as old ones aren't UTF-8. What it names and can't be
# found is told in missing: such a game isn't archived, or it would look safe and not be.
#
# Each game comes with its details from the gamelist and its scraped media. Only the
# details a scraper writes are exchanged with the archive ($LibraryFields); favorites,
# play counts and the other personal fields stay where they are, and a few of them
# ($LibraryPersonal) are only read, for the search of the collections. Atelier draws
# images of its own in one media folder, the achievement progress as physical media.
# The user's own images of that type then wait in <ES-DE home>/atelier, and that is
# where they are read from and removed with the game.
#
# Writing: a downloaded game's details are merged into the gamelist, whose original is
# kept once as gamelist.xml.atelier-backup; a game removed from ES-DE takes its files,
# but those another game still has, its media and gamelist entry with it. The gamelists
# are written once a batch of transfers ends, each in one pass (see Add-GamelistEdit).

. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'esde.ps1'))

$LibraryFields = @('name', 'sortname', 'desc', 'rating', 'releasedate', 'developer', 'publisher', 'genre', 'players')
$LibraryPersonal = @('favorite', 'completed', 'kidgame', 'playcount', 'lastplayed')
# ES-DE's media folders, in the order Catalogue lists them
$LibraryMediaTypes = @('covers', 'backcovers', '3dboxes', 'physicalmedia', 'screenshots', 'titlescreens', 'marquees',
  'fanart', 'miximages', 'custom', 'manuals', 'videos')
# The extensions ES-DE looks for, in its order
$LibraryMediaExt = @{ videos = @('.avi', '.mkv', '.mov', '.mp4', '.wmv'); manuals = @('.pdf') }
$LibraryImageExt = @('.png', '.jpg')
# Folders Catalogue extracts into while downloading, never games: its own, and those
# of its first name, which a download stopped then may have left
$LibraryTempPrefix = '.catalogue-'
$LibraryTempPrefixes = @($LibraryTempPrefix, '.game-archive-')

function Get-MediaExtensions([string]$type) {
  if ($LibraryMediaExt.ContainsKey($type)) { return , $LibraryMediaExt[$type] }
  return , $LibraryImageExt
}

# Where Atelier keeps the user's own images of the type it draws
function Get-SetAsideBase($es, [string]$system, [string]$base) {
  return [IO.Path]::Combine($es.home, 'atelier', 'physicalmedia-backup', $system, $base)
}
function Test-SetAside([string]$type) { return $type -ceq 'physicalmedia' }

# A path inside a folder made relative to it, with forward slashes
function Get-RelativeSlash([string]$dir, [string]$file) {
  $root = $dir.TrimEnd('\')
  if ($file.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { return $file.Substring($root.Length + 1).Replace('\', '/') }
  return (Get-RelativePath $dir $file).Replace('\', '/')
}

function Get-GamelistFile($es, [string]$system) { return [IO.Path]::Combine($es.home, 'gamelists', $system, 'gamelist.xml') }

# The media files of a system, by type and by name without extension, read once (see
# MediaIndex in common/scripts/windows/native.cs); UserMedia of it gives the user's own
# media file of a type for a game: the one ES-DE shows, or for the types Atelier draws,
# the one set aside in its place
function Get-MediaIndex($es, [string]$system, [string]$rel) {
  $types = @{}
  $roots = @{}
  $aside = @{}
  foreach ($type in $LibraryMediaTypes) {
    $types[$type] = Get-MediaExtensions $type
    $roots[$type] = [IO.Path]::Combine($es.mediaDir, $system, $type)
    if (Test-SetAside $type) { $aside[$type] = Get-SetAsideBase $es $system '' }
  }
  # With a game's path, only that game's media, looked up file by file
  if ($rel) { return [Atelier.MediaIndex]::new($types, $roots, $aside, $rel) }
  return [Atelier.MediaIndex]::new($types, $roots, $aside)
}
function Get-UserMedia($index, [string]$rel, [string]$type) {
  if (-not $index) { return $null }
  return $index.UserMedia($rel, $type)
}

# One game of a system read on its own, or $null when it is gone: { system, rel, dir,
# entry, isDir, wide, files: [{ rel, abs, size, mtime }], size, missing: [[descriptor,
# name]], fields, personal, hidden }, rel and the files' rel with forward slashes, the
# files' relative to dir: the folder the game is in, or the system's when one lies outside
# that (wide; LocalGames in common/scripts/windows/native.cs); its details from the
# gamelist with the changes still waiting for it in $edits
function Get-LocalGame($es, [string]$systemName, [string]$rel, $edits) {
  $system = $es.systems[$systemName]
  if (-not $system) { return $null }
  $game = [Atelier.LocalGames]::ScanOne($system.dir, $rel, $system.extensions, $systemName)
  if (-not $game) { return $null }
  $block = [Atelier.Gamelist]::Block((Get-GamelistFile $es $systemName), $game.rel)
  $game.system = $systemName
  $game.fields = [Atelier.Gamelist]::Fields($block, $LibraryFields)
  $game.personal = [Atelier.Gamelist]::Fields($block, $LibraryPersonal)
  $game.hidden = [Atelier.Gamelist]::Tag($block, 'hidden') -ceq 'true'
  $pending = Get-GamelistEdit $edits $systemName $game.rel
  if ($pending.found -and $pending.fields) {
    foreach ($f in $LibraryFields) { if ($pending.fields[$f]) { $game.fields[$f] = [string]$pending.fields[$f] } }
  }
  return $game
}

# Where a downloaded media file of a type goes
function Get-MediaTarget($es, [string]$system, [string]$rel, [string]$type, [string]$ext) {
  return [IO.Path]::GetFullPath([IO.Path]::Combine($es.mediaDir, $system, $type, (Get-BaseOf $rel) + $ext))
}

# Every media file of a game, the user's own and Atelier's: those that go with it
function Get-MediaFiles($es, [string]$system, [string]$rel) {
  $base = Get-BaseOf $rel
  return , @(foreach ($type in $LibraryMediaTypes) {
    $bases = @([IO.Path]::GetFullPath([IO.Path]::Combine($es.mediaDir, $system, $type, $base)))
    if (Test-SetAside $type) { $bases += [IO.Path]::GetFullPath((Get-SetAsideBase $es $system $base)) }
    foreach ($b in $bases) { foreach ($ext in (Get-MediaExtensions $type)) { if ([IO.File]::Exists($b + $ext)) { $b + $ext } } }
  })
}

function Backup-Once([string]$file) {
  $backup = "$file.atelier-backup"
  if ([IO.File]::Exists($file) -and -not [IO.File]::Exists($backup)) { [IO.File]::Copy($file, $backup) }
}

function Get-GamePath([string]$body) { return (Get-XmlTag $body 'path').Replace('\', '/') -replace '^\./', '' }

# Changes to the gamelists of ES-DE, a game's scraped details to set or the game to take
# out, wait until a batch of transfers ends and are then made in one pass per gamelist
# (Save-GamelistEdits): the gamelist of a large system takes a while to write. Each is
# also added to a journal in Catalogue's data folder, so that the changes still waiting
# when the app stops are made the next time it starts (Restore-GamelistEdits). The other
# fields of a game stay as they are. $edits is { journal, systems: { system: { path:
# fields, or $null to take the game out } } }, as New-GamelistEdits makes it.
function New-GamelistEdits([string]$journal) { return [hashtable]::Synchronized(@{ journal = $journal; systems = @{} }) }

function Add-GamelistEdit($edits, [string]$system, [string]$rel, $fields, [switch]$NoJournal) {
  [Threading.Monitor]::Enter($edits)
  try {
    if (-not $edits.systems.Contains($system)) { $edits.systems[$system] = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal) }
    $edits.systems[$system][$rel] = $fields
    if (-not $NoJournal) {
      New-Folder ([IO.Path]::GetDirectoryName($edits.journal))
      [IO.File]::AppendAllText($edits.journal, (ConvertTo-JsonText @{ system = $system; rel = $rel; fields = $fields }) + "`n", $Utf8NoBom)
    }
  } finally {
    [Threading.Monitor]::Exit($edits)
  }
}

# The change waiting for a game: @{ found; fields }, fields $null when it goes
function Get-GamelistEdit($edits, [string]$system, [string]$rel) {
  [Threading.Monitor]::Enter($edits)
  try {
    $byRel = $edits.systems[$system]
    if ($byRel -and $byRel.ContainsKey($rel)) { return @{ found = $true; fields = $byRel[$rel] } }
    return @{ found = $false; fields = $null }
  } finally {
    [Threading.Monitor]::Exit($edits)
  }
}

# Makes the changes waiting, each gamelist kept once as gamelist.xml.atelier-backup
function Save-GamelistEdits($es, $edits) {
  [Threading.Monitor]::Enter($edits)
  try {
    $systems = $edits.systems
    $edits.systems = @{}
    foreach ($system in @($systems.Keys)) {
      $file = Get-GamelistFile $es $system
      try {
        Backup-Once $file
        [void][Atelier.Gamelist]::Apply($file, $systems[$system], $LibraryFields)
      } catch {
        Write-Failure "gamelist of ${system}: $(Get-ErrorMessage $_)"
      }
    }
    Remove-Path $edits.journal
  } finally {
    [Threading.Monitor]::Exit($edits)
  }
}

# The changes a previous run left waiting, made now; a line cut short as it stopped is
# left out
function Restore-GamelistEdits($es, $edits) {
  if (-not [IO.File]::Exists($edits.journal)) { return }
  foreach ($line in [IO.File]::ReadAllLines($edits.journal)) {
    if (-not $line) { continue }
    $e = $null
    try { $e = [Atelier.Json]::Read($line) } catch { continue }
    if ($e -is [Collections.IDictionary] -and $e['system'] -and $e['rel']) { Add-GamelistEdit $edits ([string]$e['system']) ([string]$e['rel']) $e['fields'] -NoJournal }
  }
  Save-GamelistEdits $es $edits
}

# Removes the folders left empty between a file and a folder that stays
function Remove-EmptyUp([string]$from, [string]$stop) {
  $dir = $from
  $prefix = $stop.TrimEnd('\') + '\'
  while ($dir.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and [IO.Directory]::Exists($dir) -and
    -not [IO.Directory]::EnumerateFileSystemEntries($dir).GetEnumerator().MoveNext()) {
    [IO.Directory]::Delete($dir)
    $dir = Get-Parent $dir
  }
}

# The files of a game that can go with it: not those another game in ES-DE still has
function Get-OwnFiles($game) {
  return , [string[]]@([Atelier.Library]::OwnFiles($game.system, $game.rel, [string[]]@(foreach ($f in $game.files) { $f.abs })))
}

# Removes a game from ES-DE: its files, its media and, with the edits of the gamelists,
# its gamelist entry
function Remove-LocalGame($es, $game, $edits) {
  $systemDir = $es.systems[$game.system].dir
  if ($game.isDir) { Remove-Path $game.entry } else { foreach ($file in (Get-OwnFiles $game)) { Remove-Path $file } }
  foreach ($f in $game.files) { Remove-EmptyUp ([IO.Path]::GetDirectoryName($f.abs)) $systemDir }
  Remove-EmptyUp $game.dir $systemDir
  foreach ($file in (Get-MediaFiles $es $game.system $game.rel)) {
    Remove-Path $file
    Remove-EmptyUp ([IO.Path]::GetDirectoryName($file)) ([IO.Path]::Combine($es.mediaDir, $game.system))
  }
  Add-GamelistEdit $edits $game.system $game.rel $null
}
