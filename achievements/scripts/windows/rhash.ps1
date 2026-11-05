# Identifies a game file the way RetroAchievements does (the rcheevos library inside
# RetroArch): an MD5 of the ROM data without the copier or emulator headers some dumps
# carry, or of the file name for arcade sets. Zipped games are hashed by the file inside,
# as RetroArch extracts them before loading. Disc-based consoles hash parts of the disc
# image's file system and aren't supported yet.

. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'base.ps1'))
Add-Type -AssemblyName System.IO.Compression

$RhashDisc = [Collections.Generic.HashSet[int]]::new([int[]](9, 12, 16, 18, 19, 21, 39, 40, 41, 43, 49, 56, 76, 77))
$RhashArchives = @('.zip', '.7z')
$RhashLatin1 = [Text.Encoding]::GetEncoding(28591)

# The first file in a zip archive with one of the given extensions (or any file)
function Read-ZipEntry([string]$file, $extensions) {
  $stream = [IO.File]::OpenRead($file)
  try {
    try { $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read) } catch { throw 'not a zip archive' }
    $entries = @(foreach ($e in $zip.Entries) { if (-not $e.FullName.EndsWith('/')) { $e } })
    $entry = $null
    foreach ($e in $entries) { if ($extensions.Contains((Get-Ext $e.FullName).ToLowerInvariant())) { $entry = $e; break } }
    if (-not $entry) { $entry = $entries[0] }
    if (-not $entry) { throw 'empty zip archive' }
    $out = [IO.MemoryStream]::new([int]$entry.Length)
    try {
      $inner = $entry.Open()
      $inner.CopyTo($out)
      $inner.Dispose()
    } catch {
      throw 'zip compression method is not supported'
    }
    return , $out.ToArray()
  } finally {
    $stream.Dispose()
  }
}

function Test-Bytes([byte[]]$data, [int]$at, [string]$text) {
  if ($data.Length -lt $at + $text.Length) { return $false }
  return $RhashLatin1.GetString($data, $at, $text.Length) -ceq $text
}

# The part of the ROM that RetroAchievements hashes: @(bytes, offset)
function Get-RomPart([int]$consoleId, [byte[]]$data) {
  switch ($consoleId) {
    # NES: iNES header; Famicom Disk System: fwNES header
    { $_ -eq 7 -or $_ -eq 81 } { if ((Test-Bytes $data 0 "NES$([char]0x1a)") -or (Test-Bytes $data 0 "FDS$([char]0x1a)")) { return $data, 16 } }
    # SNES: copier header
    3 { if ($data.Length % 8192 -eq 512) { return $data, 512 } }
    # PC Engine: copier header
    8 { if ($data.Length % 131072 -eq 512) { return $data, 512 } }
    # Lynx: LNX header
    13 { if ((Test-Bytes $data 0 'LYNX') -and $data[4] -eq 0) { return $data, 64 } }
    # Atari 7800: A78 header
    51 { if (Test-Bytes $data 1 'ATARI7800') { return $data, 128 } }
    # Nintendo 64: big-endian byte order
    2 {
      if ($data.Length -lt 4) { throw 'the file is too small' }
      $magic = ([uint32]$data[0] -shl 24) -bor ([uint32]$data[1] -shl 16) -bor ([uint32]$data[2] -shl 8) -bor [uint32]$data[3]
      if ($magic -eq 0x37804012) { return [Atelier.Rom]::Swap16($data), 0 }
      if ($magic -eq 0x40123780) { return [Atelier.Rom]::Swap32($data), 0 }
    }
  }
  return $data, 0
}

# Famicom Disk System images, with or without their header, which ES-DE keeps in its
# NES and Famicom systems and RetroAchievements lists as a console of its own
function Test-FamicomDisk([byte[]]$data) { return (Test-Bytes $data 0 "FDS$([char]0x1a)") -or (Test-Bytes $data 1 '*NINTENDO-HVC*') }

function Get-Md5Hex([byte[]]$data, [int]$offset = 0) {
  $md5 = [Security.Cryptography.MD5]::Create()
  try {
    $count = [Math]::Max(0, $data.Length - $offset)
    return [BitConverter]::ToString($md5.ComputeHash($data, [Math]::Min($offset, $data.Length), $count)).Replace('-', '').ToLowerInvariant()
  } finally {
    $md5.Dispose()
  }
}

# @{ hash; consoleId } or @{ unsupported = reason }
function Get-GameHash([string]$file, [int]$consoleId, $extensions) {
  $ext = (Get-Ext $file).ToLowerInvariant()
  if ($consoleId -eq 27) {
    return [ordered]@{ hash = Get-Md5Hex ([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFileNameWithoutExtension($file))); consoleId = $consoleId }
  }
  if ($RhashDisc.Contains($consoleId)) { return @{ unsupported = 'disc-based games are not supported yet' } }
  if ($ext -eq '.7z') { return @{ unsupported = '7z archives are not supported yet' } }
  $inner = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($e in $extensions) { if ($RhashArchives -notcontains $e) { [void]$inner.Add($e) } }
  if ($ext -eq '.zip') { $data = Read-ZipEntry $file $inner } else { $data = [IO.File]::ReadAllBytes($file) }
  if ($consoleId -eq 7 -and (Test-FamicomDisk $data)) { $consoleId = 81 }
  $bytes, $offset = Get-RomPart $consoleId $data
  return [ordered]@{ hash = Get-Md5Hex $bytes $offset; consoleId = $consoleId }
}
