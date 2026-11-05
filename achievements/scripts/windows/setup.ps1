# Adds RetroAchievements to ES-DE's system carousel (see carousel.ps1), which opens the
# app. It asks nothing: the app signs in the first time it opens, with the username
# RetroArch is signed in with, when it is, and the Web API key the user enters there
# (retroachievements.org, Settings, Keys). Running it again is safe, also after moving
# the theme folder, and keeps the saved username and key.
#
# Usage: powershell -File setup.ps1 [--app <ES-DE application folder>] [--data <folder>]
# "Retro Achievements - Install.cmd" in the theme's scripts/runnable/windows folder runs it.

. ([IO.Path]::Combine($PSScriptRoot, 'library.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'retroarch.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'carousel.ps1'))

try {
  $ctx = Open-Achievements (Get-CliArg $args '--app') (Get-CliArg $args '--data') -configOnly
  Write-Line "ES-DE: $($ctx.es.home)"
  Write-Line
  New-Folder $ctx.dataDir
  [void](Install-Carousel $AchievementsCarousel $ctx.es $ctx.dataDir)
  Write-Line 'Retro Achievements is in the ES-DE system carousel, after your systems.'
  if ($ctx.config['apiKey']) { Write-Line "Signed in as $($ctx.config['username'])." }
  else {
    $found = Find-RetroArch $ctx.es
    $user = if ($found) { $found.config['cheevos_username'] } else { $null }
    if ($user) { Write-Line "The first time it opens, it signs in as $user, RetroArch's user, with your Web API key." }
    else { Write-Line 'The first time it opens, it asks for your username and Web API key.' }
    Write-Line 'The key is on retroachievements.org, under Settings, Keys.'
  }
  Write-Line
  Write-Line 'Restart ES-DE if it is running. Press B in the app to go back to ES-DE.'
} catch {
  Write-Failure (Get-ErrorMessage $_)
  exit 1
}
