# Collections: groups of games made in Catalogue from the games of ES-DE and of the
# archive. They belong to the archive, one JSON file each, so every computer that uses
# the archive has them:
#
#   <archive>/@collections/<name>.json
#     { format, app, id, name, created, updated, device,
#       games: [{ system, path, name }]       the games added by hand
#       search: { text, system, genre, ... }  for a collection that keeps itself up to date
#       excluded: [{ system, path, name }] }  games of the search taken out by hand
#
# No game is copied there: a game is named by its system and its path in the ROM folder,
# as Catalogue tells games apart, and its name only says what it was once it is gone.
# The search is run by the page (main.js), which has the details of every game; it
# tells the server which games it found, and those are remembered on each computer, as
# each has games of its own.
#
# In ES-DE each collection is a custom collection: custom-<name>.cfg in
# <ES-DE home>/collections with the games of the collection that are in ES-DE, enabled
# in es_settings.xml. ES-DE reads them only when it starts and may write its settings
# and gamelists as it ends, so they are written while it is closed: as the app leaves,
# ES-DE is restarted (restart.ps1) and the plan made here is carried out in between.
# Inside custom collections the games are sorted by platform (collectionsortname,
# which ES-DE only uses there), for Catalogue's collections and the user's own alike.
#
# <ES-DE home>/atelier/catalogue/collections.json remembers what was written, so that
# no other collection is ever touched, and the games each search found. Games added
# to or taken out of a collection with ES-DE's own editor are carried back into the
# archive the next time the app reads its library.

. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'esde.ps1'))

$CollectionsFormat = 1
$CollectionsFolder = '@collections'
# What a search may hold, all as text
$CollectionSearchKeys = @('text', 'system', 'genre', 'decade', 'year', 'developer', 'publisher', 'players', 'region', 'favorite', 'completed')

function Get-CollectionsDir([string]$root) { return [IO.Path]::Combine($root, $CollectionsFolder) }
function Get-GameKey([string]$system, [string]$path) { return "$system/$path" }

# The games of a collection file as { system, path, name }, each once, kept by
# CollectionGames in common/scripts/windows/native.cs: a collection can hold hundreds of
# thousands of games, never gone through one by one here
function Read-CollectionGames($list) { return [Atelier.CollectionGames]::From($list) }

# A search with only the parts it may hold, or $null for none
function Read-CollectionSearch($search) {
  if (-not ($search -is [Collections.IDictionary])) { return $null }
  $out = [ordered]@{}
  foreach ($key in $CollectionSearchKeys) {
    $value = [string]$search[$key]
    if ($value.Trim()) { $out[$key] = $(if ($value.Length -gt 200) { $value.Substring(0, 200) } else { $value }) }
  }
  if (-not $out.Count) { return $null }
  return $out
}

function Test-SameSearch($a, $b) {
  if (-not $a -or -not $b) { return -not $a -and -not $b }
  foreach ($key in $CollectionSearchKeys) { if ([string]$a[$key] -cne [string]$b[$key]) { return $false } }
  return $true
}

# The collections of an archive, by name; a copy of a file with the same id counts once.
# A file is read again only once it changed (CollectionFiles in native.cs).
function Read-Collections([string]$root) {
  $list = New-List
  $dir = Get-CollectionsDir $root
  if (-not [IO.Directory]::Exists($dir)) { return , $list }
  $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $files = [IO.Directory]::GetFiles($dir, '*.json')
  [Array]::Sort($files, [StringComparer]::OrdinalIgnoreCase)
  foreach ($file in $files) {
    $read = [Atelier.CollectionFiles]::Read($file)
    if (-not $read) { continue }
    $data = $read['data']
    if (-not [string]$data['id'] -or -not [string]$data['name']) { continue }
    if (-not $ids.Add([string]$data['id'])) { continue }
    $list.Add(@{
      file = [IO.Path]::GetFileName($file)
      id = [string]$data['id']; name = [string]$data['name']
      created = [string]$data['created']; updated = [string]$data['updated']; device = [string]$data['device']
      games = $read['games']
      search = Read-CollectionSearch $data['search']
      excluded = $read['excluded']
    })
  }
  $names = [string[]]@(foreach ($c in $list) { $c.name })
  return , [Collections.Generic.List[object]][Atelier.NameComparer]::Sort($list, $names, $null, [Globalization.CultureInfo]::CurrentCulture.Name)
}

