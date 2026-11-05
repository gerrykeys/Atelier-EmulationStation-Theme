# The Catalogue entry in ES-DE's system carousel, which opens the app; see
# common/scripts/windows/carousel.ps1. It comes after RetroAchievements. Catalogue was
# first called Game Archive: its entry was the system gamearchive, with GameArchive
# launchers, and its folder <ES-DE home>/atelier/archive, all of which take the new
# names.

. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'carousel.ps1'))

$CatalogueCarousel = New-Carousel -name 'catalogue' -fullName 'Catalogue' -sortName 'zzzz catalogue' `
  -launcher 'Catalogue.ps1' -app ([IO.Path]::Combine($PSScriptRoot, 'app.ps1')) `
  -comment "Opens Catalogue, the game archive of the Atelier theme: ES-DE runs this file`nwhen Catalogue is chosen. Written by `"Catalogue - Install`"." `
  -formerNames @('Game Archive') -formerLaunchers @('GameArchive.ps1', 'GameArchive.js') -formerSystems @('gamearchive') `
  -entry @{
    en = @('Archive', 'Keep your games in an archive on a network or USB disk, with their details, media and saves, and bring them back into ES-DE. Create and manage your own collections too, game by game or with a search that keeps them up to date.')
    it = @('Archivio', 'Conserva i tuoi giochi in un archivio su un disco di rete o USB, con dettagli, media e salvataggi, e riportali in ES-DE. Crea e gestisci anche le tue collezioni, gioco per gioco o con una ricerca che le tiene aggiornate.')
  } `
  -formerDescs @{
    en = @('Keep your games in an archive on a network or USB disk, with their details, media and saves, and bring them back into ES-DE.')
    it = @('Conserva i tuoi giochi in un archivio su un disco di rete o USB, con dettagli, media e salvataggi, e riportali in ES-DE.')
  }

# Catalogue's own folder, with its settings and its window's profile:
# <ES-DE home>/atelier/catalogue, unless --data names another. The folder of
# its first name is moved there; if it can't be, it is used as it is.
function Get-CatalogueDataDir($es, [string]$dataArg) {
  if ($dataArg) { return [IO.Path]::GetFullPath($dataArg) }
  $dir = [IO.Path]::Combine($es.home, 'atelier', 'catalogue')
  $former = [IO.Path]::Combine($es.home, 'atelier', 'archive')
  if (-not [IO.Directory]::Exists($dir) -and [IO.Directory]::Exists($former)) {
    try { Rename-Path $former $dir } catch { return $former }
  }
  return $dir
}
