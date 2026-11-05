# Adds Catalogue to ES-DE's system carousel (see carousel.ps1). Nothing else is needed:
# the games' zip files are made with what comes with Windows (see zip.ps1). It asks
# nothing: the archive's folder and the rest are chosen in the app.
# Running it again is safe, also after moving the theme folder.
#
# Usage: powershell -File setup.ps1 [--app <ES-DE application folder>] [--data <folder>]
# "Catalogue - Install.cmd" in the theme's scripts/runnable/windows folder runs it.

. ([IO.Path]::Combine($PSScriptRoot, 'carousel.ps1'))

try {
  $es = Open-Esde (Get-CliArg $args '--app')
  $dataDir = Get-CatalogueDataDir $es (Get-CliArg $args '--data')
  Write-Line "ES-DE: $($es.home)"
  New-Folder $dataDir
  # The copy of 7-Zip an early version downloaded is no longer used
  $oldBin = [IO.Path]::Combine($dataDir, 'bin')
  if ([IO.File]::Exists([IO.Path]::Combine($oldBin, '7zr.exe'))) { Remove-Path $oldBin }
  [void](Install-Carousel $CatalogueCarousel $es $dataDir)
  Write-Line
  Write-Line 'Catalogue is in the ES-DE system carousel, after your systems.'
  Write-Line 'Restart ES-DE if it is running, open Catalogue and choose where your archive lives.'
} catch {
  Write-Failure (Get-ErrorMessage $_)
  exit 1
}
