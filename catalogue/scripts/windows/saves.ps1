# The saves and save states RetroArch keeps of a game, and their copies in the archive.
#
# RetroArch is found the way ES-DE finds it, with its find rules, and its retroarch.cfg
# says where it saves: in its saves and states folders, in a subfolder per core and/or
# per ROM folder, or next to the game. Its files are named after the game's file, such
# as "Super Mario Bros. (Europe).srm" or ".state1", so they belong to a game by name,
# which the archive keeps.
#
# In the archive the saves belong to the game, one copy for everyone who uses it:
#
#   @saves/<system>/<game>/current/manifest.json, <kind>/<core>/<file>
#   @saves/<system>/<game>/history/<date> <computer>/...   the 5 before
#
# kind is saves or states, core the core's folder ("_" for none). Saves of the same
# system usually work in any core, so a download puts them where the core this ES-DE
# uses for the game reads them; states only work with the core that wrote them and
# keep its folder. Before a download replaces saves on this computer, they are copied
# to saves-backup in Catalogue's folder, <ES-DE home>/atelier/catalogue.
#
# Which copy is newer is told by what was last exchanged: the files' CRCs at the last
# upload or download (the signature), kept per archive and game in the app's state.
# Saves that changed on both sides since then are a conflict, which only the user can
# settle.

