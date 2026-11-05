# Talks to the RetroAchievements web API (https://api-docs.retroachievements.org) with
# the user's own Web API key, and keeps every answer in the cache folder: the app then
# opens at once with the last data it saw, refreshes it in the background, and still
# works offline. A request can be started and its answer taken later, so that the app
# waits for the site while it does other work.

. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'base.ps1'))
Add-Type -AssemblyName System.Net.Http

$RaBase = 'https://retroachievements.org/API/'
$RaMedia = 'https://media.retroachievements.org/'
$RaAgent = 'Atelier-ES-DE-Achievements/1.0'
$RaDay = 24 * 60 * 60 * 1000
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::DefaultConnectionLimit = 16
$RaHttp = [Net.Http.HttpClient]::new()
$RaHttp.Timeout = [TimeSpan]::FromSeconds(15)
[void]$RaHttp.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', $RaAgent)

function New-RaClient([string]$apiKey, [string]$username, [string]$cacheDir) {
  if (-not $apiKey) { throw 'No Retro Achievements Web API key in the configuration' }
  New-Folder $cacheDir
  return @{ apiKey = $apiKey; username = $username; cacheDir = $cacheDir }
}

# A request under way, and its answer: { status, bytes }; a site that can't be reached
# throws
function Start-RaGet([string]$url) { return $RaHttp.GetAsync($url) }
function Receive-RaGet($task) {
  try {
    $res = $task.GetAwaiter().GetResult()
  } catch {
    throw (New-AppError "Retro Achievements can't be reached: $(Get-ErrorMessage $_)" 'offline')
  }
  try {
    return @{ status = [int]$res.StatusCode; bytes = $res.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult() }
  } finally {
    $res.Dispose()
  }
}

function Start-RaCall($ra, [string]$endpoint, $params) {
  $query = @(foreach ($k in $params.Keys) { "$k=$([Uri]::EscapeDataString([string]$params[$k]))" }) + "y=$([Uri]::EscapeDataString($ra.apiKey))"
  return @{ endpoint = $endpoint; task = Start-RaGet "$RaBase$endpoint.php?$($query -join '&')" }
}
function Receive-RaCall($call) {
  $answer = Receive-RaGet $call.task
  if ($answer.status -eq 401) {
    $e = New-AppError 'Retro Achievements refused the Web API key' 'key'
    $e.Status = 401
    throw $e
  }
  if ($answer.status -lt 200 -or $answer.status -ge 300) {
    $e = New-AppError "Retro Achievements answered $($answer.status) for $($call.endpoint)" 'status'
    $e.Status = $answer.status
    throw $e
  }
  return , [Atelier.Json]::Read($Utf8NoBom.GetString($answer.bytes))
}
function Invoke-RaCall($ra, [string]$endpoint, $params) { return , (Receive-RaCall (Start-RaCall $ra $endpoint $params)) }
function Get-RaStatus($err) {
  $ex = Get-InnerError $err
  if ($ex -is [Atelier.AppException]) { return $ex.Status }
  return 0
}

# The cached answer if it is younger than maxAge, else a fresh one; the cached answer
# again if the site can't be reached. The fetcher runs here: its own variables must not
# be called cacheName, cacheFile, stale or fresh.
function Get-RaCached($ra, [string]$cacheName, [double]$maxAge, [scriptblock]$fetcher) {
  $cacheFile = [IO.Path]::Combine($ra.cacheDir, "$cacheName.json")
  $stale = $null
  if ([IO.File]::Exists($cacheFile)) {
    $stale = Read-JsonFile $cacheFile
    if ($stale -and (Get-NowMs) - $stale['time'] -lt $maxAge) { return , $stale['data'] }
  }
  try {
    $fresh = & $fetcher
    Write-Atomic $cacheFile (ConvertTo-JsonText ([ordered]@{ time = Get-NowMs; data = $fresh }))
    return , $fresh
  } catch {
    if ($stale) { return , $stale['data'] }
    throw
  }
}

