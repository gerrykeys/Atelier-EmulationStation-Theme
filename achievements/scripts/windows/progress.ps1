# Achievement progress in ES-DE's game details: for every game with achievements a
# small image, "12 / 74", a bar and the percentage, which the theme shows beside the
# game's facts (raProgress in layout/gamelist-details.xml and gamelist-gallery.xml).
# ES-DE has no field of its own for it, so the images take the place of the physical
# media images, which Atelier shows nowhere else. Those already there, scraped before
# or after, are moved to <ES-DE home>/atelier/physicalmedia-backup and put back when
# the progress is turned off. The images are white; the theme tints them with the
# accent color of the scheme. Each carries its figures in a PNG text chunk, which tells
# it apart from the user's own images and saves redrawing it when nothing changed.
#
# While the progress is on, the achievements app redraws the images each time it opens.
# Usage: powershell -File progress.ps1 [--off] [--app <ES-DE application folder>] [--data <folder>]
# On Windows, "Retro Achievements - Enable Progress Bar in ES-DE.cmd" and
# "Retro Achievements - Disable Progress Bar in ES-DE.cmd" in the theme's
# scripts/runnable/windows folder.

. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'images.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'library.ps1'))

$ProgressType = 'physicalmedia'
# Raised whenever the drawing changes, so that every image is drawn again
$ProgressVersion = 2
# Canvas height, and the length of the bar and the room for the percentage, in pixels
$ProgressHeight = 100
$ProgressBar = 360
$ProgressPercent = 230
$ProgressGap = 48

# The version and figures an image of ours was drawn with, such as "2 12/74", or $null
# for any other file
function Get-ProgressMarker([string]$file) {
  # The semicolon ends the figures before the chunk's checksum
  $m = [regex]::Match((Read-FileHead $file 120), 'Atelier achievement progress ([\d /]+)')
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}

function Get-FilesUnder([string]$dir) {
  if (-not [IO.Directory]::Exists($dir)) { return , @() }
  return , [IO.Directory]::GetFiles($dir, '*', [IO.SearchOption]::AllDirectories)
}

# Every system's physical media folder
function Get-ProgressFolders($es) {
  if (-not [IO.Directory]::Exists($es.mediaDir)) { return , @() }
  return , @(foreach ($dir in [IO.Directory]::GetDirectories($es.mediaDir)) {
    $media = [IO.Path]::Combine($dir, $ProgressType)
    if ([IO.Directory]::Exists($media)) { @{ system = [IO.Path]::GetFileName($dir); dir = $media } }
  })
}
function Get-ProgressBackupDir($es) { return [IO.Path]::Combine($es.home, 'atelier', 'physicalmedia-backup') }
function Get-ProgressFlagFile([string]$dataDir) { return [IO.Path]::Combine($dataDir, 'progress.json') }

# The theme shows the images only while the progress is on, so that the physical media
# images of a library without it never appear in their place. The switch is a variable
# in the theme's achievements/progress.xml; a reinstalled theme gets it back on the app's
# next start.
function Set-ProgressInTheme([bool]$on) {
  $file = [IO.Path]::Combine($AtelierTheme, 'achievements', 'progress.xml')
  $xml = [IO.File]::ReadAllText($file)
  $next = [regex]::Replace($xml, '<raProgressVisible>\w+</raProgressVisible>', "<raProgressVisible>$($on.ToString().ToLowerInvariant())</raProgressVisible>")
  if ($next -cne $xml) { Write-TextFile $file $next }
}

function Remove-EmptyFolders([string]$dir) {
  if (-not [IO.Directory]::Exists($dir)) { return }
  foreach ($sub in [IO.Directory]::GetDirectories($dir)) { Remove-EmptyFolders $sub }
  if (-not [IO.Directory]::EnumerateFileSystemEntries($dir).GetEnumerator().MoveNext()) { [IO.Directory]::Delete($dir) }
}

# The figures to draw for the matched games of library.ps1 and the user's completion
# progress from the site
function Get-ProgressEntries($games, $completion) {
  $byGame = @{}
  foreach ($c in $completion) { $byGame[[int]$c['GameID']] = $c }
  $out = New-List
  foreach ($g in $games) {
    if (-not $g.ra) { continue }
    $c = $byGame[[int]$g.ra.id]
    $total = if ($c -and $c['MaxPossible']) { $c['MaxPossible'] } else { $g.ra.achievements }
    $out.Add(@{ system = $g.system; relPath = $g.relPath; unlocked = $(if ($c) { $c['NumAwarded'] } else { 0 }); total = $total })
  }
  return , $out
}

# The PNG of one game's figures; widths keeps the width of each "12 / 74" drawn
function New-ProgressPng([int]$unlocked, [int]$total, $widths = @{}) {
  $white = [Drawing.SolidBrush]::new([Drawing.Color]::White)
  # The bar's track at 28% of white
  $track = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(71, 255, 255, 255))
  $left = "$unlocked / $total"
  $share = if ($total) { [Math]::Min(1.0, $unlocked / $total) } else { 0.0 }
  if (-not $widths.ContainsKey($left)) { $widths[$left] = [Math]::Ceiling((Measure-TextInk $left 72).Right) }
  $x = $widths[$left] + $ProgressGap
  $width = $x + $ProgressBar + $ProgressGap + $ProgressPercent
  $canvas = New-Canvas $width $ProgressHeight
  try {
    $path = New-TextPath $left 72 0 75
    $canvas.g.FillPath($white, $path)
    $path.Dispose()
    $canvas.g.FillRectangle($track, [single]$x, [single]45, [single]$ProgressBar, [single]10)
    $canvas.g.FillRectangle($white, [single]$x, [single]45, [single][Math]::Round($ProgressBar * $share, 1), [single]10)
    $path = New-TextPath "$([Math]::Floor($share * 100))%" 72 $width 75 'end'
    $canvas.g.FillPath($white, $path)
    $path.Dispose()
    return , (ConvertTo-MarkedPng $canvas "Atelier achievement progress $ProgressVersion $unlocked/$total;")
  } finally {
    Close-Canvas $canvas
    $white.Dispose()
    $track.Dispose()
  }
}