# A file name for a collection: its name, without what Windows doesn't allow
function Get-CollectionFileName([string]$name) {
  $clean = [regex]::Replace([regex]::Replace($name, '[\\/:*?"<>|\x00-\x1f]', ' '), '\s+', ' ').Trim().TrimEnd('.').Trim()
  if ($clean.Length -gt 80) { $clean = $clean.Substring(0, 80).Trim() }
  if (-not $clean -or $clean -match '^(?i)(con|prn|aux|nul|com\d|lpt\d)$') { $clean = "Collection $clean".Trim() }
  return $clean
}

# Writes a collection to its file, named after it: a renamed collection moves to a file
# of its new name, and one named like another gets a number
function Write-Collection([string]$root, $c) {
  $dir = Get-CollectionsDir $root
  $wanted = Get-CollectionFileName $c.name
  $file = $null
  for ($n = 1; -not $file; $n++) {
    $candidate = if ($n -eq 1) { "$wanted.json" } else { "$wanted ($n).json" }
    if (($c.file -and $candidate -ieq $c.file) -or -not [IO.File]::Exists([IO.Path]::Combine($dir, $candidate))) { $file = $candidate }
  }
  $data = [ordered]@{
    format = $CollectionsFormat; app = 'Atelier Catalogue'; id = $c.id; name = $c.name
    created = $c.created; updated = $c.updated; device = $c.device
    games = $c.games.ToJson()
  }
  if ($c.search) {
    $data.search = $c.search
    $data.excluded = $c.excluded.ToJson()
  }
  $path = [IO.Path]::Combine($dir, $file)
  Write-Atomic $path (ConvertTo-JsonText $data -Indent)
  # Reading it back gives what was just written, without reading it
  $data.Remove('games')
  $data.Remove('excluded')
  $excluded = $null
  if ($c.search) { $excluded = $c.excluded }
  [Atelier.CollectionFiles]::Wrote($path, $c.games, $excluded, (ConvertTo-JsonText $data))
  if ($c.file -and $c.file -ine $file) { Remove-Path ([IO.Path]::Combine($dir, $c.file)) }
  $c.file = $file
}

function New-CollectionId { return [Guid]::NewGuid().ToString('N').Substring(0, 16) }

# Removes the games of the keys (or entries) from a list of games, and tells whether
# there were any
function Remove-CollectionGames($list, $keys) { return $list.Remove($keys) }

# Adds games given as { system, path, name }, or games of the library, to a list, those
# not there yet
function Add-CollectionGames($list, $entries) { return $list.Add($entries) }

# A change the page asks for, made to the collection as the archive has it now, so that
# changes from another computer meanwhile stay: { id, name, add, remove, exclude,
# include, search, clearSearch }. Returns the collection, or $null if it is gone.
function Update-Collection([string]$root, $body, [string]$device) {
  $c = $null
  foreach ($x in (Read-Collections $root)) { if ($x.id -ceq [string]$body['id']) { $c = $x } }
  if (-not $c) { return $null }
  $name = ([string]$body['name']).Trim()
  if ($name) { $c.name = $name }
  # Added by hand: in the collection whatever the search finds
  if ($body['add']) {
    [void](Add-CollectionGames $c.games $body['add'])
    [void](Remove-CollectionGames $c.excluded $body['add'])
  }
  if ($body['remove']) { [void](Remove-CollectionGames $c.games $body['remove']) }
  if ($body['exclude']) { [void](Add-CollectionGames $c.excluded $body['exclude']) }
  if ($body['include']) { [void](Remove-CollectionGames $c.excluded $body['include']) }
  if ($body['clearSearch']) {
    $c.search = $null
    $c.excluded = Read-CollectionGames $null
  } elseif ($body['search']) {
    $search = Read-CollectionSearch $body['search']
    if ($search) { $c.search = $search }
  }
  $c.updated = Get-IsoNow
  $c.device = $device
  Write-Collection $root $c
  return $c
}

function New-Collection([string]$root, [string]$name, $games, $search, [string]$device) {
  $now = Get-IsoNow
  $c = @{ file = $null; id = New-CollectionId; name = $name.Trim(); created = $now; updated = $now; device = $device
    games = Read-CollectionGames $games; search = Read-CollectionSearch $search; excluded = Read-CollectionGames $null }
  if (-not $c.name) { $c.name = 'Collection' }
  Write-Collection $root $c
  return $c
}

function Remove-Collection([string]$root, [string]$id) {
  foreach ($c in (Read-Collections $root)) {
    if ($c.id -ceq $id) { Remove-Path ([IO.Path]::Combine((Get-CollectionsDir $root), $c.file)) }
  }
}

