# What Atelier's apps share on the server side: a small web server, reachable only from
# this computer, that serves the app's page from its ui folder in the theme, the shared
# page code in common/ui and the theme files the page may load; the look of the theme
# as ES-DE has it set up; and a full-screen Microsoft Edge window (or Chrome) that
# shows the page.
# Leaving the page ends both, which hands control back to ES-DE.
#
# Requests are answered side by side by a few PowerShell runspaces, so covers, badges
# and videos arrive together and a slow request never holds up the others; one more
# runspace does the app's background work in order. Each runspace loads the app's own
# script, whose functions answer the requests, and they all share $App, a synchronized
# hashtable with the app's state.

. ([IO.Path]::Combine($PSScriptRoot, 'base.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'esde.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'theme.ps1'))

$ServerTypes = @{
  '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
  '.json' = 'application/json'; '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'
  '.jpeg' = 'image/jpeg'; '.webp' = 'image/webp'; '.ttf' = 'font/ttf'; '.otf' = 'font/otf'; '.wav' = 'audio/wav'
  '.mp4' = 'video/mp4'; '.webm' = 'video/webm'; '.mkv' = 'video/x-matroska'; '.mov' = 'video/quicktime'
  '.avi' = 'video/x-msvideo'; '.wmv' = 'video/x-ms-wmv'; '.pdf' = 'application/pdf'
}
$ServerCommonUi = [IO.Path]::Combine($AtelierTheme, 'common', 'ui')
# The theme files the page may load: fonts, help icons, images, sounds and drawings
$ServerThemeDirs = @('core/', 'systems/controllers/')
# The most of a file one answer to a range request carries: a video plays on with the
# next request, and no runspace waits long on a paused one
$ServerChunk = 4MB

function Get-ContentType([string]$file) {
  $type = $ServerTypes[[IO.Path]::GetExtension($file).ToLowerInvariant()]
  if ($type) { return $type }
  return 'application/octet-stream'
}

function Close-Response($res) { try { $res.Close() } catch {} }

# An answer: a string or bytes as they are, anything else as JSON
function Send-Response($ctx, [int]$status, $body, [string]$type = 'application/json') {
  $res = $ctx.Response
  # Assigned in each branch: the value of an if would go through the bytes one by one
  if ($body -is [byte[]]) { $bytes = $body }
  elseif ($body -is [string]) { $bytes = $Utf8NoBom.GetBytes($body) }
  else { $bytes = $Utf8NoBom.GetBytes((ConvertTo-JsonText $body)) }
  try {
    $res.StatusCode = $status
    $res.ContentType = $type
    $res.AddHeader('Cache-Control', 'no-store')
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
  } catch {
  } finally {
    Close-Response $res
  }
}

function Send-NotFound($ctx) { Send-Response $ctx 404 @{ error = 'Not found' } }

function Send-File($ctx, [string]$file, [int]$maxAge = 0) {
  try { $bytes = [IO.File]::ReadAllBytes($file) } catch { return Send-NotFound $ctx }
  $res = $ctx.Response
  try {
    $res.StatusCode = 200
    $res.ContentType = Get-ContentType $file
    $res.AddHeader('Cache-Control', $(if ($maxAge) { "max-age=$maxAge" } else { 'no-cache' }))
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
  } catch {
  } finally {
    Close-Response $res
  }
}

# A file read as it is sent, in the part the request asks for: videos play while they
# arrive and jump about without being read whole, also from a network disk
function Send-Stream($ctx, [string]$file, [int]$maxAge = 0) {
  $info = [IO.FileInfo]::new($file)
  if (-not $info.Exists) { return Send-NotFound $ctx }
  $size = $info.Length
  $start = [long]0
  $end = $size - 1
  $range = [regex]::Match([string]$ctx.Request.Headers['Range'], '^bytes=(\d*)-(\d*)$')
  $partial = $range.Success -and ($range.Groups[1].Value -or $range.Groups[2].Value)
  $res = $ctx.Response
  if ($partial) {
    if ($range.Groups[1].Value) {
      $start = [long]$range.Groups[1].Value
      if ($range.Groups[2].Value) { $end = [Math]::Min([long]$range.Groups[2].Value, $end) }
      else { $end = [Math]::Min($end, $start + $ServerChunk - 1) }
    } else {
      $start = [Math]::Max(0, $size - [long]$range.Groups[2].Value)
    }
    if ($start -gt $end) {
      try {
        $res.StatusCode = 416
        $res.AddHeader('Content-Range', "bytes */$size")
      } catch {}
      return Close-Response $res
    }
  }
  $stream = $null
  try {
    $res.StatusCode = if ($partial) { 206 } else { 200 }
    $res.ContentType = Get-ContentType $file
    $res.AddHeader('Accept-Ranges', 'bytes')
    $res.AddHeader('Cache-Control', $(if ($maxAge) { "max-age=$maxAge" } else { 'no-cache' }))
    if ($partial) { $res.AddHeader('Content-Range', "bytes $start-$end/$size") }
    $res.ContentLength64 = $end - $start + 1
    if ($ctx.Request.HttpMethod -ne 'HEAD') {
      $stream = [IO.FileStream]::new($file, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite, 65536)
      [void]$stream.Seek($start, [IO.SeekOrigin]::Begin)
      $buffer = [byte[]]::new(262144)
      $left = $end - $start + 1
      while ($left -gt 0) {
        $n = $stream.Read($buffer, 0, [int][Math]::Min($buffer.Length, $left))
        if ($n -le 0) { break }
        $res.OutputStream.Write($buffer, 0, $n)
        $left -= $n
      }
    }
  } catch {
  } finally {
    if ($stream) { $stream.Dispose() }
    Close-Response $res
  }
}

