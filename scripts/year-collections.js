// Builds one ES-DE custom collection per release year ("1988", "1990", ...) from the
// scraped release dates in the gamelists, and makes the games inside each year group
// by platform.
//
// - Writes ES-DE/collections/custom-<year>.cfg and enables the years in es_settings.xml
//   (CollectionSystemsCustom). With "Group custom collections" set to "If unthemed" or
//   "Always" they show up as folders inside the Collections system.
// - Sets the collectionsortname of every dated game to "<platform> <title>". ES-DE only
//   uses this field inside custom collections, so the regular system gamelists keep
//   their order. Each gamelist.xml is copied to gamelist.xml.atelier-backup the first
//   time it is changed.
// - Gives every game shown in the Collections system (the dated ones, and those in the
//   user's other enabled custom collections) a cover with a platform banner for the Grid
//   and Gallery tiles, see platform-banners.js.
// - With --remove, deletes the year collections, disables them, removes the sort names
//   this script wrote (values it did not write are left alone) and puts the original
//   miximages back.
//
// Collections are recognized by their four-digit names, so custom collections called
// like a year are treated as belonging to this script. ES-DE must be closed while this
// runs, as it rewrites its settings and gamelists when it exits.
//
// The script ships in the scripts folder of the theme and finds ES-DE from there: the
// theme is installed in <ES-DE home>/themes/, and a portable installation keeps that
// home next to the executable. The system names come from the system list bundled
// with ES-DE; where it isn't found (an installed copy elsewhere, an AppImage), pass the
// application folder, or the short system names are used for grouping instead.
//
// Usage: node year-collections.js [--remove] [ES-DE application folder]
// On Windows, "Update year collections.cmd" and "Remove year collections.cmd" in the
// runnable folder next to it run it.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');
const { updateBanners } = require('./platform-banners');

const remove = process.argv.includes('--remove');
const appArg = process.argv.slice(2).find(arg => arg !== '--remove');

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (process.platform === 'win32') {
  const tasks = execSync('tasklist /FI "IMAGENAME eq ES-DE.exe" /NH', { encoding: 'utf8' });
  if (/ES-DE\.exe/i.test(tasks)) fail('ES-DE is running: close it first, then run this again.');
}

const hasSettings = dir => fs.existsSync(path.join(dir, 'settings', 'es_settings.xml'));
let home;
let appDirs;
if (appArg) {
  // Portable installations keep their data next to the executable
  if (!fs.existsSync(appArg)) fail(`ES-DE application folder not found: ${appArg}`);
  home = hasSettings(path.join(appArg, 'ES-DE')) ? path.join(appArg, 'ES-DE') : path.join(os.homedir(), 'ES-DE');
  appDirs = [appArg];
} else {
  // <home>/themes/<theme>/scripts
  home = path.resolve(__dirname, '..', '..', '..');
  if (!hasSettings(home)) {
    fail('ES-DE settings not found. Run this from the theme installed in the ES-DE themes folder,\n' +
      'or pass the ES-DE application folder: node year-collections.js [--remove] <folder>');
  }
  appDirs = [path.dirname(home)];
  if (process.env.ProgramFiles) appDirs.push(path.join(process.env.ProgramFiles, 'ES-DE'));
}
const settingsFile = path.join(home, 'settings', 'es_settings.xml');
const collectionsDir = path.join(home, 'collections');
const gamelistsDir = path.join(home, 'gamelists');
if (!fs.existsSync(settingsFile)) fail(`ES-DE settings not found in ${home}`);

const decode = s => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
  .replace(/&apos;/g, "'").replace(/&amp;/g, '&');
const encode = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const tag = (block, name) => {
  const m = block.match(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`));
  return m ? decode(m[1].trim()) : '';
};

// Systems: bundled definitions, overridden by the user's custom_systems
const systems = {};
const platformDir = { win32: 'windows', darwin: 'macos' }[process.platform] || 'linux';
const bundled = appDirs.map(dir => path.join(dir, 'resources', 'systems', platformDir, 'es_systems.xml'))
  .find(file => fs.existsSync(file));
if (!bundled) console.log('Note: the ES-DE system list was not found, so games are grouped by the short system names.');
for (const file of [bundled, path.join(home, 'custom_systems', 'es_systems.xml')]) {
  if (!file || !fs.existsSync(file)) continue;
  for (const m of fs.readFileSync(file, 'utf8').matchAll(/<system>([\s\S]*?)<\/system>/g)) {
    const name = tag(m[1], 'name');
    if (name) systems[name] = { fullName: tag(m[1], 'fullname') || name, path: tag(m[1], 'path') };
  }
}

// Collection entries use %ROMPATH% when the system lives in the ROM directory
function collectionEntry(system, gamePath) {
  const relative = gamePath.replace(/^\.\//, '');
  const dir = (systems[system] && systems[system].path) || `%ROMPATH%/${system}`;
  return `${dir.replace(/\\/g, '/').replace(/\/+$/, '')}/${relative}`;
}

const sortName = (fullName, block) => `${fullName} ${tag(block, 'sortname') || tag(block, 'name')}`;

let settings = fs.readFileSync(settingsFile, 'utf8');
const setting = name => (settings.match(new RegExp(`<string name="${name}" value="([^"]*)"`)) || [])[1];

