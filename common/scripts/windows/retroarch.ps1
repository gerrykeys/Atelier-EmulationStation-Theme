# RetroArch as ES-DE runs it: found the way ES-DE finds it, with its find rules (the
# user's own in custom_systems first, then those that come with ES-DE), and its
# retroarch.cfg, next to it or in the user's AppData. Catalogue reads from it where
# RetroArch saves; the achievements app the RetroAchievements user signed in there.

. ([IO.Path]::Combine($PSScriptRoot, 'esde.ps1'))

function Find-RetroArchExe($es) {
  $files = @([IO.Path]::Combine($es.home, 'custom_systems', 'es_find_rules.xml'))
  if ($es.resourcesDir) {
    $files += [IO.Path]::Combine($es.resourcesDir, 'es_find_rules.xml')
    $files += [IO.Path]::Combine($es.resourcesDir, 'es_find_rules_installer.xml')
  }
  foreach ($file in $files) {
    if (-not [IO.File]::Exists($file)) { continue }
    $block = [regex]::Match([IO.File]::ReadAllText($file), '<emulator name="RETROARCH">([\s\S]*?)</emulator>')
    if (-not $block.Success) { continue }
    foreach ($rule in [regex]::Matches($block.Groups[1].Value, '<rule type="(\w+)">([\s\S]*?)</rule>')) {
      foreach ($m in [regex]::Matches($rule.Groups[2].Value, '<entry>([\s\S]*?)</entry>')) {
        $entry = $m.Groups[1].Value.Trim()
        $found = $null
        switch ($rule.Groups[1].Value) {
          'staticpath' {
            $p = $entry.Replace('%ESPATH%', $es.appDir)
            $p = [regex]::Replace($p, '^~(?=[\\/])', $env:USERPROFILE.Replace('$', '$$'))
            $p = [regex]::Replace($p, '%(\w+)%', [Text.RegularExpressions.MatchEvaluator]{
              param($v)
              $value = [Environment]::GetEnvironmentVariable($v.Groups[1].Value)
              if ($null -ne $value) { $value } else { $v.Value }
            })
            try { $found = [IO.Path]::GetFullPath($p) } catch {}
          }
          'systempath' { $found = Find-OnPath $entry }
          'winregistrypath' {
            foreach ($hive in [Microsoft.Win32.Registry]::CurrentUser, [Microsoft.Win32.Registry]::LocalMachine) {
              $key = $hive.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$entry")
              if (-not $key) { continue }
              $value = $key.GetValue('')
              $key.Close()
              if ($value) { $found = [string]$value; break }
            }
          }
        }
        if ($found) {
          $clean = $found.Trim().Trim('"')
          if ([IO.File]::Exists($clean)) { return $clean }
        }
      }
    }
  }
  return $null
}

function Read-RetroArchConfig([string]$file) {
  $config = New-Map
  foreach ($m in [regex]::Matches([IO.File]::ReadAllText($file), '^\s*(\w+)\s*=\s*"?([^"\r\n]*)"?\s*$', 'Multiline')) {
    $config[$m.Groups[1].Value] = $m.Groups[2].Value
  }
  return , $config
}

# RetroArch's folder and settings: { exe, dir, configFile, config }, or $null
function Find-RetroArch($es) {
  $exe = Find-RetroArchExe $es
  if (-not $exe) { return $null }
  $dir = [IO.Path]::GetDirectoryName($exe)
  $configFile = $null
  foreach ($f in @([IO.Path]::Combine($dir, 'retroarch.cfg'), $(if ($env:APPDATA) { [IO.Path]::Combine($env:APPDATA, 'RetroArch', 'retroarch.cfg') }))) {
    if ($f -and [IO.File]::Exists($f)) { $configFile = $f; break }
  }
  return @{ exe = $exe; dir = $dir; configFile = $configFile; config = $(if ($configFile) { Read-RetroArchConfig $configFile } else { New-Map }) }
}
