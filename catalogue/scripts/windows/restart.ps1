# Brings ES-DE back with the games and collections as they are now. ES-DE reads its
# game lists, ROM folders and collections only when it starts, and nothing outside it
# can ask it to read them again, so after Catalogue downloaded or removed games, or
# the collections changed, ES-DE is restarted: as the app leaves, ES-DE is asked to
# close the way its window's close button does, which lets it save what it must, and is
# started again with the same command line as soon as it is gone. In between, while
# nothing can write over them, the collections are written into ES-DE: the details
# can name a plan made by collections.ps1.
#
# Find-Esde tells, while the app runs, which ES-DE started it: the app runs under a
# shell that ES-DE runs as a game. Restart-Esde hands that over to a process of its own,
# this script run with the details, which outlives the app and ES-DE.
#
# If ES-DE doesn't close within 20 seconds it is left as it is, never forced, and the
# games show after a restart by hand; the collections are written the next time the
# app leaves.

. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'base.ps1'))

$RestartScript = [IO.Path]::Combine($PSScriptRoot, 'restart.ps1')

# The ES-DE process the app runs under, with the child it waits for: { pid, exe,
# commandLine, child }, or $null when the app wasn't started by ES-DE
function Find-Esde {
  try { $list = Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine -ErrorAction Stop } catch { return $null }
  return Find-EsdeAbove $list $PID
}

# The nearest ES-DE among the parents of a process, in a list of Win32_Process
function Find-EsdeAbove($list, [int]$processId) {
  $byPid = @{}
  foreach ($p in $list) { $byPid[[int]$p.ProcessId] = $p }
  $p = $byPid[$processId]
  for ($depth = 0; $p -and $depth -lt 6; $depth++) {
    $parent = $byPid[[int]$p.ParentProcessId]
    if (-not $parent) { break }
    if ([regex]::IsMatch([string]$parent.Name, '^es-de(\.exe)?$', 'IgnoreCase') -and $parent.ExecutablePath) {
      return @{ pid = [int]$parent.ProcessId; exe = [string]$parent.ExecutablePath; commandLine = [string]$parent.CommandLine; child = [int]$p.ProcessId }
    }
    $p = $parent
  }
  return $null
}

# Starts the process that restarts ES-DE; it doesn't wait for the app to end
function Restart-Esde($esde) {
  $details = [Convert]::ToBase64String($Utf8NoBom.GetBytes((ConvertTo-JsonText $esde)))
  $exe = [IO.Path]::Combine($PSHOME, 'powershell.exe')
  $info = [Diagnostics.ProcessStartInfo]::new($exe, [Atelier.Runner]::Join(@('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', $RestartScript, $details)))
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  [void][Diagnostics.Process]::Start($info)
}

function Test-Alive([int]$processId) {
  try {
    $p = [Diagnostics.Process]::GetProcessById($processId)
    $p.Dispose()
    return $true
  } catch {
    return $false
  }
}

function Wait-Until([scriptblock]$test, [int]$ms) {
  $end = [DateTime]::UtcNow.AddMilliseconds($ms)
  while ([DateTime]::UtcNow -lt $end) {
    if (& $test) { return $true }
    Start-Sleep -Milliseconds 100
  }
  return [bool](& $test)
}

# The arguments of a command line: all after the program, as Windows wrote them
function Get-ArgumentsOf([string]$commandLine) {
  $line = $commandLine.Trim()
  $end = if ($line.StartsWith('"')) { $line.IndexOf('"', 1) + 1 } else { $m = [regex]::Match($line, '\s|$'); $m.Index }
  return $line.Substring($end).Trim()
}

function Invoke-Restart($esde) {
  # ES-DE carries on once the shell that ran the app has ended, and lets go of what
  # came while it waited; so it is asked to close from then on, every 150 ms, until it
  # takes the request in
  [void](Wait-Until { -not (Test-Alive $esde.child) } 60000)
  $end = [DateTime]::UtcNow.AddSeconds(20)
  while ((Test-Alive $esde.pid) -and [DateTime]::UtcNow -lt $end) {
    [void](Invoke-Program 'taskkill.exe' @('/PID', [string]$esde.pid) 10000)
    [void](Wait-Until { -not (Test-Alive $esde.pid) } 150)
  }
  if (Test-Alive $esde.pid) { return }
  if ($esde.plan) {
    try {
      $plan = Read-JsonFile ([string]$esde.plan) $null
      if ($plan -is [Collections.IDictionary]) { Invoke-EsdeCollectionsPlan $plan ([string]$plan['record']) }
      Remove-Path ([string]$esde.plan)
    } catch {}
  }
  $info = [Diagnostics.ProcessStartInfo]::new([string]$esde.exe, (Get-ArgumentsOf $esde.commandLine))
  $info.WorkingDirectory = [IO.Path]::GetDirectoryName([string]$esde.exe)
  $info.UseShellExecute = $false
  [void][Diagnostics.Process]::Start($info)
}

if ($MyInvocation.InvocationName -ne '.') {
  . ([IO.Path]::Combine($PSScriptRoot, 'collections.ps1'))
  try { Invoke-Restart (Read-JsonText $Utf8NoBom.GetString([Convert]::FromBase64String([string]$args[0]))) } catch {}
}
