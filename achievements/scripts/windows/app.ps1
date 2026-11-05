# The achievements app: a small web server, reachable only from this computer, that
# serves the page in the theme's achievements/ui and the data it shows, and a
# full-screen Microsoft Edge window (or Chrome) that shows it, see
# common/scripts/windows/server.ps1. Leaving the page ends both, which hands control
# back to ES-DE. The Web API key stays in this process; the page never sees it, it only
# sends a new one when the user signs in there. Until then the page asks for the
# username, which comes from RetroArch when it is signed in, and the key.
#
# The library is matched while the window opens, with the site asked for the user's
# progress at the same time; the badges of every game are then fetched in the
# background, one game after the other, so browsing doesn't wait.
#
# Usage: powershell -File app.ps1 [--app <ES-DE application folder>] [--data <folder>]
#                                 [--port <number>] [--no-window]
# --no-window only starts the server and prints its address, for testing in a browser.

. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'server.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'retroarch.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'library.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'progress.ps1'))

$AchievementsUi = [IO.Path]::Combine($AtelierTheme, 'achievements', 'ui')

function Get-AchievementsSession {
  $config = $App.Ctx.config
  $suggested = $config['username']
  if (-not $suggested) {
    try {
      $found = Find-RetroArch $App.Es
      if ($found) { $suggested = $found.config['cheevos_username'] }
    } catch {}
  }
  $session = Get-ThemeSession $App.Es
  $session.username = if ($config['username']) { $config['username'] } else { $null }
  # The username to offer when signing in: the saved one, or RetroArch's
  $session.suggestedUser = if ($suggested) { $suggested } else { $null }
  $session.hasKey = [bool]$config['apiKey']
  $session.setupError = $App.SetupError
  $session.prefs = Read-JsonFile ([IO.Path]::Combine($App.DataDir, 'prefs.json')) (New-Map)
  return $session
}

function Reset-AchievementsLibrary {
  $App.Library = $null
  $App.Games = New-List
  $App.Details.Clear()
}

# Signs in to RetroAchievements: checks the username and Web API key with the site and
# keeps them in config.json; an empty key keeps the saved one. { ok, username } or
# { ok: false, reason: missing, user, key or offline }
function Invoke-SignIn($body) {
  if (-not $body) { $body = @{} }
  $username = ([string]$body['username']).Trim()
  $apiKey = ([string]$body['apiKey']).Trim()
  if (-not $apiKey) { $apiKey = [string]$App.Ctx.config['apiKey'] }
  if (-not $username -or -not $apiKey) { return @{ ok = $false; reason = 'missing' } }
  try {
    $profile = Get-RaProfile (New-RaClient $apiKey $username ([IO.Path]::Combine($App.DataDir, 'cache')))
  } catch {
    return @{ ok = $false; reason = $(if ((Get-RaStatus $_) -eq 401) { 'key' } else { 'offline' }); message = Get-ErrorMessage $_ }
  }
  if (-not $profile) { return @{ ok = $false; reason = 'user' } }
  New-Folder $App.DataDir
  Write-TextFile ([IO.Path]::Combine($App.DataDir, 'config.json')) (ConvertTo-JsonText ([ordered]@{ username = $profile['User']; apiKey = $apiKey }) -Indent)
  [Threading.Monitor]::Enter($App.LibraryLock)
  try {
    $App.Ctx = Open-Achievements $App.AppArg $App.DataArg
    $App.SetupError = $null
    Reset-AchievementsLibrary
  } finally {
    [Threading.Monitor]::Exit($App.LibraryLock)
  }
  return @{ ok = $true; username = $profile['User'] }
}

# The view and order chosen in the app's options menu
function Save-AchievementsPrefs($body) {
  if (-not ($body -is [Collections.IDictionary])) { return }
  try {
    New-Folder $App.DataDir
    Write-TextFile ([IO.Path]::Combine($App.DataDir, 'prefs.json')) (ConvertTo-JsonText ([ordered]@{ mode = [string]$body['mode']; sort = [string]$body['sort'] }))
  } catch {}
}

# The user's games that have achievements, with how far they got, and their profile:
# built once, by whichever asks first
function Get-AchievementsLibrary {
  [Threading.Monitor]::Enter($App.LibraryLock)
  try {
    if (-not $App.Library) { $App.Library = Build-AchievementsLibrary }
    return $App.Library
  } finally {
    [Threading.Monitor]::Exit($App.LibraryLock)
  }
}

