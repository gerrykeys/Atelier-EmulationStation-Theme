# The archive: a folder on a network share or a disk that holds one zip file per game,
# in a folder per system, and in @metadata what the games' details and media need, laid
# out as ES-DE lays out its own:
#
#   <archive>/@metadata/archive.json                  the format of the archive
#   <archive>/@metadata/<system>/system.json          the system's name
#   <archive>/@metadata/<system>/catalog/00.json ...  the games: their zip, files, details,
#                                                      media, in 256 parts (ff.json the last)
#   <archive>/@metadata/<system>/gamelist.xml         the details again, in ES-DE's format
#   <archive>/@metadata/<system>/<media type>/<game>.<ext>
#   <archive>/<system>/<game>.zip                      subfolders of the ROM folder kept
#   <archive>/@saves/...                               see saves.ps1
#
# A zip holds exactly the files of the game, with their paths relative to the folder the
# game is in, or to the system's when one lies outside that (wide in the catalog, as with
# a playlist in one folder and its discs in another), so extracting it gives back the same
# files. The catalog lists them with size, date and CRC, which tell whether a game in ES-DE
# is the one in the archive. A game that names a file that isn't there isn't archived.
# The catalog is the source of the details; gamelist.xml is written from it so that
# the archive reads without the app too. The catalog is in parts so that archiving a
# game rewrites one small file however many games its system has: Catalog in
# common/scripts/windows/native.cs keeps the parts it read, reads again only those that
# changed, and writes the changes of a transfer a moment later, a few transfers at a time
# (Save-ArchiveCatalog); gamelist.xml follows in the background once a batch ends.
#
# Nothing is half written: a zip is written beside its place, read back and only then
# put in place, files are copied under a temporary name and renamed, and a download is
# extracted into a temporary folder next to the ROMs and checked against the catalog's
# CRCs before its files are moved. The catalog names a game only once its zip is in
# place, and stops naming it before its zip goes.

