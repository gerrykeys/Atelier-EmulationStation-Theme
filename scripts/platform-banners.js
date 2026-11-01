// Covers with a platform banner, for the Grid and Gallery tiles of the Collections system.
//
// ES-DE draws every grid or gallery tile with a single game image, so a label that
// changes from game to game can only be part of that image. For each game this writes a
// square picture, the shape of a tile in the Collections system: down the left side the
// name of the platform, read from the bottom up like the spine labels on many boxes, and
// the cover beside it. The band behind the name is left transparent: the Grid draws it
// under every tile in the surface color of the active color scheme (grid-band-*.svg),
// so it follows a change of scheme. The name is set in a bronze that reads on the dark
// and the light schemes alike. It is stored as
// the game's miximage, which Atelier doesn't use otherwise; inside the Collections
// system the theme shows miximages first and falls back to the cover.
//
// A miximage that was already there is moved to <ES-DE home>/atelier/miximages-backup
// and put back when the banner is removed, or when the game no longer needs one. The
// pictures written here carry a marker, and <ES-DE home>/atelier/miximages.json lists
// them, so nothing else is ever deleted.
//
// Drawing needs @resvg/resvg-js (installed next to this file by the .cmd scripts);
// without it the banners are skipped and the tiles keep their covers.

const fs = require('fs');
const path = require('path');

// The number changes with the design, so older pictures are drawn again
const MARKER = 'Atelier platform banner 3';
const SIZE = 400; // pixels, about twice the size of a tile on a 1440p screen
const BAND = 60; // as in core/images/grid-band-collections.svg
const INK = '#93703C'; // contrast of at least 3.4 on every scheme's surface and background
const IMAGE_EXTENSIONS = ['.png', '.jpg', '.webp'];

// Short names for the band; other systems use their full name without parentheses
const LABELS = {
  '3do': '3DO', amiga: 'Amiga', amigacd32: 'CD32', amstradcpc: 'Amstrad CPC', arcade: 'Arcade',
  atari2600: 'Atari 2600', atari5200: 'Atari 5200', atari7800: 'Atari 7800', atarijaguar: 'Jaguar',
  atarilynx: 'Lynx', atarist: 'Atari ST', c64: 'Commodore 64', colecovision: 'ColecoVision', cps1: 'CPS-1',
  cps2: 'CPS-2', cps3: 'CPS-3', dos: 'MS-DOS', dreamcast: 'Dreamcast', famicom: 'Famicom', fbneo: 'Arcade',
  fds: 'Famicom Disk System', gamegear: 'Game Gear', gb: 'Game Boy', gba: 'Game Boy Advance', gbc: 'Game Boy Color',
  gc: 'GameCube', genesis: 'Genesis', intellivision: 'Intellivision', mame: 'Arcade', mastersystem: 'Master System',
  megacd: 'Mega-CD', megadrive: 'Mega Drive', msx: 'MSX', n3ds: 'Nintendo 3DS', n64: 'Nintendo 64', nds: 'Nintendo DS',
  neogeo: 'Neo Geo', neogeocd: 'Neo Geo CD', nes: 'NES', ngp: 'Neo Geo Pocket', ngpc: 'Neo Geo Pocket Color',
  pc: 'PC', pcengine: 'PC Engine', pcenginecd: 'PC Engine CD', pcfx: 'PC-FX', ps2: 'PlayStation 2',
  ps3: 'PlayStation 3', psp: 'PSP', psvita: 'PS Vita', psx: 'PlayStation', saturn: 'Saturn', sega32x: '32X',
  segacd: 'Sega CD', sfc: 'Super Famicom', sg1000: 'SG-1000', snes: 'Super Nintendo', snesna: 'Super NES',
  supergrafx: 'SuperGrafx', switch: 'Switch', tg16: 'TurboGrafx-16', tgcd: 'TurboGrafx-CD', vectrex: 'Vectrex',
  virtualboy: 'Virtual Boy', wii: 'Wii', wiiu: 'Wii U', wonderswan: 'WonderSwan', wonderswancolor: 'WonderSwan Color',
  x68000: 'X68000', xbox: 'Xbox', zxspectrum: 'ZX Spectrum',
};
const label = (system, fullName) => (LABELS[system] || fullName.replace(/\s*\(.*\)\s*/g, ' ').trim()).toUpperCase();

const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
// The marker is a tEXt chunk right after the PNG header, where isOurs() looks for it
function withMarker(png) {
  const data = Buffer.from(`Software\0${MARKER}`, 'latin1');
  const chunk = Buffer.alloc(12 + data.length);
  chunk.writeUInt32BE(data.length, 0);
  chunk.write('tEXt', 4, 'latin1');
  data.copy(chunk, 8);
  chunk.writeUInt32BE(crc32(chunk.subarray(4, 8 + data.length)), 8 + data.length);
  const ihdrEnd = 8 + 25;
  return Buffer.concat([png.subarray(0, ihdrEnd), chunk, png.subarray(ihdrEnd)]);
}
function marker(file) {
  try {
    const fd = fs.openSync(file, 'r');
    const head = Buffer.alloc(96);
    fs.readSync(fd, head, 0, 96, 0);
    fs.closeSync(fd);
    const m = head.toString('latin1').match(/Atelier platform banner \d+/);
    return m ? m[0] : null;
  } catch {
    return null;
  }
}