# The user's public profile, or $null if there is no such user (never cached)
function Get-RaProfile($ra) {
  try {
    return , (Invoke-RaCall $ra 'API_GetUserProfile' @{ u = $ra.username })
  } catch {
    if ((Get-RaStatus $_) -in 404, 422) { return $null }
    throw
  }
}

# Every game of a console that has achievements, with the hashes of its supported files
function Get-RaGames($ra, [int]$consoleId) {
  return , (Get-RaCached $ra "games-$consoleId" (7 * $RaDay) { , (Invoke-RaCall $ra 'API_GetGameList' ([ordered]@{ i = $consoleId; f = 1; h = 1 })) })
}

# The files a game supports, by name, for games whose version isn't among them
function Get-RaVersions($ra, [int]$gameId) {
  return , (Get-RaCached $ra "versions-$gameId" (7 * $RaDay) { , (Invoke-RaCall $ra 'API_GetGameHashes' @{ i = $gameId }) })
}

# A game's achievements, with the user's unlocks when a username is configured
function Get-RaGame($ra, [int]$gameId, [double]$maxAge = 0) {
  return , (Get-RaCached $ra "game-$gameId" $maxAge {
    if ($ra.username) { , (Invoke-RaCall $ra 'API_GetGameInfoAndUserProgress' ([ordered]@{ g = $gameId; u = $ra.username; a = 1 })) }
    else { , (Invoke-RaCall $ra 'API_GetGameExtended' @{ i = $gameId }) }
  })
}

# The user's profile and points, kept for offline use; $profileCall is one already
# started, if there is
function Get-RaSummary($ra, $profileCall = $null) {
  if (-not $ra.username) { return $null }
  return , (Get-RaCached $ra 'profile' 0 {
    if ($profileCall) { , (Receive-RaCall $profileCall) } else { , (Invoke-RaCall $ra 'API_GetUserProfile' @{ u = $ra.username }) }
  })
}
function Start-RaSummary($ra) {
  if (-not $ra.username) { return $null }
  return Start-RaCall $ra 'API_GetUserProfile' @{ u = $ra.username }
}

# How far the user got in every game they played, in pages of 500; $firstCall is the
# first page already asked for, if it is
function Get-RaCompletion($ra, $firstCall = $null) {
  if (-not $ra.username) { return , (New-List) }
  return , (Get-RaCached $ra 'completion' 0 {
    $results = New-List
    $total = [double]::PositiveInfinity
    $call = $firstCall
    while ($results.Count -lt $total) {
      if (-not $call) { $call = Start-RaCall $ra 'API_GetUserCompletionProgress' ([ordered]@{ u = $ra.username; c = 500; o = $results.Count }) }
      $page = Receive-RaCall $call
      $call = $null
      foreach ($r in $page['Results']) { $results.Add($r) }
      $total = if (@($page['Results']).Count) { [double]$page['Total'] } else { 0 }
    }
    , $results
  })
}
function Start-RaCompletion($ra) {
  if (-not $ra.username) { return $null }
  return Start-RaCall $ra 'API_GetUserCompletionProgress' ([ordered]@{ u = $ra.username; c = 500; o = 0 })
}

# A badge or game image from the site's media server, such as Badge/711081.png,
# downloaded once
function Get-RaImage($ra, [string]$remote) {
  $file = [IO.Path]::Combine($ra.cacheDir, 'media', $remote.Replace('/', '\'))
  if (-not [IO.File]::Exists($file)) {
    $answer = Receive-RaGet (Start-RaGet "$RaMedia$remote")
    if ($answer.status -lt 200 -or $answer.status -ge 300) { throw "No image $remote" }
    New-Folder ([IO.Path]::GetDirectoryName($file))
    $temp = "$file.$PID.$([Threading.Thread]::CurrentThread.ManagedThreadId).tmp"
    [IO.File]::WriteAllBytes($temp, $answer.bytes)
    Rename-Path $temp $file
  }
  return $file
}