. ([IO.Path]::Combine($PSScriptRoot, 'library.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'zip.ps1'))

$StoreFormat = [Atelier.Catalog]::Format
$StoreMeta = '@metadata'
$StoreSaves = '@saves'

function Get-MetaDir([string]$root, [string]$system) { return [IO.Path]::Combine($root, $StoreMeta, $system) }
function Get-ArchiveFile([string]$root, [string]$system, $entry) { return [IO.Path]::Combine($root, $system, ([string]$entry['archive']).Replace('/', '\')) }
function Get-MetaMediaFile([string]$root, [string]$system, [string]$file) { return [IO.Path]::Combine((Get-MetaDir $root $system), $file.Replace('/', '\')) }

function Test-Archive([string]$root) { return [IO.File]::Exists([IO.Path]::Combine($root, $StoreMeta, 'archive.json')) }

# Makes a folder an archive
function New-Archive([string]$root) {
  New-Folder ([IO.Path]::Combine($root, $StoreMeta))
  $file = [IO.Path]::Combine($root, $StoreMeta, 'archive.json')
  if (-not [IO.File]::Exists($file)) {
    Write-Atomic $file (ConvertTo-JsonText ([ordered]@{ format = $StoreFormat; app = 'Atelier Catalogue'; created = Get-IsoNow }) -Indent)
  }
}

# The systems the archive holds games of
function Get-ArchiveSystems([string]$root) { return , [string[]]@([Atelier.Catalog]::Systems($root)) }

# One game's entry in the archive, or null, with the changes not written yet
function Get-ArchivedEntry([string]$root, [string]$system, [string]$rel) { return [Atelier.Catalog]::Entry($root, $system, $rel) }
function Get-ArchivedFullName([string]$root, [string]$system) { return [Atelier.Catalog]::FullName($root, $system) }

# Writes the changes of the catalog still waiting: of an archive, or of every archive
function Save-ArchiveCatalog($root) { [void][Atelier.Catalog]::Flush([string]$root) }

function Get-FileCrc([string]$file) { return [Atelier.Crc]::OfFile($file) }

# Two dates of the same file can differ a little: FAT disks keep them to 2 seconds
function Test-SameTime($a, $b) { return [Math]::Abs([double]$a - [double]$b) -le 2000 }

# Whether a game in ES-DE has the files of its entry in the archive. Same size and date
# is enough; a file whose date differs is compared by its CRC, through crcs, a cache
# { path: { size, mtime, crc } } kept between runs.
function Test-SameFiles($game, $entry, $crcs) {
  $archived = @{}
  foreach ($f in @($entry['files'])) { if ($f) { $archived[[string]$f['path']] = $f } }
  if (@($game.files).Count -ne $archived.Count) { return $false }
  foreach ($f in $game.files) {
    $a = $archived[$f.rel]
    if (-not $a -or [long]$a['size'] -ne $f.size) { return $false }
    if (Test-SameTime $a['mtime'] $f.mtime) { continue }
    $known = $crcs[$f.abs]
    $crc = if ($known -and [long]$known['size'] -eq $f.size -and [long]$known['mtime'] -eq $f.mtime) { $known['crc'] } else { $null }
    if (-not $crc) {
      $crc = Get-FileCrc $f.abs
      $crcs[$f.abs] = [ordered]@{ size = $f.size; mtime = $f.mtime; crc = $crc }
    }
    if ($crc -cne $a['crc']) { return $false }
  }
  return $true
}

# Whether the details and the media of the chosen types are as in the archive. A type
# the game doesn't have in ES-DE is no difference: it may just not have been downloaded.
function Test-SameDetails($game, $entry, $index, $types) {
  $fields = $entry['fields']
  if (-not $fields) { $fields = @{} }
  foreach ($f in $LibraryFields) { if ([string]$game.fields[$f] -cne [string]$fields[$f]) { return $false } }
  foreach ($type in $types) {
    $file = Get-UserMedia $index $game.rel $type
    if (-not $file) { continue }
    $archived = if ($entry['media']) { $entry['media'][$type] } else { $null }
    if (-not $archived) { return $false }
    if ([long]$archived['size'] -ne [IO.FileInfo]::new($file).Length -or -not (Test-SameTime $archived['mtime'] (Get-MtimeMs $file))) { return $false }
  }
  return $true
}

# How a game in ES-DE stands with its entry: archived (the same), changed (other
# files) or details (other details or media)
function Compare-Game($game, $entry, $index, $types, $crcs) {
  if (-not (Test-SameFiles $game $entry $crcs)) { return 'changed' }
  if (Test-SameDetails $game $entry $index $types) { return 'archived' }
  return 'details'
}

# The chosen types of media of a game, copied into the archive. Types not chosen, or
# that the game doesn't have, keep what the archive had.
function Copy-MediaToArchive([string]$root, $game, $index, $types, $previous) {
  $media = [ordered]@{}
  if ($previous) { foreach ($k in @($previous.Keys)) { $media[$k] = $previous[$k] } }
  foreach ($type in $types) {
    $file = Get-UserMedia $index $game.rel $type
    if (-not $file) { continue }
    $rel = "$type/$(Get-BaseOf $game.rel)$((Get-Ext $file).ToLowerInvariant())"
    Copy-Atomic $file (Get-MetaMediaFile $root $game.system $rel)
    if ($previous -and $previous[$type] -and $previous[$type]['file'] -cne $rel) { Remove-Path (Get-MetaMediaFile $root $game.system $previous[$type]['file']) }
    $media[$type] = [ordered]@{ file = $rel; size = [IO.FileInfo]::new($file).Length; mtime = Get-MtimeRounded $file }
  }
  return $media
}

# Whether a catalog entry's file is a zip: an early version of Catalogue wrote 7z files
function Test-ZipEntry($entry) { return ([string]$entry['archive']).EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase) }

# A name for a game's zip that no other game of the system has: its own, unless a zip of
# that name is there already, such as that of a game of the same name in another format
function Get-ArchiveName([string]$root, [string]$system, [string]$rel) {
  $base = Get-BaseOf $rel
  for ($n = 1; ; $n++) {
    $name = if ($n -gt 1) { "$base ($n).zip" } else { "$base.zip" }
    if (-not [IO.File]::Exists([IO.Path]::Combine($root, $system, $name.Replace('/', '\')))) { return $name }
  }
}

# Puts a game in the archive, or replaces the one there: its zip, its details and the
# media of the chosen types. The zip is read back before it takes its place, and must
# give back every file as it was read. $progress follows the steps compress and verify.
function Save-GameToArchive($ctx, $game, $index, $types, $progress, $signal) {
  if (@($game.missing).Count) {
    $file, $absent = @($game.missing)[0]
    throw (New-AppError "$file names $absent, which isn't in the system's folder" 'incomplete' @{ file = $file; name = $absent })
  }
  $root = $ctx.root
  $old = Get-ArchivedEntry $root $game.system $game.rel
  $name = if ($old -and (Test-ZipEntry $old)) { [string]$old['archive'] } else { Get-ArchiveName $root $game.system $game.rel }
  $target = [IO.Path]::Combine($root, $game.system, $name.Replace('/', '\'))
  # The same name every time, so a copy left by a transfer that was stopped goes
  $temp = "$target.tmp"
  New-Folder ([IO.Path]::GetDirectoryName($target))
  $names = if ($game.isDir) { , [IO.Path]::GetFileName($game.entry) } else { , [string[]]@(foreach ($f in $game.files) { $f.rel.Replace('/', '\') }) }
  $listed = @{}
  try {
    $written = New-GameZip $temp $names $game.dir $progress $signal
    foreach ($f in (Test-GameZip $temp $progress $signal)) { $listed[$f.Path] = $f }
    foreach ($f in $written) {
      $a = $listed[$f.Path]
      if (-not $a -or $a.Size -ne $f.Size -or $a.Crc -cne $f.Crc) { throw "$($f.Path) doesn't read back from the zip file as it was written" }
    }
    foreach ($f in $game.files) {
      $a = $listed[$f.rel]
      if (-not $a -or $a.Size -ne $f.size) { throw "$($f.rel) is missing from the zip file" }
    }
    Rename-Path $temp $target
  } catch {
    Remove-Path $temp
    throw
  }
  Set-Progress $progress 'media' 0
  $media = Copy-MediaToArchive $root $game $index $types $(if ($old) { $old['media'] } else { $null })
  $packed = [IO.FileInfo]::new($target).Length
  $entry = [ordered]@{
    archive = $name; isDir = $game.isDir
    files = @(foreach ($f in $game.files) { [ordered]@{ path = $f.rel; size = $f.size; mtime = $f.mtime; crc = $listed[$f.rel].crc } })
    size = $game.size; packed = $packed; fields = $game.fields; media = $media; archived = Get-IsoNow; updated = Get-IsoNow; device = $ctx.device
  }
  if ($game.wide) { $entry['wide'] = $true }
  [Atelier.Catalog]::Put($root, $game.system, $game.rel, $entry, $ctx.es.systems[$game.system].fullName)
  # The 7z file an early version wrote gives way to the zip, once the catalog names it
  if ($old -and -not (Test-ZipEntry $old)) {
    Save-ArchiveCatalog $root
    Remove-Path (Get-ArchiveFile $root $game.system $old)
  }
}

# Brings the details and media of a game in the archive up to date, keeping its zip
function Update-ArchivedDetails($ctx, $game, $index, $types) {
  $root = $ctx.root
  $old = Get-ArchivedEntry $root $game.system $game.rel
  if (-not $old) { throw 'The game is not in the archive' }
  $media = Copy-MediaToArchive $root $game $index $types $old['media']
  # A new entry: the one kept may be read meanwhile
  $entry = [ordered]@{}
  foreach ($k in @($old.Keys)) { $entry[$k] = $old[$k] }
  $entry['fields'] = $game.fields
  $entry['media'] = $media
  $entry['updated'] = Get-IsoNow
  $entry['device'] = $ctx.device
  [Atelier.Catalog]::Put($root, $game.system, $game.rel, $entry, $null)
}

# The free space on the disk of a folder, or of its nearest parent that exists
function Get-FreeSpace([string]$dir) {
  $at = $dir
  while (-not [IO.Directory]::Exists($at) -and (Get-Parent $at) -ne $at) { $at = Get-Parent $at }
  try { return [Atelier.Files]::Free($at) } catch { return [double]::PositiveInfinity }
}

# Brings a game from the archive into ES-DE: its files in the system's ROM folder, the
# media of the chosen types, and its details in the gamelist. $local is the game as
# ES-DE has it now, if it does: its files make way for the archive's, unless filesToo
# is false, when they are the same and only the details and media come.
function Get-GameFromArchive($ctx, [string]$system, [string]$rel, $local, [bool]$filesToo, $types, $progress, $signal) {
  $root = $ctx.root
  $es = $ctx.es
  $entry = Get-ArchivedEntry $root $system $rel
  if (-not $entry) { throw 'The game is no longer in the archive' }
  $target = $es.systems[$system]
  if (-not $target) { throw "This ES-DE has no system called $system" }
  $relDir = [IO.Path]::GetDirectoryName($rel.Replace('/', '\'))
  $destDir = if ($relDir -and -not $entry['wide']) { [IO.Path]::Combine($target.dir, $relDir) } else { $target.dir }
  $media = [long]0
  foreach ($t in $types) { if ($entry['media'] -and $entry['media'][$t]) { $media += [long]$entry['media'][$t]['size'] } }
  $needed = $(if ($filesToo) { [double]$entry['size'] } else { 0 }) + $media + 50e6
  if ((Get-FreeSpace $target.dir) -lt $needed) { throw (New-AppError 'Not enough free space' 'space') }
  if ($filesToo) {
    if (-not (Test-ZipEntry $entry)) { throw 'This game was archived by an early version of Catalogue: archive it again from a computer that has it' }
    Expand-GameInto (Get-ArchiveFile $root $system $entry) $entry $target.dir $destDir $local $progress $signal
  }

  Set-Progress $progress 'media' 0
  foreach ($type in $types) {
    $m = if ($entry['media']) { $entry['media'][$type] } else { $null }
    if (-not $m) { continue }
    $to = Get-MediaTarget $es $system $rel $type (Get-Ext ([string]$m['file']))
    foreach ($ext in (Get-MediaExtensions $type)) {
      $other = Get-MediaTarget $es $system $rel $type $ext
      if ($other -ne $to) { Remove-Path $other }
    }
    Copy-Atomic (Get-MetaMediaFile $root $system ([string]$m['file'])) $to
    [IO.File]::SetLastWriteTimeUtc($to, (ConvertFrom-Ms ([double]$m['mtime'])))
    [IO.File]::SetLastAccessTimeUtc($to, [DateTime]::UtcNow)
  }
  $fields = $entry['fields']
  if (-not $fields) { $fields = @{} }
  Add-GamelistEdit $ctx.edits $system $rel $fields
}

# Extracts a game's zip into a temporary folder in the system's ROM folder, checks every
# file against the catalog, and moves the files into place, with the dates they had,
# where the files of the game ES-DE had make way
function Expand-GameInto([string]$archive, $entry, [string]$systemDir, [string]$destDir, $local, $progress, $signal) {
  New-Folder $systemDir
  # Left by a download that was stopped
  foreach ($old in [IO.Directory]::GetFileSystemEntries($systemDir)) {
    if ([IO.Path]::GetFileName($old).StartsWith($LibraryTempPrefix)) { Remove-Path $old }
  }
  $temp = [IO.Path]::Combine($systemDir, "$LibraryTempPrefix$(Get-NowMs)")
  try {
    $extracted = @{}
    foreach ($f in (Expand-GameZip $archive $temp $progress $signal)) { $extracted[$f.Path] = $f }
    foreach ($f in $entry['files']) {
      $x = $extracted[[string]$f['path']]
      if (-not $x -or $x.Size -ne [long]$f['size']) { throw "$($f['path']) is missing from the zip file" }
      if ($f['crc'] -and $x.Crc -cne [string]$f['crc']) { throw "$($f['path']) in the zip file is not the one that was archived" }
    }
    if ($local) {
      if ($local.isDir) { Remove-Path $local.entry } else { foreach ($file in (Get-OwnFiles $local)) { Remove-Path $file } }
    }
    # A folder ES-DE treats as a file is replaced as a whole
    if ($entry['isDir']) { Remove-Path ([IO.Path]::Combine($destDir, ([string]@($entry['files'])[0]['path']).Split('/')[0])) }
    foreach ($f in $entry['files']) {
      $path = ([string]$f['path']).Replace('/', '\')
      $to = [IO.Path]::GetFullPath([IO.Path]::Combine($destDir, $path))
      New-Folder ([IO.Path]::GetDirectoryName($to))
      Remove-Path $to
      Rename-Path ([IO.Path]::Combine($temp, $path)) $to
      # Zip keeps dates to two seconds in local time; the catalog has the file's own
      if ($f['mtime']) { [IO.File]::SetLastWriteTimeUtc($to, (ConvertFrom-Ms ([double]$f['mtime']))) }
    }
  } finally {
    Remove-Path $temp
  }
}

# Takes a game out of the archive, with its media
function Remove-ArchivedGame($ctx, [string]$system, [string]$rel) {
  $root = $ctx.root
  $entry = Get-ArchivedEntry $root $system $rel
  if (-not $entry) { return }
  # The catalog stops naming the game before its files go
  [Atelier.Catalog]::Delete($root, $system, $rel)
  Save-ArchiveCatalog $root
  $file = Get-ArchiveFile $root $system $entry
  Remove-Path $file
  Remove-EmptyUp ([IO.Path]::GetDirectoryName($file)) $root
  if ($entry['media']) {
    foreach ($m in @($entry['media'].Values)) {
      $media = Get-MetaMediaFile $root $system ([string]$m['file'])
      Remove-Path $media
      Remove-EmptyUp ([IO.Path]::GetDirectoryName($media)) (Get-MetaDir $root $system)
    }
  }
  # The system's folder in @metadata, once it holds nothing more
  Remove-EmptyUp (Get-MetaDir $root $system) ([IO.Path]::Combine($root, $StoreMeta))
}

function Get-DeviceName { return [Net.Dns]::GetHostName() }
