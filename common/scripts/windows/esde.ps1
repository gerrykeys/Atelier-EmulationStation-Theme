# Reads what ES-DE knows about the user's games: where ES-DE keeps its data, its
# systems with their ROM folders and launch commands, the game files in them, and the
# names and media the scraper gave them. Nothing here writes to ES-DE.
#
# The apps ship in the theme and find ES-DE from this folder: the theme is installed
# in <ES-DE home>/themes/, and a portable installation keeps that home next to the
# executable. Run from anywhere else, they need the ES-DE application folder.

. ([IO.Path]::Combine($PSScriptRoot, 'base.ps1'))

$EsdeMediaTypes = @('covers', 'miximages', 'screenshots', 'titlescreens', 'fanart', 'marquees', '3dboxes')
$EsdeImageExt = @('.png', '.jpg', '.jpeg', '.webp')

function ConvertFrom-XmlText([string]$s) { return [Atelier.Gamelist]::Decode($s) }
function ConvertTo-XmlText([string]$s) { return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }
# The decoded text of the first <name> element in a block of XML, or ''
function Get-XmlTag([string]$block, [string]$name) { return [Atelier.Gamelist]::Tag($block, $name) }

function Test-EsdeSettings([string]$dir) { return [IO.File]::Exists([IO.Path]::Combine($dir, 'settings', 'es_settings.xml')) }

# ES-DE as it is set up: { home, appDir, tilde, romDir, mediaDir, systems, resourcesDir,
# settings }, the systems by name with { name, fullName, dir, path, extensions,
# commands }, path being the folder as es_systems.xml writes it, such as %ROMPATH%/nes
function Open-Esde([string]$appArg) {
  if ($appArg) {
    if (-not (Test-AnyPath $appArg)) { throw "ES-DE application folder not found: $appArg" }
    $appDir = [IO.Path]::GetFullPath($appArg)
    $homeDir = if (Test-EsdeSettings ([IO.Path]::Combine($appDir, 'ES-DE'))) { [IO.Path]::Combine($appDir, 'ES-DE') } else { [IO.Path]::Combine($env:USERPROFILE, 'ES-DE') }
  } else {
    # <home>/themes/<theme>
    $homeDir = [IO.Path]::GetFullPath([IO.Path]::Combine($AtelierTheme, '..', '..'))
    $appDir = Get-Parent $homeDir
  }
  if (-not (Test-EsdeSettings $homeDir)) { throw "ES-DE settings not found in $homeDir" }
  $portable = [IO.Path]::GetFullPath($homeDir).TrimEnd('\') -eq [IO.Path]::GetFullPath([IO.Path]::Combine($appDir, 'ES-DE')).TrimEnd('\')
  $es = @{
    home = $homeDir
    appDir = $appDir
    # What ~ stands for in ES-DE's paths
    tilde = if ($portable) { $appDir } else { $env:USERPROFILE }
    settings = [IO.File]::ReadAllText([IO.Path]::Combine($homeDir, 'settings', 'es_settings.xml'))
  }
  $romSetting = Get-EsdeSetting $es 'ROMDirectory'
  $es.romDir = Expand-EsdePath $es $(if ($romSetting) { $romSetting } else { '~/ROMs' })
  $mediaSetting = Expand-EsdePath $es (Get-EsdeSetting $es 'MediaDirectory')
  $es.mediaDir = [IO.Path]::GetFullPath($(if ($mediaSetting) { $mediaSetting } else { [IO.Path]::Combine($homeDir, 'downloaded_media') }))

  # Bundled system definitions, overridden by the user's custom_systems
  $systems = New-Map
  $candidates = @($appDir)
  if ($env:ProgramFiles) { $candidates += [IO.Path]::Combine($env:ProgramFiles, 'ES-DE') }
  $bundled = $null
  foreach ($dir in $candidates) {
    $file = [IO.Path]::Combine($dir, 'resources', 'systems', 'windows', 'es_systems.xml')
    if ([IO.File]::Exists($file)) { $bundled = $file; break }
  }
  foreach ($file in @($bundled, [IO.Path]::Combine($homeDir, 'custom_systems', 'es_systems.xml'))) {
    if (-not $file -or -not [IO.File]::Exists($file)) { continue }
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($file), '<system>([\s\S]*?)</system>')) {
      $block = $m.Groups[1].Value
      $name = Get-XmlTag $block 'name'
      if (-not $name) { continue }
      $extensions = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
      foreach ($e in ((Get-XmlTag $block 'extension') -split '\s+')) { if ($e) { [void]$extensions.Add($e.ToLowerInvariant()) } }
      # The launch commands, the first being the default
      $commands = @(foreach ($c in [regex]::Matches($block, '<command(?:\s+label="([^"]*)")?\s*>([\s\S]*?)</command>')) {
        @{ label = ConvertFrom-XmlText $c.Groups[1].Value; command = ConvertFrom-XmlText $c.Groups[2].Value.Trim() }
      })
      $fullName = Get-XmlTag $block 'fullname'
      $template = Get-XmlTag $block 'path'
      $path = Expand-EsdePath $es $template.Replace('%ROMPATH%', $es.romDir)
      $systems[$name] = @{
        name = $name
        fullName = if ($fullName) { $fullName } else { $name }
        dir = if ($path) { [IO.Path]::GetFullPath($path) } else { '' }
        path = $template
        extensions = $extensions
        commands = $commands
      }
    }
  }
  $es.systems = $systems
  # ES-DE's own files beside es_systems.xml, such as es_find_rules.xml, if found
  $es.resourcesDir = if ($bundled) { [IO.Path]::GetDirectoryName($bundled) } else { $null }
  return $es
}