function Build-AchievementsLibrary {
  $ctx = $App.Ctx
  $ra = $ctx.ra
  # The site is asked while the games are matched
  $completionCall = $null
  $summaryCall = $null
  try { $completionCall = Start-RaCompletion $ra } catch {}
  try { $summaryCall = Start-RaSummary $ra } catch {}
  $matched = New-List
  foreach ($g in (Find-RaGames $ctx)) { if ($g.ra) { $matched.Add($g) } }
  $completion = $null
  $profile = $null
  try { $completion = Get-RaCompletion $ra $completionCall } catch {}
  try { $profile = Get-RaSummary $ra $summaryCall } catch {}
  # The progress images in ES-DE, redrawn after the page has its data; never from an
  # empty answer, which would show no unlocks
  if ($completion -and (Test-ProgressOn $App.DataDir)) {
    Add-BackgroundTask @{ kind = 'progress'; entries = (Get-ProgressEntries $matched $completion) }
  }
  $progress = @{}
  foreach ($c in @($completion)) { if ($c) { $progress[[int]$c['GameID']] = $c } }
  $names = @(foreach ($g in $matched) { $g.name })
  $games = [Atelier.NameComparer]::Sort($matched, $names, $null, (Get-EsdeLanguage $App.Es))
  $App.Games = $games
  Add-BackgroundTask @{ kind = 'prefetch' }
  $list = New-List
  for ($i = 0; $i -lt $games.Count; $i++) {
    $g = $games[$i]
    $p = $progress[[int]$g.ra.id]
    $media = @{}
    foreach ($type in 'screenshots', 'titlescreens', 'fanart', 'covers') { $media[$type] = if ($g.media[$type]) { "/media/$i/$type" } else { $null } }
    $list.Add(@{
      index = $i; name = $g.name; system = $g.system; systemName = $g.systemName; description = $g.description
      image = $(if ($media.screenshots) { $media.screenshots } else { $media.titlescreens })
      backdrop = $(if ($media.fanart) { $media.fanart } else { $media.screenshots })
      cover = $media.covers
      # Files that couldn't be hashed (some disc images) aren't known to be unsupported
      ra = $g.ra; supported = ($g.supported -or -not $g.hash); note = $g.note
      progress = $(if ($p) {
        @{ awarded = $p['NumAwarded']; awardedHardcore = $p['NumAwardedHardcore']; max = $p['MaxPossible']; award = $p['HighestAwardKind']
          last = $p['MostRecentAwardedDate'] }
      } else { $null })
    })
  }
  $user = if ($profile) { @{ name = $profile['User']; points = $profile['TotalPoints']; softcorePoints = $profile['TotalSoftcorePoints'] } } else { $null }
  return @{ user = $user; games = $list }
}

function Get-OrNull($value) { if ($value) { return $value } else { return $null } }

# A game's achievements and the user's unlocks: fetched once per run, from the cache
# when the site can't be reached
function Get-GameDetails([int]$id) {
  $done = $null
  if ($App.Details.TryGetValue($id, [ref]$done)) { return $done }
  $lock = $App.DetailLocks.GetOrAdd($id, [object]::new())
  [Threading.Monitor]::Enter($lock)
  try {
    if ($App.Details.TryGetValue($id, [ref]$done)) { return $done }
    $data = Get-RaGame $App.Ctx.ra $id
    $unsupported = $false
    foreach ($g in $App.Games) { if ($g.ra.id -eq $id -and -not $g.supported) { $unsupported = $true; break } }
    $versions = New-List
    if ($unsupported) {
      try { foreach ($r in (Get-RaVersions $App.Ctx.ra $id)['Results']) { $versions.Add($r['Name']) } } catch {}
    }
    $achievements = @()
    if ($data['Achievements'] -is [Collections.IDictionary]) {
      $achievements = @($data['Achievements'].Values | Sort-Object { [double]$_['DisplayOrder'] }, { [double]$_['ID'] })
    }
    $boxArt = Get-OrNull $data['ImageBoxArt']
    $result = @{
      id = $data['ID']; title = $data['Title']; genre = $data['Genre']; players = $data['NumDistinctPlayers']
      playtime = $(if ($data['UserTotalPlaytime']) { $data['UserTotalPlaytime'] } else { 0 }); award = Get-OrNull $data['HighestAwardKind']
      versions = $versions; boxArt = $(if ($boxArt) { ([string]$boxArt) -replace '^/', '' } else { $null })
      achievements = @(foreach ($a in $achievements) {
        @{
          id = $a['ID']; title = $a['Title']; description = $a['Description']; points = $a['Points']; retroPoints = $a['TrueRatio']
          type = Get-OrNull $a['Type']; badge = $a['BadgeName']; awarded = $a['NumAwarded']; awardedHardcore = $a['NumAwardedHardcore']
          author = $a['Author']; earned = Get-OrNull $a['DateEarned']; earnedHardcore = Get-OrNull $a['DateEarnedHardcore']
        }
      })
    }
    $App.Details[$id] = $result
    return $result
  } finally {
    [Threading.Monitor]::Exit($lock)
  }
}

