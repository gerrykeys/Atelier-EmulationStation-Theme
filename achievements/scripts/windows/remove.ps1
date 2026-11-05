# Takes RetroAchievements out of ES-DE: the system carousel entry and its game list,
# the progress images (putting the physical media images back), and the app's folder
# with the username, Web API key and cache
# (<ES-DE home>/atelier/achievements). The theme itself stays as it is.
#
# Usage: powershell -File remove.ps1 [--app <ES-DE application folder>] [--data <folder>]
# "Retro Achievements - Uninstall.cmd" in the theme's scripts/runnable/windows folder runs it.

. ([IO.Path]::Combine($PSScriptRoot, 'progress.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'carousel.ps1'))

try {
  $ctx = Open-Achievements (Get-CliArg $args '--app') (Get-CliArg $args '--data') -configOnly
  Write-Line "ES-DE: $($ctx.es.home)"
  Write-Line
  Remove-Carousel $AchievementsCarousel $ctx.es
  [void](Remove-Progress $ctx.es $ctx.dataDir)
  Remove-Path $ctx.dataDir
  # The atelier folder too, if the app was all it held
  $parent = Get-Parent $ctx.dataDir
  if ([IO.Path]::GetFileName($parent) -eq 'atelier' -and [IO.Directory]::Exists($parent) -and
    -not [IO.Directory]::EnumerateFileSystemEntries($parent).GetEnumerator().MoveNext()) {
    [IO.Directory]::Delete($parent)
  }
  Write-Line 'Retro Achievements is uninstalled from ES-DE, with its settings and cache.'
  Write-Line 'Restart ES-DE if it is running.'
} catch {
  Write-Failure (Get-ErrorMessage $_)
  exit 1
}
