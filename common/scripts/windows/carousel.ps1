# An entry of one of Atelier's apps in ES-DE's system carousel. ES-DE only shows the
# systems of its es_systems.xml files, so this adds one to the user's custom_systems
# file, keeping the systems already there. Its only "game" is a small launcher script in
# the app's data folder: choosing it starts the app the way a game starts, with Windows
# PowerShell, and ES-DE comes back when the app closes. The launcher reaches this theme
# folder by a relative path and ES-DE finds the launcher through ~, so moving a portable
# ES-DE keeps them working.
#
# New-Carousel describes one app: its system name (also its theme folder), the name
# shown, the name it is sorted by, the launcher's file name, the app's script, a line
# for the launcher's comment, per language the genre and description of its entry in
# the game list, per language the descriptions that entry had before, which an entry
# still showing one swaps for the current one, the names the app had before, which an
# entry already there gives up for the new one, the launchers it had before, which make
# way for the new one and keep their entry in the game list, and the system names it
# had before, whose entries go and whose game list moves to the new name. The file
# comment of a new custom_systems file names every app it may hold.

. ([IO.Path]::Combine($PSScriptRoot, 'esde.ps1'))

$CarouselCommand = '%HIDEWINDOW% %ESCAPESPECIALS% %EMULATOR_OS-SHELL% /C powershell.exe -NoProfile -ExecutionPolicy Bypass -File %ROM%'

function New-Carousel {
  param([string]$name, [string]$fullName, [string]$sortName, [string]$launcher, [string]$app, [string]$comment,
    $entry, [hashtable]$formerDescs = @{}, [string[]]$formerNames = @(), [string[]]$formerLaunchers = @(),
    [string[]]$formerSystems = @(), [string]$developer = 'Atelier', [string]$publisher)
  return @{
    name = $name; fullName = $fullName; sortName = $sortName; launcher = $launcher; app = $app; comment = $comment
    entry = $entry; formerDescs = $formerDescs; formerNames = $formerNames; formerLaunchers = $formerLaunchers; formerSystems = $formerSystems
    developer = $developer; publisher = if ($publisher) { $publisher } else { $fullName }
  }
}

# The entry of a system in an es_systems.xml file
function Get-CarouselBlock([string]$name) {
  return [regex]::new("[ \t]*<system>\s*<name>$([regex]::Escape($name))</name>[\s\S]*?</system>[ \t]*\r?\n?")
}
function Get-CarouselSystemsFile($es) { return [IO.Path]::Combine($es.home, 'custom_systems', 'es_systems.xml') }
function Get-CarouselGamelistDir($es, [string]$name) { return [IO.Path]::Combine($es.home, 'gamelists', $name) }