# The work of the background runspace: the theme's look and the library while the
# window opens, the progress images, and the badges of the other games, one at a time
function Invoke-AchievementsBackground($task) {
  switch ($task.kind) {
    'warm-up' {
      [void](Get-ThemeSession $App.Es)
      if (-not $App.SetupError) { [void](Get-AchievementsLibrary) }
    }
    'progress' {
      Start-Sleep -Milliseconds 500
      try { [void](Update-ProgressImages $App.Es $task.entries) } catch { Write-Failure (Get-ErrorMessage $_) }
    }
    'prefetch' {
      Start-Sleep -Milliseconds 1500
      $ids = [Collections.Generic.HashSet[int]]::new()
      foreach ($g in $App.Games) {
        if ($ids.Add([int]$g.ra.id)) { try { [void](Get-GameDetails ([int]$g.ra.id)) } catch {} }
      }
    }
  }
}

function Invoke-AchievementsRequest($ctx) {
  $route = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath)
  $post = $ctx.Request.HttpMethod -eq 'POST'
  if (Invoke-StaticRoute $ctx $route $AchievementsUi) { return }
  if ($route -ceq '/api/session') { return Send-Response $ctx 200 (Get-AchievementsSession) }
  if ($route -ceq '/api/games') {
    if ($App.SetupError) { return Send-Response $ctx 409 @{ error = $App.SetupError } }
    return Send-Response $ctx 200 (Get-AchievementsLibrary)
  }
  if ($route -ceq '/api/game') { return Send-Response $ctx 200 (Get-GameDetails ([int]$ctx.Request.QueryString['id'])) }
  $m = [regex]::Match($route, '^/media/(\d+)/(\w+)$')
  if ($m.Success) {
    $i = [int]$m.Groups[1].Value
    $file = if ($i -lt @($App.Games).Count) { $App.Games[$i].media[$m.Groups[2].Value] } else { $null }
    if ($file) { return Send-File $ctx $file 3600 }
    return Send-NotFound $ctx
  }
  $m = [regex]::Match($route, '^/ra/((?:Badge|Images)/[\w-]+\.png)$')
  if ($m.Success) { return Send-File $ctx (Get-RaImage $App.Ctx.ra $m.Groups[1].Value) 86400 }
  if ($route -ceq '/api/account' -and $post) { return Send-Response $ctx 200 (Invoke-SignIn (Read-RequestJson $ctx)) }
  if ($route -ceq '/api/prefs' -and $post) {
    Save-AchievementsPrefs (Read-RequestJson $ctx)
    return Send-Response $ctx 200 @{ ok = $true }
  }
  if ($route -ceq '/api/quit' -and $post) {
    Send-Response $ctx 200 @{ ok = $true }
    return Request-Quit
  }
  Send-NotFound $ctx
}

if ($MyInvocation.InvocationName -ne '.') {
  $argv = $args
  $App = [hashtable]::Synchronized(@{})
  try {
    $App.AppArg = Get-CliArg $argv '--app'
    $App.DataArg = Get-CliArg $argv '--data'
    $App.Ctx = Open-Achievements $App.AppArg $App.DataArg -configOnly
  } catch {
    Write-Failure (Get-ErrorMessage $_)
    exit 1
  }
  $App.Es = $App.Ctx.es
  $App.DataDir = $App.Ctx.dataDir
  $App.SetupError = $null
  try { $App.Ctx = Open-Achievements $App.AppArg $App.DataArg } catch { $App.SetupError = Get-ErrorMessage $_ }
  $App.LibraryLock = [object]::new()
  $App.Details = [Collections.Concurrent.ConcurrentDictionary[int, object]]::new()
  $App.DetailLocks = [Collections.Concurrent.ConcurrentDictionary[int, object]]::new()
  $App.Library = $null
  $App.Games = New-List
  Start-AppServer -name 'Achievements' -script $PSCommandPath -handler 'Invoke-AchievementsRequest' -dataDir $App.DataDir -argv $argv `
    -background 'Invoke-AchievementsBackground' -tasks @(@{ kind = 'warm-up' })
}