. ([IO.Path]::Combine($PSScriptRoot, 'store.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'retroarch.ps1'))

$SavesHistory = 5
# What follows the game's name in the name of a save or state RetroArch or its cores
# write: srm, rtc, state, state1, state.auto, their .png thumbnails, 1.mcr...
$SavesSuffix = [regex]::new('^(srm|sav|rtc|ldci|eep|sra|fla|mpk|(\d+\.)?mcr|state\d*(\.auto)?(\.png)?)$', 'IgnoreCase')

# RetroArch as ES-DE runs it: where it is, where it saves, and its cores' names
function Get-RetroArchSaves($es) {
  $found = Find-RetroArch $es
  if (-not $found) { return $null }
  $config = $found.config
  $dir = $found.dir
  # ":" starts a path relative to RetroArch's folder
  $resolve = {
    param($value, $fallback)
    $v = if (-not $value -or $value -ceq 'default') { $fallback } else { $value }
    [IO.Path]::GetFullPath([IO.Path]::Combine($dir, ($v -replace '^:[\\/]?', '')))
  }
  $on = { param($key) $config[$key] -ceq 'true' }
  return @{
    exe = $found.exe; dir = $dir
    saves = @{ root = & $resolve $config['savefile_directory'] 'saves'; byCore = & $on 'sort_savefiles_enable'
      byContent = & $on 'sort_savefiles_by_content_enable'; inContent = & $on 'savefiles_in_content_dir' }
    states = @{ root = & $resolve $config['savestate_directory'] 'states'; byCore = & $on 'sort_savestates_enable'
      byContent = & $on 'sort_savestates_by_content_enable'; inContent = & $on 'savestates_in_content_dir' }
    infoDir = & $resolve $config['libretro_info_path'] 'info'
  }
}

# The emulators chosen in ES-DE for a system and for its games, by command label, read
# from its gamelist once per cache
function Get-EmulatorChoices($es, [string]$system, $cache) {
  $key = "choices:$system"
  if ($cache.ContainsKey($key)) { return $cache[$key] }
  $file = Get-GamelistFile $es $system
  $xml = if ([IO.File]::Exists($file)) { [IO.File]::ReadAllText($file) } else { '' }
  $games = New-Map
  foreach ($m in [regex]::Matches($xml, '<game>([\s\S]*?)</game>')) {
    $label = Get-XmlTag $m.Groups[1].Value 'altemulator'
    if ($label) { $games[(Get-GamePath $m.Groups[1].Value)] = $label }
  }
  $alt = [regex]::Match($xml, '<alternativeEmulator>([\s\S]*?)</alternativeEmulator>')
  $choices = @{ system = Get-XmlTag $(if ($alt.Success) { $alt.Groups[1].Value } else { '' }) 'label'; games = $games }
  $cache[$key] = $choices
  return $choices
}

# The core RetroArch runs a game with in this ES-DE, by its folder name ("Mesen"), or
# $null when the game runs in another emulator; 'unknown' when no core can be told.
# A cache shared by the calls for a library reads each gamelist and core once.
function Get-GameCore($es, $ra, $game, $cache = @{}) {
  $system = $es.systems[$game.system]
  if (-not $system -or -not @($system.commands).Count) { return 'unknown' }
  $choices = Get-EmulatorChoices $es $game.system $cache
  $label = $choices.games[$game.rel]
  if (-not $label) { $label = $choices.system }
  $command = @($system.commands)[0].command
  if ($label) { foreach ($c in $system.commands) { if ($c.label -ceq $label) { $command = $c.command; break } } }
  if (-not $command.Contains('%EMULATOR_RETROARCH%')) { return $null }
  $m = [regex]::Match($command, '%CORE_RETROARCH%[\\/]([\w.-]+?)\.(?:dll|so|dylib)')
  if (-not $m.Success) { return 'unknown' }
  $lib = $m.Groups[1].Value
  $key = "core:$lib"
  if (-not $cache.ContainsKey($key)) {
    $name = $null
    try {
      $info = [IO.File]::ReadAllText([IO.Path]::Combine($ra.infoDir, "$lib.info"))
      $n = [regex]::Match($info, '^\s*corename\s*=\s*"([^"]+)"', 'Multiline')
      if ($n.Success) { $name = $n.Groups[1].Value }
    } catch {}
    $cache[$key] = if ($name) { $name } else { 'unknown' }
  }
  return $cache[$key]
}

# The games of a system whose saves are in the archive, by their path without
# extension, from one look at the system's folder
function Get-ArchivedSaveGames([string]$root, [string]$system) {
  $found = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $pending = [Collections.Generic.Stack[object]]::new()
  $pending.Push(@([IO.Path]::Combine($root, $StoreSaves, $system), ''))
  while ($pending.Count) {
    $at, $rel = $pending.Pop()
    try { $dirs = [IO.Directory]::GetDirectories($at) } catch { continue }
    $names = @(foreach ($d in $dirs) { [IO.Path]::GetFileName($d) })
    if ($names -ccontains 'current') { [void]$found.Add($rel); continue }
    foreach ($name in $names) { $pending.Push(@([IO.Path]::Combine($at, $name), $(if ($rel) { "$rel/$name" } else { $name }))) }
  }
  return , $found
}

# The file RetroArch gets for a game: a folder ES-DE treats as a file is run through
# the file of the same name inside it
function Get-ContentPath($game) {
  if ($game.isDir) { return [IO.Path]::Combine($game.entry, [IO.Path]::GetFileName($game.entry)) }
  return $game.entry
}
function Get-SaveName($game) { return Get-BaseOf ([IO.Path]::GetFileName((Get-ContentPath $game))) }

# Every save and state file RetroArch has, by the name of the game it belongs to:
# Map(name => [{ kind, core, name, abs, size, mtime }]). Read once for many games. Saves
# kept next to the games are looked for in the folders of the games, or in dirs.
function Find-Saves($ra, $games, $dirs = $null) {
  $found = New-Map
  $add = {
    param([string]$kind, [string]$dir, [string[]]$segments, [bool]$walk)
    try { $list = [IO.DirectoryInfo]::new($dir).GetFileSystemInfos() } catch { return }
    $k = $ra[$kind]
    # Folders are a ROM folder's and then a core's; a single one is whichever this
    # RetroArch sorts by, a core's if it sorts by neither (saves from before)
    $core = if ($segments.Count -eq 2) { $segments[1] } elseif ($segments.Count -eq 1 -and -not ($k.byContent -and -not $k.byCore)) { $segments[0] } else { $null }
    foreach ($e in $list) {
      if ($e -is [IO.DirectoryInfo]) {
        if ($walk -and $segments.Count -lt 2) { & $add $kind $e.FullName ([string[]]@($segments + $e.Name)) $walk }
        continue
      }
      $file = $null
      $name = $e.Name
      # Every way of splitting the name into a game's name and a save suffix
      for ($i = $name.IndexOf('.'); $i -gt 0; $i = $name.IndexOf('.', $i + 1)) {
        $rest = $name.Substring($i + 1)
        if ($rest.Length -gt 24 -or -not $SavesSuffix.IsMatch($rest)) { continue }
        if (-not $file) { $file = @{ kind = $kind; core = $core; name = $name; abs = $e.FullName; size = $e.Length; mtime = Get-MtimeRounded $e.FullName } }
        $key = $name.Substring(0, $i)
        $list2 = $found[$key]
        if (-not $list2) { $list2 = New-List; $found[$key] = $list2 }
        $list2.Add($file)
      }
    }
  }
  foreach ($kind in 'saves', 'states') {
    & $add $kind $ra[$kind].root ([string[]]@()) $true
    if ($ra[$kind].inContent) {
      $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
      if ($dirs) { foreach ($d in $dirs) { [void]$seen.Add($d) } }
      foreach ($g in $games) { [void]$seen.Add([IO.Path]::GetDirectoryName((Get-ContentPath $g))) }
      foreach ($d in $seen) { & $add $kind $d ([string[]]@()) $false }
    }
  }
  return , $found
}

# A game's saves on this computer, the newest of each kind and name
function Get-LocalSaves($found, $game) {
  $newest = New-Map
  foreach ($f in @($found[(Get-SaveName $game)])) {
    if (-not $f) { continue }
    $key = "$($f.kind)/$($f.name)"
    if (-not $newest.ContainsKey($key) -or $newest[$key].mtime -lt $f.mtime) { $newest[$key] = $f }
  }
  $keys = [string[]]@($newest.Keys)
  $values = [object[]]@(foreach ($k in $keys) { $newest[$k] })
  [Array]::Sort($keys, $values, [StringComparer]::CurrentCulture)
  return , $values
}

# The files' fingerprint, the same wherever they are
function Get-SavesSignature($files) {
  if (-not @($files).Count) { return $null }
  $lines = [string[]]@(foreach ($f in $files) { "$($f['kind'])/$($f['name']):$($f['crc'])" })
  [Array]::Sort($lines, [StringComparer]::Ordinal)
  $sha = [Security.Cryptography.SHA1]::Create()
  return [BitConverter]::ToString($sha.ComputeHash($Utf8NoBom.GetBytes($lines -join "`n"))).Replace('-', '').ToLowerInvariant()
}
function Add-SavesCrc($files) {
  return , [object[]]@(foreach ($f in $files) {
    $c = $f.Clone()
    if (-not $c.crc) { $c.crc = Get-FileCrc $c.abs }
    $c
  })
}

function Get-SavesGameDir([string]$root, $game) {
  return [IO.Path]::Combine($root, $StoreSaves, $game.system, (Get-BaseOf $game.rel).Replace('/', '\'))
}

# The archive's copy of a game's saves: its manifest, or $null
function Get-ArchivedSaves([string]$root, $game) {
  return Read-JsonFile ([IO.Path]::Combine((Get-SavesGameDir $root $game), 'current', 'manifest.json')) $null
}

# How the saves of a game stand: none, local (only here), archive (only there), synced,
# local-newer, archive-newer or conflict. last is the signature of the last exchange.
function Get-SavesStatus($local, $manifest, $last) {
  $mine = Get-SavesSignature $local
  $theirs = if ($manifest) { $manifest['signature'] } else { $null }
  if (-not $mine -and -not $theirs) { return 'none' }
  if (-not $theirs) { return 'local' }
  if (-not $mine) { return 'archive' }
  if ($mine -ceq $theirs) { return 'synced' }
  if ($theirs -ceq $last) { return 'local-newer' }
  if ($mine -ceq $last) { return 'archive-newer' }
  return 'conflict'
}

function Get-SavesStamp { return [DateTime]::UtcNow.ToString('yyyy-MM-dd-HH-mm-ss', [Globalization.CultureInfo]::InvariantCulture) }

# Copies a game's saves into the archive; the copy there before goes to the history.
# Unless forced, refuses when the archive's copy changed since the last exchange.
function Send-Saves($ctx, $game, $found, $last, [bool]$force) {
  $root = $ctx.root
  $local = Add-SavesCrc (Get-LocalSaves $found $game)
  if (-not $local.Count) { throw (New-AppError 'This game has no saves here' 'none') }
  $manifest = Get-ArchivedSaves $root $game
  $state = Get-SavesStatus $local $manifest $last
  if ($state -ceq 'synced') { return Get-SavesSignature $local }
  if (-not $force -and ($state -ceq 'archive-newer' -or $state -ceq 'conflict')) { throw (New-AppError 'The archive has newer saves' 'conflict' $manifest) }
  $dir = Get-SavesGameDir $root $game
  $current = [IO.Path]::Combine($dir, 'current')
  if ($manifest) {
    $history = [IO.Path]::Combine($dir, 'history')
    New-Folder $history
    $device = if ($manifest['device']) { [string]$manifest['device'] } else { 'unknown' }
    Rename-Path $current ([IO.Path]::Combine($history, "$(Get-SavesStamp) $([regex]::Replace($device, '[<>:"/\\|?*]', ''))"))
    $old = [string[]]@(foreach ($d in [IO.Directory]::GetDirectories($history)) { [IO.Path]::GetFileName($d) })
    [Array]::Sort($old, [StringComparer]::Ordinal)
    [Array]::Reverse($old)
    foreach ($name in ($old | Select-Object -Skip $SavesHistory)) { Remove-Path ([IO.Path]::Combine($history, $name)) }
  }
  foreach ($f in $local) { Copy-Atomic $f.abs ([IO.Path]::Combine($current, $f.kind, $(if ($f.core) { $f.core } else { '_' }), $f.name)) }
  $files = @(foreach ($f in $local) { [ordered]@{ kind = $f.kind; core = $f.core; name = $f.name; size = $f.size; mtime = $f.mtime; crc = $f.crc } })
  $sig = Get-SavesSignature $local
  Write-Atomic ([IO.Path]::Combine($current, 'manifest.json')) (ConvertTo-JsonText ([ordered]@{ device = $ctx.device; saved = Get-IsoNow; signature = $sig; files = $files }) -Indent)
  return $sig
}

# Where RetroArch reads a save of a game from, in this computer's set-up
function Get-SaveTarget($ra, $game, $file, $core) {
  $k = $ra[[string]$file['kind']]
  $content = Get-ContentPath $game
  $dir = if ($k.inContent) { [IO.Path]::GetDirectoryName($content) } else { $k.root }
  if (-not $k.inContent) {
    if ($k.byContent) { $dir = [IO.Path]::Combine($dir, [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($content))) }
    # Saves go where this computer's core reads them, states stay with their own core
    $folder = if ($file['kind'] -ceq 'saves') { if ($core) { $core } else { $file['core'] } } else { if ($file['core']) { $file['core'] } else { $core } }
    if ($k.byCore -and $folder) { $dir = [IO.Path]::Combine($dir, $folder) }
  }
  return [IO.Path]::Combine($dir, [string]$file['name'])
}

# Brings a game's saves from the archive. Unless forced, refuses when the saves here
# changed since the last exchange. The saves here are copied aside first.
function Receive-Saves($ctx, $game, $found, $last, [bool]$force) {
  $root = $ctx.root
  $es = $ctx.es
  $manifest = Get-ArchivedSaves $root $game
  if (-not $manifest) { throw (New-AppError 'The archive has no saves of this game' 'none') }
  $local = Add-SavesCrc (Get-LocalSaves $found $game)
  $state = Get-SavesStatus $local $manifest $last
  if ($state -ceq 'synced') { return $manifest['signature'] }
  if (-not $force -and ($state -ceq 'local-newer' -or $state -ceq 'conflict')) { throw (New-AppError 'The saves here are newer' 'conflict' $manifest) }
  $all = @(foreach ($f in @($found[(Get-SaveName $game)])) { if ($f) { $f } })
  if ($all.Count) {
    $backup = [IO.Path]::Combine($ctx.dataDir, 'saves-backup', (Get-SavesStamp), $game.system, (Get-BaseOf $game.rel).Replace('/', '\'))
    foreach ($f in $all) {
      $to = [IO.Path]::Combine($backup, $f.kind, $(if ($f.core) { $f.core } else { '_' }), $f.name)
      New-Folder ([IO.Path]::GetDirectoryName($to))
      [IO.File]::Copy($f.abs, $to, $true)
    }
    foreach ($f in $all) { Remove-Path $f.abs }
  }
  $core = Get-GameCore $es $ctx.ra $game
  if ($core -ceq 'unknown') { $core = $null }
  $current = [IO.Path]::Combine((Get-SavesGameDir $root $game), 'current')
  foreach ($f in $manifest['files']) {
    $to = Get-SaveTarget $ctx.ra $game $f $core
    Copy-Atomic ([IO.Path]::Combine($current, [string]$f['kind'], $(if ($f['core']) { [string]$f['core'] } else { '_' }), [string]$f['name'])) $to
    [IO.File]::SetLastWriteTimeUtc($to, (ConvertFrom-Ms ([double]$f['mtime'])))
    [IO.File]::SetLastAccessTimeUtc($to, [DateTime]::UtcNow)
  }
  return $manifest['signature']
}
