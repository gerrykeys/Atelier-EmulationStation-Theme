# Takes Catalogue out of ES-DE: the system carousel entry and its game list, its
# collections in ES-DE with their sort names, the platform banners older versions drew
# (the user's own miximages are put back), and the app's folder with its settings and
# its window's profile (<ES-DE home>/atelier/catalogue). The archives
# themselves, with their collections, and the games stay as they are; so do the saves
# set aside before a download replaced them (saves-backup), which are the user's own.
# ES-DE must be closed when it has collections of Catalogue, as it may write its
# settings as it ends.
#
# Usage: powershell -File remove.ps1 [--app <ES-DE application folder>] [--data <folder>]
# "Catalogue - Uninstall.cmd" in the theme's scripts/runnable/windows folder runs it.

. ([IO.Path]::Combine($PSScriptRoot, 'carousel.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'collections.ps1'))

try {
  $es = Open-Esde (Get-CliArg $args '--app')
  $dataDir = Get-CatalogueDataDir $es (Get-CliArg $args '--data')
  $recordFile = [IO.Path]::Combine($dataDir, 'collections.json')
  $inEsde = [IO.File]::Exists($recordFile)
  if ($inEsde -and [Diagnostics.Process]::GetProcessesByName('ES-DE').Count) {
    throw 'ES-DE is running: close it first, then run this again.'
  }
  Write-Line "ES-DE: $($es.home)"
  Write-Line
  Remove-Carousel $CatalogueCarousel $es
  if ($inEsde) {
    $removed = Remove-EsdeCollections $es $recordFile
    Write-Line "Collections taken out of ES-DE: $($removed.collections); sort names removed from $($removed.sortNames) games."
  }
  $banners = Remove-PlatformBanners $es
  if ($banners) { Write-Line "Platform banners removed from $banners games, their own miximages put back." }
  $kept = [IO.Path]::Combine($dataDir, 'saves-backup')
  if ([IO.Directory]::Exists($dataDir)) {
    foreach ($entry in [IO.Directory]::GetFileSystemEntries($dataDir)) {
      if ([IO.Path]::GetFileName($entry) -ne 'saves-backup') { Remove-Path $entry }
    }
    if (-not [IO.Directory]::EnumerateFileSystemEntries($dataDir).GetEnumerator().MoveNext()) { [IO.Directory]::Delete($dataDir) }
  }
  # The atelier folder too, if the app was all it held
  $parent = Get-Parent $dataDir
  if ([IO.Path]::GetFileName($parent) -eq 'atelier' -and [IO.Directory]::Exists($parent) -and
    -not [IO.Directory]::EnumerateFileSystemEntries($parent).GetEnumerator().MoveNext()) {
    [IO.Directory]::Delete($parent)
  }
  Write-Line 'Catalogue is uninstalled from ES-DE, with its settings. Your archives, their collections and your games are untouched.'
  if ([IO.Directory]::Exists($kept)) { Write-Line "Saves set aside before downloads are still in $kept." }
  Write-Line 'Restart ES-DE if it is running.'
} catch {
  Write-Failure (Get-ErrorMessage $_)
  exit 1
}