# A path inside dir, or $null if the request tries to leave it
function Get-PathInside([string]$dir, [string]$rel) {
  try {
    $root = [IO.Path]::GetFullPath($dir).TrimEnd('\')
    $file = [IO.Path]::GetFullPath([IO.Path]::Combine($root, $rel))
  } catch {
    return $null
  }
  if ($file.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { return $file }
  return $null
}

# The JSON object or list in the body of a request, up to limit characters, or $null
function Read-RequestJson($ctx, [int]$limit = 2000) {
  try {
    $reader = [IO.StreamReader]::new($ctx.Request.InputStream, [Text.Encoding]::UTF8)
    $body = $reader.ReadToEnd()
    if ($body.Length -gt $limit) { $body = $body.Substring(0, $limit) }
    $value = [Atelier.Json]::Read($body)
    if ($value -is [Collections.IDictionary] -or $value -is [Collections.IList]) { return , $value }
  } catch {}
  return $null
}

# The page, its own files and the shared ones; true if the route was one of them
function Invoke-StaticRoute($ctx, [string]$route, [string]$uiDir) {
  if ($route -ceq '/') {
    Send-File $ctx ([IO.Path]::Combine($uiDir, 'index.html'))
    return $true
  }
  foreach ($pair in @(@('/ui/', $uiDir), @('/common/', $ServerCommonUi))) {
    if (-not $route.StartsWith($pair[0], [StringComparison]::Ordinal)) { continue }
    $file = Get-PathInside $pair[1] $route.Substring($pair[0].Length)
    if ($file) { Send-File $ctx $file } else { Send-NotFound $ctx }
    return $true
  }
  if ($route.StartsWith('/theme/', [StringComparison]::Ordinal)) {
    $rel = $route.Substring(7)
    $allowed = $false
    foreach ($dir in $ServerThemeDirs) { if ($rel.StartsWith($dir, [StringComparison]::Ordinal)) { $allowed = $true } }
    $file = if ($allowed) { Get-PathInside $ThemeRoot $rel } else { $null }
    if ($file) { Send-File $ctx $file 3600 } else { Send-NotFound $ctx }
    return $true
  }
  return $false
}

# The look and settings of ES-DE the page follows. The theme's part is read once per
# run, by whichever asks first, as it doesn't change while the app is open.
function Get-ThemeSession($es) {
  $lang = Get-EsdeLanguage $es
  $fontSize = Get-EsdeSetting $es 'ThemeFontSize'
  if (-not $fontSize) { $fontSize = 'medium' }
  [Threading.Monitor]::Enter($App.ThemeLock)
  try {
    if (-not $App.ThemeLook) {
      $App.ThemeLook = @{
        labels = Get-ThemeLabels $lang
        colors = Get-ThemeColors (Get-EsdeSetting $es 'ThemeColorScheme')
        systems = Get-ThemeSystems
        fontSizes = Get-ThemeFontSizes $fontSize
        layouts = Get-ThemeLayouts $fontSize
      }
    }
    $look = $App.ThemeLook
  } finally {
    [Threading.Monitor]::Exit($App.ThemeLock)
  }
  $aspect = Get-EsdeSetting $es 'ThemeAspectRatio'
  $controller = Get-EsdeSetting $es 'InputControllerType'
  $volume = Get-EsdeSetting $es 'SoundVolumeNavigation'
  return @{
    language = $lang
    labels = $look.labels
    colors = $look.colors
    systems = $look.systems
    fontSizes = $look.fontSizes
    layouts = $look.layouts
    aspectRatio = if ($aspect) { $aspect } else { 'automatic' }
    controller = if ($controller) { $controller } else { 'xbox' }
    sounds = (Get-EsdeSetting $es 'NavigationSounds') -cne 'false'
    volume = $(if ($volume) { [double]$volume } else { 70.0 }) / 100
  }
}

function Find-Browser {
  $roots = @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA) | Where-Object { $_ }
  foreach ($app in @(@('Microsoft', 'Edge', 'Application', 'msedge.exe'), @('Google', 'Chrome', 'Application', 'chrome.exe'))) {
    foreach ($root in $roots) {
      $file = [IO.Path]::Combine($root, [IO.Path]::Combine([string[]]$app))
      if ([IO.File]::Exists($file)) { return $file }
    }
  }
  return $null
}

function Get-FreePort {
  $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
  $probe.Start()
  $port = $probe.LocalEndpoint.Port
  $probe.Stop()
  return $port
}

# Ends the app: the page has closed its window, or will in a moment
function Request-Quit { [void]$App.Quit.Set() }

# Hands work to the background runspace, which calls the app's background function with
# it, one piece at a time
function Add-BackgroundTask($task) { $App.Tasks.Add($task) }

# Serves the app on a local port and opens the window, unless --no-window, which only
# prints the address, for testing in a browser. $App gets what the runspaces share. Each
# runspace loads $script (the app's app.ps1), which must not run its main part when
# dot-sourced; $handler is called with every request, $background with every task given
# to Add-BackgroundTask, and $beforeExit runs before the app ends, for work that must
# stop cleanly. $tasks are given to the background runspace at once, such as work that
# can be done while the window opens.
function Start-AppServer {
  param([string]$name, [string]$script, [string]$handler, [string]$dataDir, $argv,
    [string]$background, [string]$beforeExit, [object[]]$tasks = @(), [int]$workers = 8)
  $listener = $null
  $port = [int](Get-CliArg $argv '--port')
  for ($try = 0; -not $listener; $try++) {
    $candidate = [Net.HttpListener]::new()
    $usePort = if ($port) { $port } else { Get-FreePort }
    $candidate.Prefixes.Add("http://127.0.0.1:$usePort/")
    $candidate.IgnoreWriteExceptions = $true
    try {
      $candidate.Start()
      $listener = $candidate
      $url = "http://127.0.0.1:$usePort/"
    } catch {
      if ($port -or $try -ge 5) { throw }
    }
  }
  $App.Listener = $listener
  $App.Quit = [Threading.ManualResetEvent]::new($false)
  $App.Tasks = [Collections.Concurrent.BlockingCollection[object]]::new()
  $App.ThemeLock = [object]::new()
  foreach ($task in $tasks) { $App.Tasks.Add($task) }

  $worker = {
    param($App, $script, $handler)
    . $script
    while ($App.Listener.IsListening) {
      try { $ctx = $App.Listener.GetContext() } catch { break }
      try {
        & $handler $ctx
      } catch {
        Write-Failure "$($ctx.Request.HttpMethod) $($ctx.Request.Url.AbsolutePath): $(Get-ErrorMessage $_)"
        Send-Response $ctx 500 @{ error = Get-ErrorMessage $_ }
      }
    }
  }
  $runner = {
    param($App, $script, $background)
    . $script
    foreach ($task in $App.Tasks.GetConsumingEnumerable()) {
      try { & $background $task } catch { Write-Failure "$($task.kind): $(Get-ErrorMessage $_)" }
    }
  }
  $App.Runspaces = New-List
  for ($i = 0; $i -lt $workers; $i++) {
    $ps = [powershell]::Create()
    [void]$ps.AddScript($worker).AddArgument($App).AddArgument($script).AddArgument($handler)
    $App.Runspaces.Add(@{ ps = $ps; handle = $ps.BeginInvoke() })
  }
  if ($background) {
    $ps = [powershell]::Create()
    [void]$ps.AddScript($runner).AddArgument($App).AddArgument($script).AddArgument($background)
    $App.Runspaces.Add(@{ ps = $ps; handle = $ps.BeginInvoke() })
  }

  $end = {
    if ($beforeExit) { try { & $beforeExit } catch { Write-Failure (Get-ErrorMessage $_) } }
  }
  if (Test-CliFlag $argv '--no-window') {
    Write-Line "${name}: $url"
    while (-not $App.Quit.WaitOne(500)) {}
    & $end
    Start-Sleep -Milliseconds 200
    [Environment]::Exit(0)
  }
  $exe = Find-Browser
  if (-not $exe) {
    Write-Failure "Microsoft Edge or Google Chrome is needed to show $name."
    [Environment]::Exit(1)
  }
  # Its own profile, so the window is a process of its own that ends when it closes
  $browserArgs = @("--user-data-dir=$([IO.Path]::Combine($dataDir, 'browser'))", '--no-first-run', '--no-default-browser-check',
    '--autoplay-policy=no-user-gesture-required', '--kiosk', '--edge-kiosk-type=fullscreen', $url)
  $info = [Diagnostics.ProcessStartInfo]::new($exe, [Atelier.Runner]::Join($browserArgs))
  $info.UseShellExecute = $false
  $browser = [Diagnostics.Process]::Start($info)
  while ($true) {
    if ($App.Quit.WaitOne(200)) {
      & $end
      # The page closes its window; this only cleans up if it couldn't
      if (-not $browser.WaitForExit(3000)) { [void](Invoke-Program 'taskkill.exe' @('/PID', [string]$browser.Id, '/T', '/F') 5000) }
      [Environment]::Exit(0)
    }
    if ($browser.HasExited) {
      & $end
      [Environment]::Exit(0)
    }
  }
}
