# Where an archive can live: the computer's drives, local, removable (a USB disk) or
# network ones, the folders on them, and network shares (\\server\share) reached by
# their address. A share that wants a user name and password gets them through Windows
# itself, with "net use"; when the user asks to remember them, Windows keeps them in
# its Credential Manager ("cmdkey"), as when a share is opened in File Explorer. The
# app never writes them anywhere.
#
# A network folder that doesn't answer would hold up the app, so every look at one
# gives up after a few seconds.

. ([IO.Path]::Combine($PSScriptRoot, 'store.ps1'))

$PlacesTimeout = 8000
# Windows' answers that mean a user name and password are wanted (or wrong): logon
# failure, access denied, bad password, not authenticated, account restrictions,
# locked or disabled account, password expired
$PlacesCredentials = @(5, 86, 1244, 1326, 1327, 1328, 1330, 1331, 1909)
# The share doesn't exist or can't be reached
$PlacesUnreachable = @(53, 64, 67, 1203, 1222, 1231)

function Test-Unc([string]$p) { return [regex]::IsMatch($p, '^\\\\[^\\]+\\[^\\]+') }
# \\server\share of a path on a share
function Get-ShareOf([string]$p) {
  $m = [regex]::Match($p, '^(\\\\[^\\]+\\[^\\]+)')
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}
# The Windows error number in net's output, whatever its language: the last number on
# the first line, "System error 1326 has occurred."
function Get-NetError([string]$out) {
  $line = ''
  foreach ($l in [regex]::Split($out, '\r?\n')) { if ($l.Trim()) { $line = $l.Trim(); break } }
  $m = [regex]::Match($line, '(\d{1,5})\D*$')
  if ($m.Success) { return [int]$m.Groups[1].Value }
  return 0
}

# The drives: [{ path, letter, label, type: local, removable, network, free, size,
# share (the network drive's \\server\share) }]
function Get-Drives {
  $types = @{ Removable = 'removable'; Fixed = 'local'; Network = 'network' }
  return , @(foreach ($d in [IO.DriveInfo]::GetDrives()) {
    if ($d.DriveType -eq 'CDRom') { continue }
    $letter = $d.Name.TrimEnd('\')
    $ready = $false
    try { $ready = $d.IsReady } catch {}
    $label = ''; $free = $null; $size = $null
    if ($ready) {
      try { $label = $d.VolumeLabel } catch {}
      try { $free = $d.AvailableFreeSpace; $size = $d.TotalSize } catch {}
    }
    $type = $types[[string]$d.DriveType]
    if (-not $type) { $type = 'local' }
    @{
      path = "$letter\"; letter = $letter; label = $label; type = $type; free = $free; size = $size
      share = $(if ($type -eq 'network') { [Atelier.Files]::NetworkShare($letter) } else { $null })
    }
  })
}

# The share behind a path: its own, or the network drive's it is on
function Get-ShareFor([string]$dir) {
  if (Test-Unc $dir) { return Get-ShareOf $dir }
  $m = [regex]::Match($dir, '^([A-Za-z]:)')
  if (-not $m.Success) { return $null }
  foreach ($d in (Get-Drives)) {
    if ($d.letter -eq $m.Groups[1].Value) { if ($d.type -eq 'network') { return $d.share } else { return $null } }
  }
  return $null
}

# The entries of a folder, giving up after a few seconds
function Get-FolderEntries([string]$dir) { return , [Atelier.Files]::List($dir, $PlacesTimeout) }

# Whether a folder can be read: { ok } or { ok: false, reason: credentials, missing,
# unreachable or denied, share, message }
function Test-Access([string]$dir) {
  try {
    [void](Get-FolderEntries $dir)
    return @{ ok = $true }
  } catch {
    $err = Get-InnerError $_
  }
  $share = Get-ShareFor $dir
  if ($err -is [TimeoutException]) { return @{ ok = $false; reason = 'unreachable'; share = $share; message = $err.Message } }
  if ($share) {
    # Asking Windows to connect tells why: its own error number
    $result = Invoke-Program 'net.exe' @('use', $share) 20000 -Oem
    if ($result.ok) {
      try {
        [void](Get-FolderEntries $dir)
        return @{ ok = $true }
      } catch {}
    }
    $code = Get-NetError $result.out
    if ($PlacesCredentials -contains $code) { return @{ ok = $false; reason = 'credentials'; share = $share; message = $result.out.Trim() } }
    if ($PlacesUnreachable -contains $code) { return @{ ok = $false; reason = 'unreachable'; share = $share; message = $result.out.Trim() } }
  }
  $win32 = $err.HResult -band 0xFFFF
  if ($err -is [IO.DirectoryNotFoundException] -or $err -is [IO.FileNotFoundException] -or $win32 -in 2, 3, 15) {
    return @{ ok = $false; reason = 'missing'; share = $share; message = $err.Message }
  }
  return @{ ok = $false; reason = 'denied'; share = $share; message = $err.Message }
}

# Connects to a share with a user name and password; remember keeps them in Windows'
# Credential Manager. { ok } or { ok: false, reason, message }.
function Connect-Share([string]$share, [string]$user, [string]$password, [bool]$remember) {
  $server = $share.Split('\')[2]
  $attempt = { Invoke-Program 'net.exe' @('use', $share, $password, "/user:$user", '/persistent:no') 20000 -Oem }
  $result = & $attempt
  # Windows allows one user per server: a connection to this share with another user
  # goes first
  if (-not $result.ok -and (Get-NetError $result.out) -eq 1219) {
    [void](Invoke-Program 'net.exe' @('use', $share, '/delete', '/y') 20000 -Oem)
    $result = & $attempt
  }
  if (-not $result.ok) {
    $code = Get-NetError $result.out
    $reason = if ($PlacesCredentials -contains $code) { 'credentials' } elseif ($code -eq 1219) { 'other-user' } elseif ($PlacesUnreachable -contains $code) { 'unreachable' } else { 'failed' }
    return @{ ok = $false; reason = $reason; message = $result.out.Trim() }
  }
  if ($remember) { [void](Invoke-Program 'cmdkey.exe' @("/add:$server", "/user:$user", "/pass:$password") 20000 -Oem) }
  return @{ ok = $true }
}

# The folders in a folder, for choosing one: { path, parent, folders: [{ name, path }],
# archive (whether it is one), free }
function Get-Folders([string]$dir) {
  $entries = Get-FolderEntries $dir
  $list = @(foreach ($e in $entries) {
    $n = $e.Name
    # Junctions such as "All Users" are links, not folders of their own
    if (-not ($e -is [IO.DirectoryInfo]) -or ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $n.StartsWith('$') -or $n.StartsWith('.') -or $n -eq 'System Volume Information' -or
      $n -ceq $StoreMeta -or $n -ceq $StoreSaves) { continue }
    @{ name = $n; path = [IO.Path]::Combine($dir, $n) }
  })
  if ($list.Count -gt 1) { $list = [Atelier.NameComparer]::Sort($list, @(foreach ($f in $list) { $f.name }), $null, [Globalization.CultureInfo]::CurrentCulture.Name) }
  $full = [IO.Path]::GetFullPath($dir).TrimEnd('\')
  $root = [IO.Path]::GetPathRoot($full).TrimEnd('\')
  $atRoot = $full -eq $root -or ((Test-Unc $dir) -and $full -eq (Get-ShareOf $dir).TrimEnd('\'))
  return @{
    path = $dir; parent = $(if ($atRoot) { $null } else { Get-Parent $dir }); folders = $list
    archive = Test-Archive $dir; free = Get-FreeSpace $dir
  }
}
