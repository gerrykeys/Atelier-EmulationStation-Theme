// Achievement progress in ES-DE's game details: for every game with achievements a
// small image, "12 / 74", a bar and the percentage, which the theme shows beside the
// game's facts (raProgress in layout/gamelist-details.xml and gamelist-gallery.xml).
// ES-DE has no field of its own for it, so the images take the place of the physical
// media images, which Atelier shows nowhere else. Those already there, scraped before
// or after, are moved to <ES-DE home>/atelier/physicalmedia-backup and put back when
// the progress is turned off. The images are white; the theme tints them with the
// accent color of the scheme. Each carries its figures in a PNG text chunk, which tells
// it apart from the user's own images and saves redrawing it when nothing changed.
//
// While the progress is on, the achievements app redraws the images each time it opens.
// Usage: node progress.js [--off] [--app <ES-DE application folder>] [--data <folder>]
// On Windows, "Enable achievement progress.cmd" and "Disable achievement progress.cmd"
// in the theme's scripts/runnable folder.

const fs = require('fs');
const path = require('path');

const TYPE = 'physicalmedia';
const MARKER = 'Atelier achievement progress';
// Raised whenever the drawing changes, so that every image is drawn again
const VERSION = 2;
// Canvas height, and the length of the bar and the room for the percentage, in pixels
const HEIGHT = 100;
const BAR = 360;
const PERCENT = 230;
const GAP = 48;

// The library for drawing is installed in the theme's scripts folder, as for the
// platform banners of the year collections
function loadResvg() {
  try {
    return require(require.resolve('@resvg/resvg-js', { paths: [path.join(__dirname, '..', 'scripts')] })).Resvg;
  } catch {
    return null;
  }
}

function withMarker(png, value) {
  const data = Buffer.from(`Software\0${MARKER} ${value};`, 'latin1');
  const chunk = Buffer.alloc(12 + data.length);
  chunk.writeUInt32BE(data.length, 0);
  chunk.write('tEXt', 4, 'latin1');
  data.copy(chunk, 8);
  chunk.writeUInt32BE(require('zlib').crc32(chunk.subarray(4, 8 + data.length)) >>> 0, 8 + data.length);
  return Buffer.concat([png.subarray(0, 33), chunk, png.subarray(33)]);
}

// The version and figures an image of ours was drawn with, such as "2 12/74", or null
// for any other file
function marker(file) {
  try {
    const fd = fs.openSync(file, 'r');
    const head = Buffer.alloc(120);
    fs.readSync(fd, head, 0, 120, 0);
    fs.closeSync(fd);
    // The semicolon ends the figures before the chunk's checksum
    const m = head.toString('latin1').match(/Atelier achievement progress ([\d /]+)/);
    return m ? m[1] : null;
  } catch {
    return null;
  }
}

function files(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry =>
    entry.isDirectory() ? files(path.join(dir, entry.name)) : [path.join(dir, entry.name)]);
}

// Every system's physical media folder
const mediaFolders = es => fs.existsSync(es.mediaDir)
  ? fs.readdirSync(es.mediaDir).map(system => ({ system, dir: path.join(es.mediaDir, system, TYPE) })).filter(f => fs.existsSync(f.dir))
  : [];
const backupDir = es => path.join(es.home, 'atelier', 'physicalmedia-backup');
const flagFile = dataDir => path.join(dataDir, 'progress.json');

// The theme shows the images only while the progress is on, so that the physical media
// images of a library without it never appear in their place. The switch is a variable
// in progress.xml, next to this file; a reinstalled theme gets it back on the app's
// next start.
function showInTheme(on) {
  const file = path.join(__dirname, 'progress.xml');
  const xml = fs.readFileSync(file, 'utf8');
  const next = xml.replace(/<raProgressVisible>\w+<\/raProgressVisible>/, `<raProgressVisible>${on}</raProgressVisible>`);
  if (next !== xml) fs.writeFileSync(file, next);
}

function prune(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) if (entry.isDirectory()) prune(path.join(dir, entry.name));
  if (!fs.readdirSync(dir).length) fs.rmdirSync(dir);
}

// The figures to draw for the matched games of library.js and the user's completion
// progress from the site
function entries(games, completion) {
  const byGame = new Map(completion.map(c => [c.GameID, c]));
  return games.filter(g => g.ra).map(g => {
    const c = byGame.get(g.ra.id);
    return { system: g.system, relPath: g.relPath, unlocked: c ? c.NumAwarded : 0, total: (c && c.MaxPossible) || g.ra.achievements };
  });
}

