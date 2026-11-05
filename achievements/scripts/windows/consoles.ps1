# ES-DE systems and the RetroAchievements consoles their games belong to. Only the
# consoles the site has active achievement sets for are listed.

$RaConsoles = @{
  1 = 'genesis', 'megadrive', 'megadrivejp'
  2 = 'n64'
  3 = 'snes', 'snesna', 'sfc', 'satellaview', 'sufami'
  4 = 'gb'
  5 = 'gba'
  6 = 'gbc'
  7 = 'nes', 'famicom'
  8 = 'pcengine', 'tg16', 'supergrafx'
  9 = 'segacd', 'megacd', 'megacdjp'
  10 = 'sega32x', 'sega32xjp', 'sega32xna'
  11 = 'mastersystem'
  12 = 'psx'
  13 = 'atarilynx'
  14 = 'ngp', 'ngpc'
  15 = 'gamegear'
  16 = 'gc'
  17 = 'atarijaguar'
  18 = 'nds'
  19 = 'wii'
  21 = 'ps2'
  23 = 'odyssey2', 'videopac'
  24 = 'pokemini'
  25 = 'atari2600'
  27 = 'arcade', 'mame', 'fbneo', 'fba', 'cps', 'cps1', 'cps2', 'cps3', 'neogeo'
  28 = 'virtualboy'
  29 = 'msx', 'msx1', 'msx2'
  33 = 'sg-1000'
  37 = 'amstradcpc'
  38 = 'apple2'
  39 = 'saturn', 'saturnjp'
  40 = 'dreamcast'
  41 = 'psp'
  43 = '3do'
  44 = 'colecovision'
  45 = 'intellivision'
  46 = 'vectrex'
  47 = 'pc88'
  49 = 'pcfx'
  51 = 'atari7800'
  53 = 'wonderswan', 'wonderswancolor'
  56 = 'neogeocd', 'neogeocdjp'
  57 = 'channelf'
  63 = 'supervision'
  69 = 'megaduck'
  71 = 'arduboy'
  72 = 'wasm4'
  73 = 'arcadia'
  76 = 'pcenginecd', 'tg-cd'
  77 = 'atarijaguarcd'
  80 = 'uzebox'
  81 = 'fds'
}

$RaConsoleOf = [System.Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
foreach ($id in $RaConsoles.Keys) { foreach ($s in $RaConsoles[$id]) { $RaConsoleOf[$s] = $id } }

# The RetroAchievements console of an ES-DE system, or $null
function Get-RaConsole([string]$system) {
  $id = 0
  if ($RaConsoleOf.TryGetValue($system, [ref]$id)) { return $id }
  return $null
}