const mime = buf => (buf[0] === 0x89 ? 'image/png' : buf[0] === 0xff ? 'image/jpeg' : 'image/webp');
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
const find = base => IMAGE_EXTENSIONS.map(ext => base + ext).find(f => fs.existsSync(f));

// targets: [{ system, gamePath (as in the gamelist), fullName }]
function updateBanners({ home, mediaDir, targets, remove }) {
  const stateDir = path.join(home, 'atelier');
  const manifestFile = path.join(stateDir, 'miximages.json');
  const backupDir = path.join(stateDir, 'miximages-backup');
  const previous = fs.existsSync(manifestFile) ? JSON.parse(fs.readFileSync(manifestFile, 'utf8')) : [];

  // A game's miximage path without extension, relative to the media directory
  const relative = (system, gamePath) => {
    const parsed = path.parse(gamePath.replace(/^\.\//, ''));
    return path.join(system, 'miximages', parsed.dir, parsed.name);
  };
  function restore(rel) {
    const ours = path.join(mediaDir, `${rel}.png`);
    if (marker(ours)) fs.unlinkSync(ours);
    for (const ext of IMAGE_EXTENSIONS) {
      const saved = path.join(backupDir, rel + ext);
      if (!fs.existsSync(saved)) continue;
      fs.mkdirSync(path.dirname(path.join(mediaDir, rel)), { recursive: true });
      fs.renameSync(saved, path.join(mediaDir, rel + ext));
    }
  }

  if (remove) {
    previous.forEach(restore);
    if (fs.existsSync(manifestFile)) fs.unlinkSync(manifestFile);
    // Only empty folders are left behind by the restore
    const prune = dir => {
      if (!fs.existsSync(dir)) return;
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) if (entry.isDirectory()) prune(path.join(dir, entry.name));
      if (fs.readdirSync(dir).length === 0) fs.rmdirSync(dir);
    };
    prune(stateDir);
    return { written: 0, removed: previous.length };
  }

  let Resvg;
  try {
    ({ Resvg } = require('@resvg/resvg-js'));
  } catch {
    console.log('Note: the image library is not installed, so the platform banners were skipped.');
    return null;
  }
  const fontFile = path.join(__dirname, '..', 'core', 'fonts', 'AtelierCaps-Medium.ttf');
  const render = (svg, opts = {}) => new Resvg(svg, { font: { fontFiles: [fontFile], loadSystemFonts: false, defaultFontFamily: 'Atelier Caps' }, ...opts });

  // Font size per label: capitals about 30% of the band, shorter than the tile
  const sizes = new Map();
  function fontSize(text) {
    if (!sizes.has(text)) {
      const probe = render(`<svg xmlns="http://www.w3.org/2000/svg" width="4000" height="200"><text x="10" y="150" font-family="Atelier Caps" font-size="100">${esc(text)}</text></svg>`);
      const box = probe.getBBox();
      const width = box ? box.width / 100 : text.length * 0.8;
      sizes.set(text, Math.min(25, (SIZE * 0.86) / width));
    }
    return sizes.get(text);
  }

  const current = [];
  let written = 0;
  for (const { system, gamePath, fullName } of targets) {
    const rel = relative(system, gamePath);
    const coverBase = path.join(mediaDir, rel.replace(`${path.sep}miximages`, `${path.sep}covers`));
    const cover = find(coverBase);
    if (!cover) continue;
    current.push(rel);
    const target = path.join(mediaDir, `${rel}.png`);
    if (marker(target) === MARKER && fs.statSync(target).mtimeMs >= fs.statSync(cover).mtimeMs) continue;

    // Set aside a miximage of the user's own
    for (const ext of IMAGE_EXTENSIONS) {
      const existing = path.join(mediaDir, rel + ext);
      if (!fs.existsSync(existing) || marker(existing)) continue;
      const saved = path.join(backupDir, rel + ext);
      fs.mkdirSync(path.dirname(saved), { recursive: true });
      fs.renameSync(existing, saved);
    }

    const text = label(system, fullName);
    const size = fontSize(text);
    const data = fs.readFileSync(cover);
    // Rotated a quarter turn back, the capitals stand on a baseline half a capital to
    // the right of the band's middle
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}">
  <image href="data:${mime(data)};base64,${data.toString('base64')}" x="${BAND}" y="0" width="${SIZE - BAND}" height="${SIZE}" preserveAspectRatio="xMinYMid meet"/>
  <text transform="translate(${(BAND / 2 + size * 0.358).toFixed(2)} ${SIZE / 2}) rotate(-90)" text-anchor="middle" font-family="Atelier Caps" font-size="${size.toFixed(2)}" fill="${INK}">${esc(text)}</text>
</svg>`;
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, withMarker(render(svg).render().asPng()));
    written++;
  }

  // Games that no longer need a banner get their own miximage back
  const keep = new Set(current);
  previous.filter(rel => !keep.has(rel)).forEach(restore);
  fs.mkdirSync(stateDir, { recursive: true });
  fs.writeFileSync(manifestFile, JSON.stringify(current, null, 1));
  return { written, total: current.length, removed: previous.filter(rel => !keep.has(rel)).length };
}

module.exports = { updateBanners };
