# The user's ES-DE games matched with RetroAchievements: each game file is identified
# by its hash, which is looked up in the site's list of supported files for its console.
# The hashes are remembered by file size and date, so only new or changed files are
# read again. A file whose hash isn't listed is matched by title instead and marked as
# an unsupported version: RetroArch won't unlock anything with it, but the app can
# still show the game's achievements and which versions the site supports.
#
# The configuration (Web API key and username) and the cache live in
# <ES-DE home>/atelier/achievements, outside the theme folder, so updating or
# reinstalling the theme keeps them and the key never ends up in a copy of the theme.
#
# Run on its own it prints the matches:
#   powershell -File library.ps1 [--app <ES-DE application folder>] [--data <folder>]

. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'esde.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'ra.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'consoles.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'rhash.ps1'))

# "Lion King, The (USA)" and "The Lion King" both become "lion king"
function Get-TitleKey([string]$s) {
  $s = [regex]::Replace($s, '[(\[][^)\]]*[)\]]', ' ')
  $s = [regex]::Replace($s, '^(.*), (the|a|an)\b', '$2 $1', 'IgnoreCase').ToLowerInvariant()
  $s = [regex]::Replace($s, '^(the|a|an) ', '').Replace('&', 'and')
  return [regex]::Replace($s, '[^a-z0-9]+', ' ').Trim()
}

# ES-DE, the configuration and, unless configOnly, the RetroAchievements client
function Open-Achievements([string]$appArg, [string]$dataArg, [switch]$configOnly) {
  $es = Open-Esde $appArg
  $dataDir = if ($dataArg) { [IO.Path]::GetFullPath($dataArg) } else { [IO.Path]::Combine($es.home, 'atelier', 'achievements') }
  $configFile = [IO.Path]::Combine($dataDir, 'config.json')
  $config = if ([IO.File]::Exists($configFile)) { [Atelier.Json]::Read([IO.File]::ReadAllText($configFile)) } else { New-Map }
  if ($configOnly) { return @{ es = $es; dataDir = $dataDir; config = $config } }
  if (-not $config['apiKey']) { throw 'Retro Achievements is not signed in yet: open Retro Achievements in ES-DE and enter your username and Web API key.' }
  $ra = New-RaClient $config['apiKey'] $config['username'] ([IO.Path]::Combine($dataDir, 'cache'))
  return @{ es = $es; ra = $ra; dataDir = $dataDir; config = $config }
}

function Find-RaGames($ctx) {
  $es = $ctx.es
  $hashesFile = [IO.Path]::Combine($ctx.dataDir, 'hashes.json')
  $known = if ([IO.File]::Exists($hashesFile)) { [Atelier.Json]::Read([IO.File]::ReadAllText($hashesFile)) } else { New-Map }
  $seen = New-Map
  $lists = @{}
  $games = New-List
  foreach ($game in (Get-EsdeAllGames $es)) {
    $consoleId = Get-RaConsole $game.system
    if (-not $consoleId) { continue }
    $info = [IO.FileInfo]::new($game.file)
    $stamp = "$($info.Length):$([Atelier.Json]::Number([Atelier.Files]::MtimeMs($game.file)))"
    $id = $known[$game.file]
    if (-not $id -or $id['stamp'] -cne $stamp) {
      $id = [ordered]@{ stamp = $stamp }
      try {
        $hashed = Get-GameHash $game.file $consoleId $es.systems[$game.system].extensions
        foreach ($k in $hashed.Keys) { $id[$k] = $hashed[$k] }
      } catch {
        $id['unsupported'] = Get-ErrorMessage $_
      }
    }
    $seen[$game.file] = $id
    $entry = $game.Clone()
    $entry.hash = if ($id['hash']) { $id['hash'] } else { $null }
    $entry.consoleId = if ($id['consoleId']) { [int]$id['consoleId'] } else { $consoleId }
    $entry.ra = $null
    $entry.supported = $false
    $entry.note = if ($id['unsupported']) { $id['unsupported'] } else { $null }
    $list = $lists[$entry.consoleId]
    if (-not $list) {
      $byHash = New-Map
      $byTitle = New-Map
      foreach ($g in (Get-RaGames $ctx.ra $entry.consoleId)) {
        foreach ($h in @($g['Hashes'])) { if ($h) { $byHash[([string]$h).ToLowerInvariant()] = $g } }
        $key = Get-TitleKey $g['Title']
        if (-not $byTitle.ContainsKey($key)) { $byTitle[$key] = $g }
      }
      $list = @{ byHash = $byHash; byTitle = $byTitle }
      $lists[$entry.consoleId] = $list
    }
    $exact = if ($entry.hash) { $list.byHash[$entry.hash] } else { $null }
    $match = $exact
    if (-not $match) { $match = $list.byTitle[(Get-TitleKey $game.name)] }
    if (-not $match) { $match = $list.byTitle[(Get-TitleKey ([IO.Path]::GetFileName($game.file)))] }
    if ($match) {
      $entry.ra = [ordered]@{ id = $match['ID']; title = $match['Title']; icon = $match['ImageIcon']; achievements = $match['NumAchievements']; points = $match['Points'] }
      $entry.supported = [bool]$exact
      if (-not $exact -and $entry.hash) { $entry.note = 'this version of the game is not supported' }
    } elseif ($entry.hash) {
      $entry.note = 'no achievements for this game'
    }
    $games.Add($entry)
  }
  New-Folder $ctx.dataDir
  Write-TextFile $hashesFile (ConvertTo-JsonText $seen -Indent)
  return , $games
}

if ($MyInvocation.InvocationName -ne '.') {
  try {
    $ctx = Open-Achievements (Get-CliArg $args '--app') (Get-CliArg $args '--data')
    $games = Find-RaGames $ctx
    foreach ($g in $games) {
      $result = if ($g.ra) { "$($g.ra.title) (game $($g.ra.id), $($g.ra.achievements) achievements)" } else { '-' }
      Write-Line ('{0} {1} {2}{3}' -f $g.system.PadRight(8), $g.name.PadRight(28), $result, $(if ($g.note) { ": $($g.note)" } else { '' }))
    }
    $supported = @($games | Where-Object { $_.supported }).Count
    $other = @($games | Where-Object { $_.ra -and -not $_.supported }).Count
    Write-Line "$supported of $($games.Count) games can unlock achievements, $other more need another version of the file"
  } catch {
    Write-Failure (Get-ErrorMessage $_)
    exit 1
  }
}