function Get-EsdeSetting($es, [string]$name) {
  $m = [regex]::Match($es.settings, "<\w+ name=""$([regex]::Escape($name))"" value=""([^""]*)""")
  if ($m.Success) { return ConvertFrom-XmlText $m.Groups[1].Value }
  return ''
}

# ~ is the user's home folder, or the application folder of a portable installation
function Expand-EsdePath($es, [string]$p) {
  $p = [regex]::Replace($p, '^~(?=$|[\\/])', $es.tilde.Replace('$', '$$'))
  $i = $p.IndexOf('%ESPATH%')
  if ($i -ge 0) { $p = $p.Substring(0, $i) + $es.appDir + $p.Substring($i + 8) }
  return $p
}

# The theme language, else the application language, else the system's, as it_IT
function Get-EsdeLanguage($es) {
  foreach ($name in 'ThemeLanguage', 'ApplicationLanguage') {
    $value = Get-EsdeSetting $es $name
    if ($value -and $value -ne 'automatic') { return $value }
  }
  return [Globalization.CultureInfo]::CurrentCulture.Name.Replace('-', '_')
}

# The scraped image of a type for a game, if there is one
function Get-EsdeMedia($es, [string]$system, [string]$relPath, [string]$type) {
  $base = [IO.Path]::Combine($es.mediaDir, $system, $type, (Get-BaseOf ($relPath -replace '^\./', '')))
  foreach ($ext in $EsdeImageExt) { if ([IO.File]::Exists($base + $ext)) { return $base + $ext } }
  return $null
}

# The games ES-DE shows for a system: files with one of its extensions, anywhere in its
# folder, minus the ones hidden in the gamelist
function Get-EsdeGames($es, [string]$systemName) {
  $system = $es.systems[$systemName]
  $found = New-List
  if (-not $system -or -not [IO.Directory]::Exists($system.dir)) { return , $found }
  $meta = [Atelier.Gamelist]::Blocks([IO.Path]::Combine($es.home, 'gamelists', $systemName, 'gamelist.xml'), $false)
  $files = [Collections.Generic.List[string]]::new()
  $pending = [Collections.Generic.Stack[string]]::new()
  $pending.Push($system.dir)
  while ($pending.Count) {
    $dir = $pending.Pop()
    foreach ($entry in [IO.DirectoryInfo]::new($dir).GetFileSystemInfos()) {
      if ($entry -is [IO.DirectoryInfo]) { $pending.Push($entry.FullName) }
      elseif ($system.extensions.Contains($entry.Extension.ToLowerInvariant())) { $files.Add($entry.FullName) }
    }
  }
  $files.Sort([StringComparer]::Ordinal)
  $mediaRoot = [IO.Path]::Combine($es.mediaDir, $systemName)
  foreach ($file in $files) {
    $rel = [Atelier.Paths]::Relative($system.dir, $file)
    $relPath = "./$rel"
    $block = if ($meta.ContainsKey($relPath)) { $meta[$relPath] } else { '' }
    if ([Atelier.Gamelist]::Tag($block, 'hidden') -ceq 'true') { continue }
    $name = [Atelier.Gamelist]::Tag($block, 'name')
    if (-not $name) { $name = [Atelier.Paths]::BaseOf([IO.Path]::GetFileName($file)) }
    $images = @{}
    $base = [Atelier.Paths]::BaseOf($rel)
    foreach ($type in $EsdeMediaTypes) {
      $image = [Atelier.Paths]::FirstExisting([IO.Path]::Combine($mediaRoot, $type, $base), $EsdeImageExt)
      if ($image) { $images[$type] = $image }
    }
    $released = [Atelier.Gamelist]::Tag($block, 'releasedate')
    $found.Add(@{
      system = $systemName; systemName = $system.fullName; file = $file; relPath = $relPath; name = $name; media = $images
      developer = [Atelier.Gamelist]::Tag($block, 'developer'); releaseDate = $released.Substring(0, [Math]::Min(4, $released.Length))
      description = [Atelier.Gamelist]::Tag($block, 'desc')
    })
  }
  return , $found
}

function Get-EsdeAllGames($es) {
  $all = New-List
  foreach ($name in @($es.systems.Keys)) { $all.AddRange((Get-EsdeGames $es $name)) }
  return , $all
}
