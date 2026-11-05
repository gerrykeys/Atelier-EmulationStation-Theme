# The RetroAchievements entry in ES-DE's system carousel, which opens the app; see
# common/scripts/windows/carousel.ps1.

. ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..', 'common', 'scripts', 'windows', 'carousel.ps1'))

$AchievementsCarousel = New-Carousel -name 'retroachievements' -fullName 'Retro Achievements' -sortName 'zzz retroachievements' `
  -launcher 'RetroAchievements.ps1' -app ([IO.Path]::Combine($PSScriptRoot, 'app.ps1')) `
  -comment "Opens the achievements app of the Atelier theme: ES-DE runs this file when`nRetroAchievements is chosen. Written by `"Retro Achievements - Install`"." `
  -formerNames @('RetroAchievements') -formerLaunchers @('RetroAchievements.js') `
  -entry @{
    en = @('Achievements', 'Your progress, points and badges in every game of yours that has achievements on Retro Achievements.')
    it = @('Obiettivi', 'Progressi, punti e badge di ogni tuo gioco che ha obiettivi su Retro Achievements.')
  }
