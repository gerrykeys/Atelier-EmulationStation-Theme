// Takes RetroAchievements out of ES-DE: the system carousel entry and its game list,
// the progress images (putting the physical media images back), and the app's folder
// with the username, Web API key and cache
// (<ES-DE home>/atelier/achievements). The theme itself stays as it is.
//
// Usage: node remove.js [--app <ES-DE application folder>] [--data <folder>]
// On Windows, "Remove achievements.cmd" in the theme's scripts/runnable folder runs it.

const fs = require('fs');
const path = require('path');
const { openAll } = require('./library');
const carousel = require('./carousel');
const progress = require('./progress');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : undefined;
}

try {
  const { es, dataDir } = openAll({ app: arg('--app'), data: arg('--data'), configOnly: true });
  console.log(`ES-DE: ${es.home}\n`);
  carousel.remove(es);
  progress.remove(es, dataDir);
  fs.rmSync(dataDir, { recursive: true, force: true });
  // The atelier folder too, if the app was all it held
  const parent = path.dirname(dataDir);
  if (path.basename(parent) === 'atelier' && fs.existsSync(parent) && !fs.readdirSync(parent).length) fs.rmdirSync(parent);
  console.log('RetroAchievements is removed from ES-DE, with its settings and cache.' +
    '\nRestart ES-DE if it is running.');
} catch (err) {
  console.error(err.message);
  process.exit(1);
}