# What this computer remembers: { written: { <ES-DE name>: { id, lines } }, matches:
# { <id>: { search, games } } }
function Read-CollectionsRecord([string]$file) {
  $record = Read-JsonFile $file $null
  if (-not ($record -is [Collections.IDictionary])) { $record = New-Map }
  foreach ($key in 'written', 'matches') { if (-not ($record[$key] -is [Collections.IDictionary])) { $record[$key] = New-Map } }
  return $record
}

# The games of a collection by key: those added by hand, then those its search found
# on this computer and nobody took out
function Get-CollectionMembers($c, $record) {
  $found = $record['matches'][$c.id]
  $games = $null
  if ($c.search -and $found -is [Collections.IDictionary] -and (Test-SameSearch (Read-CollectionSearch $found['search']) $c.search)) { $games = $found['games'] }
  return , [Atelier.CollectionGames]::Members($c.games, $c.excluded, $games)
}

# ES-DE's side

# A collection's name in ES-DE, which is its file name: letters, digits and the few
# signs ES-DE allows in the names of custom collections, without accents or commas,
# which separate the names in its settings
function Get-EsdeCollectionName([string]$name) {
  $sb = [Text.StringBuilder]::new()
  foreach ($ch in $name.Normalize([Text.NormalizationForm]::FormD).ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -eq [Globalization.UnicodeCategory]::NonSpacingMark) { continue }
    if ([char]::IsLetterOrDigit($ch) -or "-[]()' ".IndexOf($ch) -ge 0) { [void]$sb.Append($ch) } else { [void]$sb.Append(' ') }
  }
  $clean = [regex]::Replace($sb.ToString().Normalize([Text.NormalizationForm]::FormC), '\s+', ' ').Trim()
  if ($clean.Length -gt 60) { $clean = $clean.Substring(0, 60).Trim() }
  if (-not $clean) { $clean = 'Collection' }
  return $clean
}

function Get-EsdeCollectionFile($es, [string]$name) { return [IO.Path]::Combine($es.home, 'collections', "custom-$name.cfg") }

# ES-DE's paths as the collections read them (EsdePaths in common/scripts/windows/native.cs),
# made once for an ES-DE: each system's folder, its path in es_systems.xml and its full name
function Get-EsdePaths($es) {
  if (-not $es.collectionPaths) {
    $systems = @{}
    foreach ($s in $es.systems.Values) { $systems[$s.name] = @([string]$s.dir, [string]$s.path, [string]$s.fullName) }
    $es.collectionPaths = [Atelier.EsdePaths]::new($systems, [string]$es.romDir, [string]$es.tilde, [string]$es.appDir)
  }
  return $es.collectionPaths
}

# A game's line in a custom collection, as ES-DE writes it: its system's folder as
# es_systems.xml has it, %ROMPATH% for the ROM directory
function Get-EsdeCollectionLine($es, [string]$system, [string]$rel) { return (Get-EsdePaths $es).Line($system, $rel) }

# The full path a line stands for, or $null; paths are compared ignoring case
function ConvertFrom-EsdeCollectionLine($es, [string]$line) { return (Get-EsdePaths $es).FullOfLine($line) }
function New-PathSet { return , [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase) }

function Get-GameFullPath($es, [string]$system, [string]$rel) { return (Get-EsdePaths $es).FullPath($system, $rel) }

# The lines of a custom collection file, trimmed, with forward slashes; $null without it
function Read-EsdeCollectionLines([string]$file) {
  $lines = [Atelier.EsdePaths]::ReadLines($file)
  if ($null -eq $lines) { return $null }
  return , $lines
}

# The custom collections enabled in ES-DE, by name
function Get-EnabledCollections([string]$settings) {
  $m = [regex]::Match($settings, '<string name="CollectionSystemsCustom" value="([^"]*)"')
  if (-not $m.Success) { return , @() }
  return , @(foreach ($n in (ConvertFrom-XmlText $m.Groups[1].Value).Split(',')) { if ($n.Trim()) { $n.Trim() } })
}

