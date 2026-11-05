# Reads the look of Atelier from the theme's own files, so the app follows the theme
# as it changes: the colors of the color scheme chosen in ES-DE, the font sizes, the
# language, and the positions of the Index and Grid layouts for every aspect ratio.

. ([IO.Path]::Combine($PSScriptRoot, 'base.ps1'))

$ThemeRoot = $AtelierTheme
$ThemeDocs = @{}
$ThemeVariable = [regex]'\$\{(\w+)\}'
$ThemeSpace = [regex]'\s+'
$ThemeInvariant = [Globalization.CultureInfo]::InvariantCulture

# A theme file, read again only when it changed
function Read-ThemeXml([string]$file) {
  $path = [IO.Path]::Combine($ThemeRoot, $file)
  $stamp = [IO.File]::GetLastWriteTimeUtc($path).Ticks
  $known = $ThemeDocs[$path]
  if ($known -and $known.stamp -eq $stamp) { return $known.doc }
  $doc = [Xml.XmlDocument]::new()
  $doc.Load($path)
  $ThemeDocs[$path] = @{ stamp = $stamp; doc = $doc }
  return $doc
}

function Get-ThemeList([string]$s) { return @(foreach ($x in $s.Split(',')) { if ($x.Trim()) { $x.Trim() } }) }
function Get-ThemeChildren($node, [string]$tag) {
  return @(foreach ($c in $node.ChildNodes) { if ($c.NodeType -eq 'Element' -and (-not $tag -or $c.LocalName -ceq $tag)) { $c } })
}
function Get-ThemeVariables($node) {
  $vars = New-Map
  if (-not $node) { return , $vars }
  $block = @(Get-ThemeChildren $node 'variables')[0]
  if ($block) { foreach ($v in (Get-ThemeChildren $block)) { $vars[$v.LocalName] = $v.InnerText.Trim() } }
  return , $vars
}
function Merge-ThemeMaps {
  $out = New-Map
  foreach ($map in $args) { if ($map) { foreach ($k in @($map.Keys)) { $out[$k] = $map[$k] } } }
  return , $out
}

$ThemeRootElement = (Read-ThemeXml 'theme.xml').DocumentElement

function Get-ThemeFontSizes([string]$name) {
  $blocks = @(Get-ThemeChildren $ThemeRootElement 'fontSize')
  $block = @($blocks | Where-Object { $_.GetAttribute('name') -ceq $name })[0]
  if (-not $block) { $block = @($blocks | Where-Object { $_.GetAttribute('name') -ceq 'medium' })[0] }
  return , (Get-ThemeVariables $block)
}

# The variables of a color scheme, with ${systemColor} left in place: the page sets it
# per game from Get-ThemeSystems
function Get-ThemeColors([string]$name) {
  $schemes = @(Get-ThemeChildren (Read-ThemeXml 'layout/colors.xml').DocumentElement 'colorScheme')
  $scheme = @($schemes | Where-Object { $_.GetAttribute('name') -ceq $name })[0]
  if (-not $scheme) { $scheme = $schemes[0] }
  $out = New-Map
  $out['name'] = $scheme.GetAttribute('name')
  return , (Merge-ThemeMaps $out (Get-ThemeVariables $scheme))
}

# The labels of the theme in a language, falling back to English
function Get-ThemeLabels([string]$language) {
  $doc = (Read-ThemeXml 'layout/languages.xml').DocumentElement
  $own = @(Get-ThemeChildren $doc 'language' | Where-Object { (Get-ThemeList $_.GetAttribute('name')) -ccontains $language })[0]
  return , (Merge-ThemeMaps (Get-ThemeVariables $doc) (Get-ThemeVariables $own))
}

# A property's text as a number, a list of numbers or the text itself, as JavaScript's
# Number() reads it, with font size variables resolved
function ConvertTo-ThemeValue([string]$text, $vars) {
  $text = $text.Trim()
  if ($text.Contains('${')) {
    $sb = [Text.StringBuilder]::new()
    $at = 0
    foreach ($m in $ThemeVariable.Matches($text)) {
      $key = $m.Groups[1].Value
      [void]$sb.Append($text, $at, $m.Index - $at)
      [void]$sb.Append($(if ($vars.ContainsKey($key) -and $null -ne $vars[$key]) { $vars[$key] } else { $m.Value }))
      $at = $m.Index + $m.Length
    }
    [void]$sb.Append($text, $at, $text.Length - $at)
    $text = $sb.ToString()
  }
  if ($text -eq '') { return 0.0 }
  $n = 0.0
  if ($text -cne 'NaN' -and [double]::TryParse($text, 'Float', $ThemeInvariant, [ref]$n)) { return $n }
  $parts = $ThemeSpace.Split($text)
  if ($parts.Count -eq 1) { return $text }
  $nums = New-List
  foreach ($part in $parts) {
    if ($part -ceq 'NaN' -or -not [double]::TryParse($part, 'Float', $ThemeInvariant, [ref]$n)) { return $text }
    $nums.Add($n)
  }
  return , $nums
}