function refresh(es, list) {
  const Resvg = loadResvg();
  if (!Resvg) return null;
  const font = { fontFiles: [path.join(__dirname, '..', 'core', 'fonts', 'AtelierCaps-Medium.ttf')], loadSystemFonts: false, defaultFontFamily: 'Atelier Caps' };
  const text = (s, x, anchor = 'start') =>
    `<text x="${x}" y="75" text-anchor="${anchor}" font-family="Atelier Caps" font-size="72" fill="#fff">${s}</text>`;
  const widths = new Map();
  const width = s => {
    if (!widths.has(s)) {
      const box = new Resvg(`<svg xmlns="http://www.w3.org/2000/svg" width="2000" height="${HEIGHT}">${text(s, 0)}</svg>`, { font }).getBBox();
      widths.set(s, box ? Math.ceil(box.x + box.width) : s.length * 50);
    }
    return widths.get(s);
  };

  // Set aside every physical media image that isn't ours, including newly scraped ones
  let setAside = 0;
  for (const { system, dir } of mediaFolders(es)) {
    for (const file of files(dir)) {
      if (marker(file)) continue;
      const saved = path.join(backupDir(es), system, path.relative(dir, file));
      fs.mkdirSync(path.dirname(saved), { recursive: true });
      fs.renameSync(file, saved);
      setAside++;
    }
  }

  const wanted = new Set();
  let written = 0;
  for (const e of list) {
    const file = path.join(es.mediaDir, e.system, TYPE, e.relPath.replace(/^\.\//, '').replace(/\.[^./\\]+$/, '') + '.png');
    wanted.add(file);
    const value = `${VERSION} ${e.unlocked}/${e.total}`;
    if (marker(file) === value) continue;
    const left = `${e.unlocked} / ${e.total}`;
    const share = e.total ? Math.min(1, e.unlocked / e.total) : 0;
    const x = width(left) + GAP;
    const canvas = x + BAR + GAP + PERCENT;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${canvas}" height="${HEIGHT}">
  ${text(left, 0)}
  <rect x="${x}" y="45" width="${BAR}" height="10" fill="#fff" fill-opacity="0.28"/>
  <rect x="${x}" y="45" width="${(BAR * share).toFixed(1)}" height="10" fill="#fff"/>
  ${text(`${Math.floor(share * 100)}%`, canvas, 'end')}
</svg>`;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, withMarker(new Resvg(svg, { font }).render().asPng(), value));
    written++;
  }

  showInTheme(true);
  // Images of games that are gone or no longer matched
  let removed = 0;
  for (const { dir } of mediaFolders(es)) {
    for (const file of files(dir)) {
      if (!wanted.has(file) && marker(file)) {
        fs.unlinkSync(file);
        removed++;
      }
    }
  }
  return { written, removed, setAside };
}

const isOn = dataDir => fs.existsSync(flagFile(dataDir));

// Deletes the progress images and puts the user's physical media images back
function remove(es, dataDir) {
  let removed = 0;
  for (const { dir } of mediaFolders(es)) {
    for (const file of files(dir)) {
      if (marker(file)) {
        fs.unlinkSync(file);
        removed++;
      }
    }
  }
  let restored = 0;
  const backup = backupDir(es);
  for (const saved of files(backup)) {
    const [system, ...rest] = path.relative(backup, saved).split(path.sep);
    const target = path.join(es.mediaDir, system, TYPE, ...rest);
    if (fs.existsSync(target)) fs.unlinkSync(saved);
    else {
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.renameSync(saved, target);
      restored++;
    }
  }
  prune(backup);
  fs.rmSync(flagFile(dataDir), { force: true });
  showInTheme(false);
  for (const { dir } of mediaFolders(es)) prune(dir);
  return { removed, restored };
}

module.exports = { entries, refresh, remove, isOn, loadResvg };

if (require.main === module) {
  const { openAll, matchGames } = require('./library');
  const arg = name => {
    const i = process.argv.indexOf(name);
    return i > 0 ? process.argv[i + 1] : undefined;
  };
  (async () => {
    const options = { app: arg('--app'), data: arg('--data') };
    if (process.argv.includes('--off')) {
      const { es, dataDir } = openAll({ ...options, configOnly: true });
      const { removed, restored } = remove(es, dataDir);
      console.log(`Removed ${removed} progress images and put back ${restored} physical media images.` +
        '\nRestart ES-DE if it is running.');
      return;
    }
    const ctx = openAll(options);
    if (!loadResvg()) throw new Error('The image library is not installed: run "Enable achievement progress.cmd", which installs it.');
    console.log('Matching your games with RetroAchievements...');
    const games = (await matchGames(ctx)).filter(g => g.ra);
    const completion = await ctx.ra.completion();
    fs.writeFileSync(flagFile(ctx.dataDir), JSON.stringify({ on: true }));
    const { written, removed, setAside } = refresh(ctx.es, entries(games, completion));
    console.log(`Progress shown for ${games.length} games (${written} images drawn, ${removed} removed).`);
    if (setAside) console.log(`${setAside} physical media images were set aside in ${backupDir(ctx.es)}; they come back when the progress is disabled.`);
    console.log('The achievements app keeps the images up to date each time it opens. Restart ES-DE if it is running.');
  })().catch(err => {
    console.error(err.message);
    process.exit(1);
  });
}
