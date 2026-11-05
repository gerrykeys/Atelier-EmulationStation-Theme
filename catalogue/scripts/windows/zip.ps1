# The games' zip files: written, checked and extracted with the zip support of .NET
# Framework, which comes with Windows (Atelier.Zip in common/scripts/windows/native.cs),
# so there is nothing to install. A zip opens in File Explorer, or with any zip tool.
#
# Files that are compressed already, such as the zip of an arcade set or a CHD, are
# stored as they are: compressing them again takes time and saves nothing. The rest is
# deflated, at the quicker level for large disc images.
#
# Every step reports its progress, as a fraction, and stops when its signal is raised.

. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'base.ps1'))

$ZipPacked = [string[]]@('.7z', '.zip', '.rar', '.gz', '.bz2', '.xz', '.zst', '.lzma', '.chd', '.rvz', '.wia', '.gcz',
  '.cso', '.zso', '.pbp', '.nsz', '.xcz', '.z', '.cia', '.wua', '.mp4', '.mkv')
# Above this size the quicker deflate level is used
$ZipFastAbove = [long]1GB

function New-AbortError { return New-AppError 'Stopped' 'aborted' }

# A step of a job done to a fraction: the job's own progress, through the part of the
# whole the step takes
function Set-Progress($progress, [string]$step, [double]$fraction) {
  if (-not $progress) { return }
  $range = $progress.steps[$step]
  if (-not $range) { $range = @(0, 1) }
  $progress.job.step = $step
  $progress.job.fraction = $range[0] + ($range[1] - $range[0]) * $fraction
}

# Follows a zip at work until it is done: its progress goes to the job, in the given
# step, and $signal.aborted stops it. Returns the files it wrote, checked or extracted:
# [{ Path (with forward slashes), Size, Crc }]
function Wait-Zip($zip, $progress, [string]$step, $signal) {
  while (-not $zip.Wait(100)) {
    if ($signal -and $signal.aborted) { $zip.Kill() }
    Set-Progress $progress $step $zip.Fraction
  }
  if ($signal -and $signal.aborted) { throw (New-AbortError) }
  if ($zip.Error) { throw "The zip file failed: $($zip.Error.Message)" }
  Set-Progress $progress $step 1
  return , @($zip.Items)
}

# Writes a zip of files and folders relative to dir (a folder ES-DE treats as a file is
# added with all it holds), the paths kept as given
function New-GameZip([string]$file, [string[]]$names, [string]$dir, $progress, $signal) {
  Remove-Path $file
  return , (Wait-Zip ([Atelier.Zip]::Create($file, $dir, $names, $ZipPacked, $ZipFastAbove)) $progress 'compress' $signal)
}

# Reads a zip through: what each of its files gives back
function Test-GameZip([string]$file, $progress, $signal) {
  return , (Wait-Zip ([Atelier.Zip]::Check($file)) $progress 'verify' $signal)
}

function Expand-GameZip([string]$file, [string]$dir, $progress, $signal) {
  return , (Wait-Zip ([Atelier.Zip]::Extract($file, $dir)) $progress 'extract' $signal)
}
