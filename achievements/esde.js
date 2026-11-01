// Reads what ES-DE knows about the user's games: where ES-DE keeps its data, its
// systems and their ROM folders, the game files in them, and the names and media the
// scraper gave them. Nothing here writes to ES-DE.
//
// The app ships in the achievements folder of the theme and finds ES-DE from there, as
// the year collection scripts do: the theme is installed in <ES-DE home>/themes/, and a
// portable installation keeps that home next to the executable. Run from anywhere else,
// it needs the ES-DE application folder.

const fs = require('fs');
const os = require('os');
const path = require('path');

const decode = s => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
  .replace(/&apos;/g, "'").replace(/&amp;/g, '&');
const tag = (block, name) => {
  const m = block.match(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`));
  return m ? decode(m[1].trim()) : '';
};
const hasSettings = dir => fs.existsSync(path.join(dir, 'settings', 'es_settings.xml'));

const MEDIA = ['covers', 'miximages', 'screenshots', 'titlescreens', 'fanart', 'marquees', '3dboxes'];
const IMAGE_EXT = ['.png', '.jpg', '.jpeg', '.webp'];

function open(appArg) {
  let home;
  let appDir;
  if (appArg) {
    if (!fs.existsSync(appArg)) throw new Error(`ES-DE application folder not found: ${appArg}`);
    home = hasSettings(path.join(appArg, 'ES-DE')) ? path.join(appArg, 'ES-DE') : path.join(os.homedir(), 'ES-DE');
    appDir = appArg;
  } else {
    // <home>/themes/<theme>/achievements
    home = path.resolve(__dirname, '..', '..', '..');
    appDir = path.dirname(home);
  }
  if (!hasSettings(home)) throw new Error(`ES-DE settings not found in ${home}`);
  const portable = path.resolve(home) === path.resolve(appDir, 'ES-DE');

  const settings = fs.readFileSync(path.join(home, 'settings', 'es_settings.xml'), 'utf8');
  const setting = name => decode((settings.match(new RegExp(`<\\w+ name="${name}" value="([^"]*)"`)) || [])[1] || '');
  // ~ is the user's home folder, or the application folder of a portable installation
  const expand = p => p.replace(/^~(?=$|[\\/])/, portable ? appDir : os.homedir()).replace('%ESPATH%', appDir);
  const romDir = expand(setting('ROMDirectory') || '~/ROMs');
  const mediaDir = expand(setting('MediaDirectory') || '') || path.join(home, 'downloaded_media');

  // Bundled system definitions, overridden by the user's custom_systems
  const systems = {};
  const platformDir = { win32: 'windows', darwin: 'macos' }[process.platform] || 'linux';
  const candidates = [appDir, process.env.ProgramFiles && path.join(process.env.ProgramFiles, 'ES-DE')]
    .filter(Boolean).map(dir => path.join(dir, 'resources', 'systems', platformDir, 'es_systems.xml'));
  const bundled = candidates.find(file => fs.existsSync(file));
  for (const file of [bundled, path.join(home, 'custom_systems', 'es_systems.xml')]) {
    if (!file || !fs.existsSync(file)) continue;
    for (const m of fs.readFileSync(file, 'utf8').matchAll(/<system>([\s\S]*?)<\/system>/g)) {
      const name = tag(m[1], 'name');
      if (!name) continue;
      systems[name] = {
        name,
        fullName: tag(m[1], 'fullname') || name,
        dir: path.resolve(expand(tag(m[1], 'path').replace('%ROMPATH%', romDir))),
        extensions: new Set(tag(m[1], 'extension').split(/\s+/).filter(Boolean).map(e => e.toLowerCase())),
      };
    }
  }

  // The scraped image of a type for a game, if there is one
  function media(system, relPath, type) {
    const base = path.join(mediaDir, system, type, relPath.replace(/^\.\//, '').replace(/\.[^./\\]+$/, ''));
    for (const ext of IMAGE_EXT) if (fs.existsSync(base + ext)) return base + ext;
    return null;
  }

  // The games ES-DE shows for a system: files with one of its extensions, anywhere in
  // its folder, minus the ones hidden in the gamelist
  function games(systemName) {
    const system = systems[systemName];
    if (!system || !fs.existsSync(system.dir)) return [];
    const meta = {};
    const listFile = path.join(home, 'gamelists', systemName, 'gamelist.xml');
    if (fs.existsSync(listFile)) {
      for (const m of fs.readFileSync(listFile, 'utf8').matchAll(/<game>([\s\S]*?)<\/game>/g)) {
        meta[tag(m[1], 'path').replace(/\\/g, '/')] = m[1];
      }
    }
    const found = [];
    (function walk(dir) {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(full);
        else if (system.extensions.has(path.extname(entry.name).toLowerCase())) found.push(full);
      }
    })(system.dir);
    return found.sort().flatMap(file => {
      const relPath = './' + path.relative(system.dir, file).replace(/\\/g, '/');
      const block = meta[relPath] || '';
      if (tag(block, 'hidden') === 'true') return [];
      const name = tag(block, 'name') || path.basename(file).replace(/\.[^.]+$/, '');
      const images = {};
      for (const type of MEDIA) {
        const image = media(systemName, relPath, type);
        if (image) images[type] = image;
      }
      return [{ system: systemName, systemName: system.fullName, file, relPath, name, media: images,
        developer: tag(block, 'developer'), releaseDate: tag(block, 'releasedate').slice(0, 4), description: tag(block, 'desc') }];
    });
  }

  return {
    home,
    appDir,
    // What ~ stands for in ES-DE's paths
    tilde: portable ? appDir : os.homedir(),
    // The theme language, else the application language, else the system's, as it_IT
    language() {
      for (const name of ['ThemeLanguage', 'ApplicationLanguage']) {
        const value = setting(name);
        if (value && value !== 'automatic') return value;
      }
      return Intl.DateTimeFormat().resolvedOptions().locale.replace('-', '_');
    },
    romDir,
    mediaDir,
    systems,
    setting,
    allGames: () => Object.keys(systems).flatMap(games),
  };
}

module.exports = { open };