function Update-ProgressImages($es, $list) {
  $widths = @{}

  # Set aside every physical media image that isn't ours, including newly scraped ones
  $setAside = 0
  foreach ($folder in (Get-ProgressFolders $es)) {
    foreach ($file in (Get-FilesUnder $folder.dir)) {
      if (Get-ProgressMarker $file) { continue }
      $saved = [IO.Path]::Combine((Get-ProgressBackupDir $es), $folder.system, (Get-RelativeInside $folder.dir $file))
      New-Folder ([IO.Path]::GetDirectoryName($saved))
      Rename-Path $file $saved
      $setAside++
    }
  }

  $wanted = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $written = 0
  foreach ($e in $list) {
    $base = Get-BaseOf ($e.relPath -replace '^\./', '')
    $file = [IO.Path]::GetFullPath([IO.Path]::Combine($es.mediaDir, $e.system, $ProgressType, "$base.png"))
    [void]$wanted.Add($file)
    $value = "$ProgressVersion $($e.unlocked)/$($e.total)"
    if ((Get-ProgressMarker $file) -ceq $value) { continue }
    $png = New-ProgressPng $e.unlocked $e.total $widths
    New-Folder ([IO.Path]::GetDirectoryName($file))
    [IO.File]::WriteAllBytes($file, $png)
    $written++
  }

  Set-ProgressInTheme $true
  # Images of games that are gone or no longer matched
  $removed = 0
  foreach ($folder in (Get-ProgressFolders $es)) {
    foreach ($file in (Get-FilesUnder $folder.dir)) {
      if (-not $wanted.Contains($file) -and (Get-ProgressMarker $file)) {
        Remove-Path $file
        $removed++
      }
    }
  }
  return @{ written = $written; removed = $removed; setAside = $setAside }
}

function Test-ProgressOn([string]$dataDir) { return [IO.File]::Exists((Get-ProgressFlagFile $dataDir)) }

# Deletes the progress images and puts the user's physical media images back
function Remove-Progress($es, [string]$dataDir) {
  $removed = 0
  foreach ($folder in (Get-ProgressFolders $es)) {
    foreach ($file in (Get-FilesUnder $folder.dir)) {
      if (Get-ProgressMarker $file) {
        Remove-Path $file
        $removed++
      }
    }
  }
  $restored = 0
  $backup = Get-ProgressBackupDir $es
  foreach ($saved in (Get-FilesUnder $backup)) {
    $parts = (Get-RelativeInside $backup $saved).Split('\')
    $target = [IO.Path]::Combine($es.mediaDir, $parts[0], $ProgressType, ($parts[1..($parts.Count - 1)] -join '\'))
    if ([IO.File]::Exists($target)) { Remove-Path $saved }
    else {
      New-Folder ([IO.Path]::GetDirectoryName($target))
      Rename-Path $saved $target
      $restored++
    }
  }
  Remove-EmptyFolders $backup
  Remove-Path (Get-ProgressFlagFile $dataDir)
  Set-ProgressInTheme $false
  foreach ($folder in (Get-ProgressFolders $es)) { Remove-EmptyFolders $folder.dir }
  return @{ removed = $removed; restored = $restored }
}

if ($MyInvocation.InvocationName -ne '.') {
  try {
    $appArg = Get-CliArg $args '--app'
    $dataArg = Get-CliArg $args '--data'
    if (Test-CliFlag $args '--off') {
      $ctx = Open-Achievements $appArg $dataArg -configOnly
      $result = Remove-Progress $ctx.es $ctx.dataDir
      Write-Line "Removed $($result.removed) progress images and put back $($result.restored) physical media images."
      Write-Line 'Restart ES-DE if it is running.'
      exit 0
    }
    $ctx = Open-Achievements $appArg $dataArg
    Write-Line 'Matching your games with Retro Achievements...'
    $games = @(foreach ($g in (Find-RaGames $ctx)) { if ($g.ra) { $g } })
    $completion = Get-RaCompletion $ctx.ra
    Write-TextFile (Get-ProgressFlagFile $ctx.dataDir) '{"on":true}'
    $result = Update-ProgressImages $ctx.es (Get-ProgressEntries $games $completion)
    Write-Line "Progress shown for $($games.Count) games ($($result.written) images drawn, $($result.removed) removed)."
    if ($result.setAside) {
      Write-Line "$($result.setAside) physical media images were set aside in $(Get-ProgressBackupDir $ctx.es); they come back when the progress is disabled."
    }
    Write-Line 'The achievements app keeps the images up to date each time it opens. Restart ES-DE if it is running.'
  } catch {
    Write-Failure (Get-ErrorMessage $_)
    exit 1
  }
}