# Element properties as numbers or pairs of numbers, with font size variables resolved
function Get-ThemeProps($node, $vars) {
  $out = New-Map
  foreach ($p in $node.ChildNodes) {
    if ($p.NodeType -eq 'Element') { $out[$p.LocalName] = ConvertTo-ThemeValue $p.InnerText $vars }
  }
  return , $out
}

# The game video of the theme's game lists: how long it waits for the selection to
# rest, in seconds, how long it takes to fade in over the screenshot, and whether it
# plays its sound
function Get-ThemeVideo {
  $element = $null
  foreach ($node in (Read-ThemeXml 'layout/gamelist-media-video.xml').SelectNodes('//video')) {
    if ((Get-ThemeList $node.GetAttribute('name')) -ccontains 'gameVideo') { $element = $node; break }
  }
  $p = if ($element) { Get-ThemeProps $element (Get-ThemeVariables $ThemeRootElement) } else { New-Map }
  $delay = if ($p['delay'] -is [double] -and $p['delay']) { $p['delay'] } else { 1.6 }
  $fadeIn = if ($p['fadeInTime'] -is [double] -and $p['fadeInTime']) { $p['fadeInTime'] } else { 1.1 }
  return @{ delay = $delay; fadeIn = $fadeIn; audio = ([string]$p['audio'] -cne 'false') }
}

# Each system's color and the shape of its box covers as width/height, such as 0.75
function Get-ThemeSystems {
  $out = New-Map
  $dir = [IO.Path]::Combine($ThemeRoot, 'systems', 'metadata')
  foreach ($file in [IO.Directory]::GetFiles($dir)) {
    $xml = [IO.File]::ReadAllText($file)
    $color = [regex]::Match($xml, '<systemColor>(\w+)</systemColor>')
    $cover = [regex]::Match($xml, '<systemCoverSize>(\d+)-(\d+)</systemCoverSize>')
    $out[[regex]::Replace([IO.Path]::GetFileName($file), '\.xml$', '')] = @{
      color = if ($color.Success) { $color.Groups[1].Value } else { $null }
      cover = if ($cover.Success) { [double]$cover.Groups[1].Value / [double]$cover.Groups[2].Value } else { 0.75 }
    }
  }
  return , $out
}

# The gamelist elements of one aspect ratio file for the given variants, later ones
# overriding earlier ones, as ES-DE applies them
function Get-ThemeElements([string]$file, [string[]]$variantNames, $vars) {
  $out = New-Map
  $doc = (Read-ThemeXml $file).DocumentElement
  $variants = @(Get-ThemeChildren $doc 'variant')
  $blocks = [Collections.Generic.List[object]]::new()
  if ($doc.LocalName -ceq 'theme' -and -not $variants.Count) { $blocks.Add($doc) }
  else {
    foreach ($v in $variants) {
      foreach ($n in (Get-ThemeList $v.GetAttribute('name'))) { if ($variantNames -ccontains $n) { $blocks.Add($v); break } }
    }
  }
  foreach ($block in $blocks) {
    foreach ($view in (Get-ThemeChildren $block 'view')) {
      if (-not ((Get-ThemeList $view.GetAttribute('name')) -ccontains 'gamelist')) { continue }
      foreach ($el in (Get-ThemeChildren $view)) {
        $props = $null
        foreach ($name in (Get-ThemeList $el.GetAttribute('name'))) {
          if (-not $props) { $props = Get-ThemeProps $el $vars }
          $out[$name] = Merge-ThemeMaps $out[$name] $props
        }
      }
    }
  }
  return , $out
}

# The variables an aspect ratio file defines for itself, such as where the clock goes,
# with those of the font size over them
function Get-ThemeOwnVariables([string]$file, [string]$fontSizeName) {
  $doc = (Read-ThemeXml $file).DocumentElement
  $sized = @(Get-ThemeChildren $doc 'fontSize' | Where-Object { (Get-ThemeList $_.GetAttribute('name')) -ccontains $fontSizeName })[0]
  return , (Merge-ThemeMaps (Get-ThemeVariables $doc) (Get-ThemeVariables $sized))
}

$ThemeRatios = [ordered]@{ '21:9' = @('ar-21-9', '21-9'); '16:9' = @('ar-16-9', '16-9'); '4:3' = @('ar-4-3', '4-3') }

# The Index layout for the game list and the Grid layout, with its square covers, for
# the wall of badges
function Get-ThemeLayouts([string]$fontSizeName) {
  $vars = Get-ThemeFontSizes $fontSizeName
  $out = New-Map
  foreach ($ratio in $ThemeRatios.Keys) {
    $file, $grid = $ThemeRatios[$ratio]
    $at = "layout/$file.xml"
    $own = Merge-ThemeMaps $vars (Get-ThemeOwnVariables $at $fontSizeName)
    $out[$ratio] = @{
      games = Get-ThemeElements $at @('all', 'index', 'indexStill') $own
      achievements = Merge-ThemeMaps (Get-ThemeElements $at @('all', 'grid') $own) (Get-ThemeElements "layout/grid/$grid-square.xml" @() $vars)
    }
  }
  return , $out
}