# What ES-DE should show of the collections: { <ES-DE name>: { id, lines } }, with the
# games of each that are in ES-DE now. The names stay as they were written as long as
# the collection keeps its name, and never take one of the user's own collections.
function Get-EsdeCollectionsWanted($es, $collections, $record) {
  $written = $record['written']
  $used = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $dir = [IO.Path]::Combine($es.home, 'collections')
  if ([IO.Directory]::Exists($dir)) {
    foreach ($file in [IO.Directory]::GetFiles($dir, 'custom-*.cfg')) {
      $name = [IO.Path]::GetFileNameWithoutExtension($file).Substring(7)
      if (-not $written.ContainsKey($name)) { [void]$used.Add($name) }
    }
  }
  foreach ($name in (Get-EnabledCollections $es.settings)) { if (-not $written.ContainsKey($name)) { [void]$used.Add($name) } }
  $wanted = New-Map
  foreach ($c in $collections) {
    $base = Get-EsdeCollectionName $c.name
    $name = $base
    for ($n = 2; $used.Contains($name); $n++) { $name = "$base $n" }
    [void]$used.Add($name)
    $lines = (Get-EsdePaths $es).LinesOf((Get-CollectionMembers $c $record))
    $wanted[$name] = [ordered]@{ id = $c.id; lines = $lines }
  }
  return $wanted
}

# Whether two lists hold the same lines, in any order
function Test-SameLines($a, $b) { return [Atelier.CollectionGames]::SameLines($a, $b) }

# The plan for ES-DE, and whether it changes anything: { app, changed, written, remove,
# record }. $collections is $null when the archive couldn't be read, and then ES-DE
# keeps what it has.
function Get-EsdeCollectionsPlan($es, [string]$appArg, $collections, $record) {
  $written = $record['written']
  $plan = @{ app = $appArg; changed = $false; written = $written; remove = @() }
  if ($null -eq $collections) { return $plan }
  $wanted = Get-EsdeCollectionsWanted $es $collections $record
  $plan.written = $wanted
  $plan.remove = @(foreach ($name in @($written.Keys)) { if (-not $wanted.ContainsKey($name)) { $name } })
  $plan.changed = [bool]$plan.remove.Count
  foreach ($name in @($wanted.Keys)) {
    if (-not $written.ContainsKey($name) -or -not (Test-SameLines $written[$name]['lines'] $wanted[$name].lines)) { $plan.changed = $true }
  }
  return $plan
}

# Sets the collection sort name, "<platform> <title>", of the games given by their full
# paths (New-PathSet), and takes the ones written before off the others. Sort names that
# don't start with the platform's name are the user's own and stay. Each gamelist is
# copied to gamelist.xml.atelier-backup the first time it changes. Done by
# Gamelist.SetCollectionSortNames in common/scripts/windows/native.cs, while ES-DE is
# closed: it reads a gamelist of hundreds of thousands of games in a moment.
function Update-CollectionSortNames($es, $paths) {
  $dir = [IO.Path]::Combine($es.home, 'gamelists')
  if (-not [IO.Directory]::Exists($dir)) { return 0 }
  $changed = 0
  foreach ($systemDir in [IO.Directory]::GetDirectories($dir)) {
    $system = $es.systems[[IO.Path]::GetFileName($systemDir)]
    $file = [IO.Path]::Combine($systemDir, 'gamelist.xml')
    if (-not $system -or -not [IO.File]::Exists($file)) { continue }
    $changed += [Atelier.Gamelist]::SetCollectionSortNames($file, [string]$system.fullName, [string]$system.dir, $paths)
  }
  return $changed
}

# The full paths of the games in the enabled custom collections that aren't
# Catalogue's, as the cfg files of ES-DE list them
function Get-OtherCollectionPaths($es, [string]$settings, $ours) {
  $paths = New-PathSet
  $esdePaths = Get-EsdePaths $es
  foreach ($name in (Get-EnabledCollections $settings)) {
    if ($ours.Contains($name)) { continue }
    $esdePaths.AddFulls((Read-EsdeCollectionLines (Get-EsdeCollectionFile $es $name)), $paths)
  }
  return , $paths
}

# Turns custom collections on or off in ES-DE's settings, the user's others as they are
function Set-EnabledCollections([string]$file, $add, $drop) {
  $settings = [IO.File]::ReadAllText($file)
  $enabledLine = [regex]'<string name="CollectionSystemsCustom" value="([^"]*)" />'
  $previous = $enabledLine.Match($settings)
  $names = [Collections.Generic.List[string]]::new()
  $dropSet = [Collections.Generic.HashSet[string]]::new([string[]]@($drop), [StringComparer]::OrdinalIgnoreCase)
  foreach ($n in (Get-EnabledCollections $settings)) { if (-not $dropSet.Contains($n) -and -not $names.Contains($n)) { $names.Add($n) } }
  foreach ($n in @($add)) { if (-not $names.Contains($n)) { $names.Add($n) } }
  $list = $names.ToArray()
  [Array]::Sort($list, [StringComparer]::Ordinal)
  $line = "<string name=""CollectionSystemsCustom"" value=""$(ConvertTo-XmlText ($list -join ','))"" />"
  # es_settings.xml is a flat list of entries without a root element
  $next = if ($previous.Success) { $enabledLine.Replace($settings, $line.Replace('$', '$$'), 1) } else { "$([regex]::new('\s*$').Replace($settings, '', 1))`n$line`n" }
  if ($next -cne $settings) { Write-TextFile $file $next }
  return $next
}

