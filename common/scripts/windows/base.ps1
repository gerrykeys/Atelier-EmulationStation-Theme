# What every script of Atelier's apps starts from. The work PowerShell would do slowly,
# byte by byte, is done by a few helpers in C# (native.cs, next to this file) that
# PowerShell compiles itself, as Add-Type comes with Windows: reading and writing JSON,
# the CRC-32 of large files, the byte order of N64 ROMs, renaming and deleting as
# Node.js did, free space, folder listings that give up on a share that doesn't answer,
# sorting names the way people read them, running a program while its output is read,
# and writing, checking and extracting zip files with .NET's own zip support. Around
# them, the file, JSON, error and command line helpers the other scripts share.
#
# Everything runs on Windows PowerShell 5.1 and .NET Framework 4, which come with
# Windows 10 and 11: there is nothing to install. The compiled helpers are kept in
# bin\ next to this file, named after their source, so that only the first run after
# a change of the source compiles them; without a folder to write to, every run does.
#
# The Windows scripts live in scripts\windows of each part of the theme (common,
# achievements, catalogue, collections), beside what every platform shares, such as the
# apps' pages in ui; $AtelierTheme is the theme's folder.

$AtelierTheme = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, '..', '..', '..'))

if (-not ('Atelier.Json' -as [type])) {
  # The zip support is an assembly of .NET Framework that PowerShell doesn't load itself
  Add-Type -AssemblyName System.IO.Compression
  $references = @([IO.Compression.ZipArchive].Assembly.Location)
  $source = [IO.File]::ReadAllText([IO.Path]::Combine($PSScriptRoot, 'native.cs'))
  $sha = [Security.Cryptography.SHA256]::Create()
  $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($source)), 0, 8).Replace('-', '').ToLowerInvariant()
  $binDir = [IO.Path]::Combine($PSScriptRoot, 'bin')
  $dll = [IO.Path]::Combine($binDir, "Atelier.$hash.dll")
  $compile = {
    [void][IO.Directory]::CreateDirectory($binDir)
    $temp = [IO.Path]::Combine($binDir, "Atelier.$hash.$PID.tmp.dll")
    Add-Type -TypeDefinition $source -ReferencedAssemblies $references -OutputAssembly $temp -OutputType Library
    try { [IO.File]::Move($temp, $dll) } catch { $dll = $temp }
    # The helpers of an older source
    foreach ($old in [IO.Directory]::GetFiles($binDir, 'Atelier.*.dll')) {
      if ($old -ne $dll) { try { [IO.File]::Delete($old) } catch {} }
    }
    $dll
  }
  try {
    if (-not [IO.File]::Exists($dll)) { $dll = & $compile }
    try {
      [void][Reflection.Assembly]::LoadFrom($dll)
    } catch {
      # A copy Windows won't load, such as one that came in a downloaded zip, is made again
      [IO.File]::Delete($dll)
      [void][Reflection.Assembly]::LoadFrom((& $compile))
    }
  } catch {}
  if (-not ('Atelier.Json' -as [type])) { Add-Type -TypeDefinition $source -ReferencedAssemblies $references }
}

$Utf8NoBom = New-Object Text.UTF8Encoding $false
$UnixEpoch = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)

# The value of a --name option in a script's arguments, and whether a flag is there
function Get-CliArg($argv, [string]$name) {
  $i = [Array]::IndexOf([object[]]@($argv), $name)
  if ($i -ge 0 -and $i + 1 -lt @($argv).Count) { return [string]@($argv)[$i + 1] }
  return $null
}
function Test-CliFlag($argv, [string]$name) { return [Array]::IndexOf([object[]]@($argv), $name) -ge 0 }

# JSON, read into dictionaries and lists; a file that can't be read gives the fallback
function Read-JsonText([string]$text) { return , [Atelier.Json]::Read($text) }
function Read-JsonFile([string]$file, $fallback = $null) {
  try { return , [Atelier.Json]::Read([IO.File]::ReadAllText($file)) } catch { return , $fallback }
}
function ConvertTo-JsonText($value, [switch]$Indent) { return [Atelier.Json]::Write($value, [bool]$Indent) }

function New-Map { return , [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal) }
function New-List { return , [System.Collections.Generic.List[object]]::new() }

# Files, in UTF-8 without a byte order mark, as Node.js wrote them
function New-Folder([string]$dir) { if ($dir) { [void][IO.Directory]::CreateDirectory($dir) } }
function Write-TextFile([string]$file, [string]$text) {
  New-Folder ([IO.Path]::GetDirectoryName($file))
  [IO.File]::WriteAllText($file, $text, $Utf8NoBom)
}
function Rename-Path([string]$from, [string]$to) { [Atelier.Files]::Rename($from, $to) }
function Remove-Path([string]$path) { [Atelier.Files]::Remove($path) }
function Test-File([string]$path) { return [IO.File]::Exists($path) }
function Test-Folder([string]$path) { return [IO.Directory]::Exists($path) }
function Test-AnyPath([string]$path) { return [IO.File]::Exists($path) -or [IO.Directory]::Exists($path) }

