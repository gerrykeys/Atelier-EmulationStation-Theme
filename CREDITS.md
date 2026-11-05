# Atelier for ES-DE - credits

## Typefaces

- [Google Sans Flex](https://github.com/googlefonts/googlesans-flex) by Google, SIL Open Font License 1.1 (`core/fonts/OFL-GoogleSansFlex.txt`). The `Display` files are static instances at optical size 72 for large titles, the others at optical size 18.
- *Atelier Caps* (`AtelierCaps-*.ttf`) is a letter-spaced derivative of Google Sans Flex made for small capital labels, as the ES-DE theme engine has no letter-spacing property. Only the advance widths and the font names were changed. It is distributed under the same SIL Open Font License 1.1.
- *Atelier Tags* (`AtelierTags.otf`) is built from Atelier Caps Medium by `tools/build-tag-font.js`: its letters set between tag outlines, and contextual substitutions that show only the bracketed parts of a file name. It is distributed under the same SIL Open Font License 1.1.

## System assets

- Controller line drawings from [system-controllers-outline](https://gitlab.com/es-de/themes/system-controllers-outline) by the ES-DE project. The copies in `systems/controllers-tagged` add a tag naming the model, set in Atelier Caps (`tools/build-model-tags.js`)
- System descriptions, release years and manufacturers from [system-metadata](https://gitlab.com/es-de/themes/system-metadata) by the ES-DE project and its contributors

## Scripts

The scripts and the apps run with Windows PowerShell and .NET Framework, draw their images with GDI+ and write the zip files of Catalogue with .NET's own zip support, all part of Windows.

The achievements app (`achievements`, its server in `achievements/scripts/windows`) shows data and badge images from the [RetroAchievements](https://retroachievements.org) web API, fetched with each user's own key. They are not part of the theme. Games are identified with hashes computed the way [rcheevos](https://github.com/RetroAchievements/rcheevos) does.

## Original work

The theme configuration, badges, rating stars, help prompt icons, ambient images, navigation sounds (synthesized by `tools/build-sounds.js`), the achievements app, and the RetroAchievements trophy drawing (`systems/controllers/retroachievements.svg`) and system texts were made for Atelier and are released under the MIT license (see `LICENSE`).