# Carries out a plan while ES-DE is closed: the collection files, the settings, the
# sort names, and what was written into the record
function Invoke-EsdeCollectionsPlan($plan, [string]$recordFile) {
  $es = Open-Esde ([string]$plan['app'])
  $written = $plan['written']
  foreach ($name in @($plan['remove'])) { Remove-Path (Get-EsdeCollectionFile $es ([string]$name)) }
  foreach ($name in @($written.Keys)) {
    $lines = [Atelier.CollectionGames]::Strings($written[$name]['lines'])
    Write-TextFile (Get-EsdeCollectionFile $es $name) $(if ($lines.Count) { ($lines -join "`n") + "`n" } else { '' })
  }
  $settingsFile = [IO.Path]::Combine($es.home, 'settings', 'es_settings.xml')
  $settings = Set-EnabledCollections $settingsFile @($written.Keys) @($plan['remove'])
  $ours = [Collections.Generic.HashSet[string]]::new([string[]]@($written.Keys), [StringComparer]::OrdinalIgnoreCase)
  $paths = Get-OtherCollectionPaths $es $settings $ours
  $esdePaths = Get-EsdePaths $es
  foreach ($name in @($written.Keys)) { $esdePaths.AddFulls($written[$name]['lines'], $paths) }
  [void](Update-CollectionSortNames $es $paths)
  $record = Read-CollectionsRecord $recordFile
  $record['written'] = $written
  Write-Atomic $recordFile (ConvertTo-JsonText $record -Indent)
}

# Games added or taken out with ES-DE's own editor since the collections were written,
# into the archive: an added game joins the collection, a game taken out leaves it, and
# if its search finds it, it is excluded. Games ES-DE no longer has don't count as taken
# out. Returns whether a collection changed.
function Sync-EsdeCollectionEdits($es, [string]$root, $collections, $record, [string]$device) {
  $changed = $false
  $written = $record['written']
  foreach ($name in @($written.Keys)) {
    $before = $written[$name]
    $now = Read-EsdeCollectionLines (Get-EsdeCollectionFile $es $name)
    if ($null -eq $now -or (Test-SameLines $before['lines'] $now)) { continue }
    $c = $null
    foreach ($x in $collections) { if ($x.id -ceq [string]$before['id']) { $c = $x } }
    if (-not $c) { continue }
    # By full path: the games added { system, path, name }, and those taken out that
    # are still there
    $edits = (Get-EsdePaths $es).EditsOf($before['lines'], $now)
    if ($edits['add'].Count -or $edits['remove'].Count) {
      $body = @{ id = $c.id; add = $edits['add']; remove = $edits['keys'] }
      if ($c.search) { $body.exclude = $edits['remove'] }
      [void](Update-Collection $root $body $device)
      $changed = $true
    }
    $before['lines'] = $now
  }
  return $changed
}

# Takes Catalogue's collections out of ES-DE: their files, their place in the settings
# and the sort names; see remove.ps1
function Remove-EsdeCollections($es, [string]$recordFile) {
  $record = Read-CollectionsRecord $recordFile
  $names = @($record['written'].Keys)
  foreach ($name in $names) { Remove-Path (Get-EsdeCollectionFile $es $name) }
  $settingsFile = [IO.Path]::Combine($es.home, 'settings', 'es_settings.xml')
  [void](Set-EnabledCollections $settingsFile @() $names)
  $removed = Update-CollectionSortNames $es (New-PathSet)
  return @{ collections = $names.Count; sortNames = $removed }
}

# Older versions stored covers with a platform banner as the miximages of the games in
# collections (OldBanners in common/scripts/windows/native.cs takes them off). The list
# they kept goes last, so that a run cut short goes on the next time; once done this
# only looks for two paths. Returns how many banners went.
function Remove-PlatformBanners($es) {
  $list = [IO.Path]::Combine($es.home, 'atelier', 'miximages.json')
  $backup = [IO.Path]::Combine($es.home, 'atelier', 'miximages-backup')
  if (-not [IO.File]::Exists($list) -and -not [IO.Directory]::Exists($backup)) { return 0 }
  $removed = [Atelier.OldBanners]::TakeOff($es.mediaDir, $backup)
  Remove-Path $list
  return $removed
}