# Written under another name and renamed, so a reader never sees half a file
function Write-Atomic([string]$file, [string]$text) {
  New-Folder ([IO.Path]::GetDirectoryName($file))
  $temp = "$file.$PID.$([Threading.Thread]::CurrentThread.ManagedThreadId).tmp"
  [IO.File]::WriteAllText($temp, $text, $Utf8NoBom)
  Rename-Path $temp $file
}
function Copy-Atomic([string]$from, [string]$to) {
  New-Folder ([IO.Path]::GetDirectoryName($to))
  $temp = "$to.$PID.$([Threading.Thread]::CurrentThread.ManagedThreadId).tmp"
  [IO.File]::Copy($from, $temp, $true)
  Rename-Path $temp $to
}

# A file's date as Node.js gives it, in milliseconds since 1970 with their fraction,
# and rounded as Math.round does
function Get-MtimeMs([string]$file) { return [Atelier.Files]::MtimeMs($file) }
function Get-MtimeRounded([string]$file) { return [long][Math]::Floor((Get-MtimeMs $file) + 0.5) }
function Get-NowMs { return [long][Math]::Floor(([DateTime]::UtcNow - $UnixEpoch).TotalMilliseconds) }
function ConvertFrom-Ms([double]$ms) { return $UnixEpoch.AddMilliseconds($ms) }
function Get-IsoNow { return [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture) }

# Paths as Node's path module handles them: the folder of a path, a path's extension
# (none for a name that starts with its only dot), and a path relative to a folder it is in
function Get-Parent([string]$p) {
  $trimmed = $p.TrimEnd('\', '/')
  if (-not $trimmed -or $trimmed -match '^[A-Za-z]:$') { return $p }
  $dir = [IO.Path]::GetDirectoryName($trimmed)
  if ($null -eq $dir) { return $p }
  if ($dir -match '^[A-Za-z]:$') { return "$dir\" }
  return $dir
}
function Get-Ext([string]$p) { return [Atelier.Paths]::Ext($p) }
function Get-RelativeInside([string]$dir, [string]$file) {
  $root = $dir.TrimEnd('\')
  return $file.Substring($root.Length + 1)
}
function Get-RelativePath([string]$from, [string]$to) {
  $a = [IO.Path]::GetFullPath($from).TrimEnd('\').Split('\')
  $b = [IO.Path]::GetFullPath($to).TrimEnd('\').Split('\')
  if ($a[0] -ne $b[0]) { return [IO.Path]::GetFullPath($to) }
  $common = 0
  while ($common -lt $a.Count -and $common -lt $b.Count -and $a[$common] -eq $b[$common]) { $common++ }
  $parts = @('..') * ($a.Count - $common) + @($b | Select-Object -Skip $common)
  return ($parts -join '\')
}
function ConvertTo-Slash([string]$p) { return $p.Replace('\', '/') }

# The base name of a path in the gamelist, without "./" and its extension
function Get-BaseOf([string]$rel) { return [Atelier.Paths]::BaseOf($rel) }

# Errors: an AppException with a code, and the message and code of whatever was thrown,
# looking through PowerShell's wrapping
function New-AppError([string]$message, [string]$code, $detail = $null) {
  $e = New-Object Atelier.AppException $message, $code
  $e.Detail = $detail
  return $e
}
function Get-InnerError($err) {
  $ex = if ($err -is [Management.Automation.ErrorRecord]) { $err.Exception } else { $err }
  while ($ex -and -not ($ex -is [Atelier.AppException]) -and $ex.InnerException -and
    ($ex -is [Management.Automation.MethodInvocationException] -or $ex -is [Management.Automation.RuntimeException] -or $ex -is [AggregateException])) {
    $ex = $ex.InnerException
  }
  return $ex
}
function Get-ErrorMessage($err) { return (Get-InnerError $err).Message }
function Get-ErrorCode($err) {
  $ex = Get-InnerError $err
  if ($ex -is [Atelier.AppException]) { return $ex.Code }
  return $null
}
function Write-Failure([string]$message) { [Console]::Error.WriteLine($message) }
function Write-Line([string]$message = '') { [Console]::Out.WriteLine($message) }

# Runs a program to its end, or until it has taken too long: { ok, code, out }
function Invoke-Program([string]$exe, $arguments, [int]$timeoutMs = 20000, [switch]$Oem, [string]$cwd) {
  $codePage = if ($Oem) { [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage } else { 0 }
  try {
    $run = [Atelier.Runner]::new($exe, [Atelier.Runner]::Join(@($arguments)), $cwd, $codePage)
  } catch {
    return @{ ok = $false; code = 'ENOENT'; out = (Get-ErrorMessage $_) }
  }
  if (-not $run.Wait($timeoutMs)) {
    $run.Kill()
    [void]$run.Wait(2000)
    return @{ ok = $false; code = 'ETIMEDOUT'; out = "$($run.Output)`n$($run.Errors)" }
  }
  return @{ ok = ($run.ExitCode -eq 0); code = $run.ExitCode; out = "$($run.Output)`n$($run.Errors)" }
}

# A program on the PATH, as "where" finds it, with the extensions of PATHEXT when the
# name has none
function Find-OnPath([string]$name) {
  $names = @($name)
  if (-not [IO.Path]::GetExtension($name)) { $names = @(foreach ($ext in ([string]$env:PATHEXT).Split(';')) { if ($ext) { $name + $ext } }) }
  foreach ($dir in ([string]$env:PATH).Split(';')) {
    if (-not $dir) { continue }
    foreach ($n in $names) {
      try { $file = [IO.Path]::Combine($dir.Trim('"'), $n) } catch { continue }
      if ([IO.File]::Exists($file)) { return $file }
    }
  }
  return $null
}