function Install-Carousel($carousel, $es, [string]$dataDir) {
  $dir = [IO.Path]::Combine($dataDir, 'carousel')
  New-Folder $dir
  $script = Get-RelativePath $dir $carousel.app
  $call = if ([IO.Path]::IsPathRooted($script)) { "& '$($script.Replace("'", "''"))' @args" }
    else { "& ([IO.Path]::Combine(`$PSScriptRoot, '$($script.Replace("'", "''"))')) @args" }
  $lines = @(foreach ($line in $carousel.comment.Split("`n")) { "# $line" })
  Write-TextFile ([IO.Path]::Combine($dir, $carousel.launcher)) ((($lines + $call) -join "`n") + "`n")
  foreach ($former in $carousel.formerLaunchers) { Remove-Path ([IO.Path]::Combine($dir, $former)) }

  $inHome = Get-RelativePath $es.tilde $dir
  $romPath = if ([IO.Path]::IsPathRooted($inHome) -or $inHome.StartsWith('..')) { $dir } else { '~/' + $inHome.Replace('\', '/') }
  # Sorted after the other systems (ES-DE keeps its grouped Collections system after
  # everything), so ES-DE still starts on the first system as before
  $xmlBlock = @(
    '    <system>'
    "        <name>$($carousel.name)</name>"
    "        <fullname>$(ConvertTo-XmlText $carousel.fullName)</fullname>"
    "        <systemsortname>$(ConvertTo-XmlText $carousel.sortName)</systemsortname>"
    "        <path>$(ConvertTo-XmlText $romPath)</path>"
    '        <extension>.ps1</extension>'
    "        <command label=""Atelier"">$CarouselCommand</command>"
    '        <platform>ignore</platform>'
    "        <theme>$($carousel.name)</theme>"
    '    </system>'
    ''
  ) -join "`n"

  $file = Get-CarouselSystemsFile $es
  $block = Get-CarouselBlock $carousel.name
  if ([IO.File]::Exists($file)) {
    $xml = [IO.File]::ReadAllText($file)
    if (-not $block.IsMatch($xml) -and -not [IO.File]::Exists("$file.atelier-backup")) { [IO.File]::Copy($file, "$file.atelier-backup") }
    $xml = $block.Replace($xml, '', 1)
    foreach ($former in $carousel.formerSystems) { $xml = (Get-CarouselBlock $former).Replace($xml, '', 1) }
    $i = $xml.IndexOf('</systemList>')
    if ($i -lt 0) { throw "$file has no </systemList>: fix or remove it, then run this again." }
    $xml = $xml.Substring(0, $i) + $xmlBlock + $xml.Substring($i)
  } else {
    $xml = "<?xml version=""1.0""?>`n<!-- Systems added to ES-DE. RetroAchievements and Catalogue open the apps of the Atelier theme. -->`n<systemList>`n$xmlBlock</systemList>`n"
  }
  Write-TextFile $file $xml

  # The entry's details in the game list, unless ES-DE already keeps them; an entry
  # still named as the app was before takes its new name, also in its description, and
  # the launcher's new path, and one still showing a description the app had before
  # takes the current one, in the same language; a description edited in ES-DE stays.
  # The game list of a former system name is the entry's own.
  $listDir = Get-CarouselGamelistDir $es $carousel.name
  foreach ($former in $carousel.formerSystems) {
    $formerDir = Get-CarouselGamelistDir $es $former
    if (-not [IO.Directory]::Exists($formerDir)) { continue }
    if ([IO.Directory]::Exists($listDir)) { Remove-Path $formerDir } else { Rename-Path $formerDir $listDir }
  }
  $list = [IO.Path]::Combine($listDir, 'gamelist.xml')
  if ([IO.File]::Exists($list)) {
    $text = [IO.File]::ReadAllText($list)
    $next = $text
    foreach ($former in $carousel.formerNames) {
      $old = ConvertTo-XmlText $former
      $new = ConvertTo-XmlText $carousel.fullName
      foreach ($field in 'name', 'publisher') { $next = $next.Replace("<$field>$old</$field>", "<$field>$new</$field>") }
      $next = [regex]::Replace($next, '<desc>[^<]*</desc>', { param($m) $m.Value.Replace($old, $new) })
    }
    foreach ($lang in $carousel.formerDescs.Keys) {
      $own = $carousel.entry[$lang]
      if (-not $own) { $own = $carousel.entry['en'] }
      foreach ($former in $carousel.formerDescs[$lang]) {
        $next = $next.Replace("<desc>$(ConvertTo-XmlText $former)</desc>", "<desc>$(ConvertTo-XmlText $own[1])</desc>")
      }
    }
    foreach ($former in $carousel.formerLaunchers) {
      $next = $next.Replace("<path>./$(ConvertTo-XmlText $former)</path>", "<path>./$(ConvertTo-XmlText $carousel.launcher)</path>")
    }
    if ($next -cne $text) { Write-TextFile $list $next }
  } else {
    $lang = (Get-EsdeLanguage $es)
    $own = $carousel.entry[$lang.Substring(0, [Math]::Min(2, $lang.Length))]
    if (-not $own) { $own = $carousel.entry['en'] }
    $fields = [ordered]@{
      path = "./$($carousel.launcher)"; name = $carousel.fullName; desc = $own[1]; releasedate = '20261101T000000'
      developer = $carousel.developer; publisher = $carousel.publisher; genre = $own[0]; players = '1'
    }
    $body = -join @(foreach ($k in $fields.Keys) { "`t`t<$k>$(ConvertTo-XmlText $fields[$k])</$k>`n" })
    Write-TextFile $list "<?xml version=""1.0""?>`n<gameList>`n`t<game>`n$body`t</game>`n</gameList>`n"
  }
  return $file
}

# Takes the entry out again; the custom_systems file goes too if nothing else is left,
# and its backup once no app of Atelier is left in it
function Remove-Carousel($carousel, $es) {
  $names = @($carousel.name) + @($carousel.formerSystems)
  $file = Get-CarouselSystemsFile $es
  if ([IO.File]::Exists($file)) {
    $xml = [IO.File]::ReadAllText($file)
    foreach ($name in $names) { $xml = (Get-CarouselBlock $name).Replace($xml, '', 1) }
    if ($xml.Contains('<system>')) { Write-TextFile $file $xml } else { Remove-Path $file }
    if (-not $xml.Contains('<command label="Atelier">')) { Remove-Path "$file.atelier-backup" }
  }
  foreach ($name in $names) { Remove-Path (Get-CarouselGamelistDir $es $name) }
}