// Media directory as ES-DE resolves it
let mediaDir = decode(setting('MediaDirectory') || '');
if (!mediaDir) mediaDir = path.join(home, 'downloaded_media');
mediaDir = mediaDir.replace(/^~(?=$|[\\/])/, os.homedir()).replace('%ESPATH%', appDirs[0] || path.dirname(home));

// Games of the user's other enabled custom collections, which also get banners
const otherEntries = new Set();
for (const name of (setting('CollectionSystemsCustom') || '').split(',').map(s => s.trim())) {
  const file = path.join(collectionsDir, `custom-${name}.cfg`);
  if (!name || /^\d{4}$/.test(name) || !fs.existsSync(file)) continue;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) if (line.trim()) otherEntries.add(line.trim().replace(/\\/g, '/'));
}

// Gamelists: collect the years and update the collection sort names
const years = new Map();
const bannerTargets = [];
let changedGames = 0;
for (const system of fs.existsSync(gamelistsDir) ? fs.readdirSync(gamelistsDir) : []) {
  const file = path.join(gamelistsDir, system, 'gamelist.xml');
  if (!fs.existsSync(file)) continue;
  const fullName = (systems[system] && systems[system].fullName) || system;
  const original = fs.readFileSync(file, 'utf8');
  const updated = original.replace(/([ \t]*)<game>([\s\S]*?)<\/game>/g, (whole, indent, body) => {
    const year = (tag(body, 'releasedate').match(/^(\d{4})/) || [])[1];
    const current = body.match(/\n?[ \t]*<collectionsortname>[\s\S]*?<\/collectionsortname>/);
    const currentValue = tag(body, 'collectionsortname');
    // Sort names written by this script start with the platform name; others are the user's
    const ours = current && currentValue.startsWith(`${fullName} `);

    if (remove) {
      if (!ours) return whole;
      changedGames++;
      return `${indent}<game>${body.replace(current[0], '')}</game>`;
    }
    const entry = collectionEntry(system, tag(body, 'path'));
    if (year || otherEntries.has(entry)) bannerTargets.push({ system, gamePath: tag(body, 'path'), fullName });
    if (!year) return whole;
    const entries = years.get(year) || [];
    entries.push(entry);
    years.set(year, entries);

    const value = encode(sortName(fullName, body));
    if (current && (!ours || currentValue === sortName(fullName, body))) return whole;
    changedGames++;
    if (current) return `${indent}<game>${body.replace(current[0], `\n${indent}\t<collectionsortname>${value}</collectionsortname>`)}</game>`;
    const inner = body.replace(/\s*$/, '');
    return `${indent}<game>${inner}\n${indent}\t<collectionsortname>${value}</collectionsortname>\n${indent}</game>`;
  });
  if (updated !== original) {
    const backup = `${file}.atelier-backup`;
    if (!fs.existsSync(backup)) fs.copyFileSync(file, backup);
    fs.writeFileSync(file, updated);
  }
}

// Collection files: one per year, stale years removed
fs.mkdirSync(collectionsDir, { recursive: true });
for (const file of fs.readdirSync(collectionsDir)) {
  const m = file.match(/^custom-(\d{4})\.cfg$/);
  if (m && (remove || !years.has(m[1]))) fs.unlinkSync(path.join(collectionsDir, file));
}
const yearNames = remove ? [] : [...years.keys()].sort();
for (const year of yearNames) {
  fs.writeFileSync(path.join(collectionsDir, `custom-${year}.cfg`), years.get(year).sort().join('\n') + '\n');
}

// Settings: keep the user's other custom collections, replace the years
const enabledLine = /<string name="CollectionSystemsCustom" value="([^"]*)" \/>/;
const previous = (settings.match(enabledLine) || [])[1];
const others = (previous || '').split(',').map(s => s.trim()).filter(s => s && !/^\d{4}$/.test(s));
const value = [...others, ...yearNames].sort().join(',');
const line = `<string name="CollectionSystemsCustom" value="${value}" />`;
// es_settings.xml is a flat list of entries without a root element
settings = previous !== undefined ? settings.replace(enabledLine, line) : `${settings.replace(/\s*$/, '')}\n${line}\n`;
fs.writeFileSync(settingsFile, settings);

const banners = updateBanners({ home, mediaDir, targets: bannerTargets, remove });

if (remove) {
  console.log(`Year collections removed; sort names removed from ${changedGames} games.`);
  console.log(`Platform banners removed from ${banners.removed} games, their own miximages put back.`);
} else {
  for (const year of yearNames) console.log(`${year}: ${years.get(year).length} games`);
  console.log(`${yearNames.length} year collections written and enabled; sort names updated for ${changedGames} games.`);
  if (banners) console.log(`Platform banners: ${banners.total} games (${banners.written} drawn now), ${banners.removed} no longer needed.`);
  const grouping = (settings.match(/<string name="CollectionCustomGrouping" value="([^"]*)"/) || [])[1];
  if (grouping === 'never') console.log('Note: "Group custom collections" is set to "Never", so every year appears as its own system.');
}
