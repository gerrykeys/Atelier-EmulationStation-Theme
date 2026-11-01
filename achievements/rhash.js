// Identifies a game file the way RetroAchievements does (the rcheevos library inside
// RetroArch): an MD5 of the ROM data without the copier or emulator headers some dumps
// carry, or of the file name for arcade sets. Zipped games are hashed by the file inside,
// as RetroArch extracts them before loading. Disc-based consoles hash parts of the disc
// image's file system and aren't supported yet.

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const DISC = new Set([9, 12, 16, 18, 19, 21, 39, 40, 41, 43, 49, 56, 76, 77]);
const ARCHIVES = new Set(['.zip', '.7z']);

// The first file in a zip archive with one of the given extensions (or any file)
function unzip(file, extensions) {
  const buf = fs.readFileSync(file);
  let end = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { end = i; break; }
  }
  if (end < 0) throw new Error('not a zip archive');
  const entries = [];
  let p = buf.readUInt32LE(end + 16);
  for (let n = buf.readUInt16LE(end + 10); n > 0 && buf.readUInt32LE(p) === 0x02014b50; n--) {
    const nameLen = buf.readUInt16LE(p + 28);
    const name = buf.toString('utf8', p + 46, p + 46 + nameLen);
    if (!name.endsWith('/')) {
      entries.push({ name, method: buf.readUInt16LE(p + 10), size: buf.readUInt32LE(p + 20), local: buf.readUInt32LE(p + 42) });
    }
    p += 46 + nameLen + buf.readUInt16LE(p + 30) + buf.readUInt16LE(p + 32);
  }
  const entry = entries.find(e => extensions.has(path.extname(e.name).toLowerCase())) || entries[0];
  if (!entry) throw new Error('empty zip archive');
  const start = entry.local + 30 + buf.readUInt16LE(entry.local + 26) + buf.readUInt16LE(entry.local + 28);
  const data = buf.subarray(start, start + entry.size);
  if (entry.method === 0) return data;
  if (entry.method === 8) return zlib.inflateRawSync(data);
  throw new Error(`zip compression method ${entry.method} is not supported`);
}

// The part of the ROM that RetroAchievements hashes
function romData(consoleId, data) {
  switch (consoleId) {
    case 7: // NES: iNES header
    case 81: // Famicom Disk System: fwNES header
      return /^(NES|FDS)\x1a/.test(data.toString('latin1', 0, 4)) ? data.subarray(16) : data;
    case 3: // SNES: copier header
      return data.length % 8192 === 512 ? data.subarray(512) : data;
    case 8: // PC Engine: copier header
      return data.length % 131072 === 512 ? data.subarray(512) : data;
    case 13: // Lynx: LNX header
      return data.toString('latin1', 0, 4) === 'LYNX' && data[4] === 0 ? data.subarray(64) : data;
    case 51: // Atari 7800: A78 header
      return data.toString('latin1', 1, 10) === 'ATARI7800' ? data.subarray(128) : data;
    case 2: { // Nintendo 64: big-endian byte order
      const magic = data.readUInt32BE(0);
      const out = Buffer.from(data);
      if (magic === 0x37804012) for (let i = 0; i + 1 < out.length; i += 2) out.writeUInt16BE(data.readUInt16LE(i), i);
      if (magic === 0x40123780) for (let i = 0; i + 3 < out.length; i += 4) out.writeUInt32BE(data.readUInt32LE(i), i);
      return out;
    }
    default:
      return data;
  }
}

// Famicom Disk System images, with or without their header, which ES-DE keeps in its
// NES and Famicom systems and RetroAchievements lists as a console of its own
const isDisk = data => data.toString('latin1', 0, 4) === 'FDS\x1a' || data.toString('latin1', 1, 15) === '*NINTENDO-HVC*';

// { hash, consoleId } or { unsupported: reason }
function hashGame(file, consoleId, extensions) {
  const ext = path.extname(file).toLowerCase();
  const md5 = data => crypto.createHash('md5').update(data).digest('hex');
  if (consoleId === 27) return { hash: md5(path.basename(file, path.extname(file))), consoleId };
  if (DISC.has(consoleId)) return { unsupported: 'disc-based games are not supported yet' };
  if (ext === '.7z') return { unsupported: '7z archives are not supported yet' };
  const inner = new Set([...extensions].filter(e => !ARCHIVES.has(e)));
  const data = ext === '.zip' ? unzip(file, inner) : fs.readFileSync(file);
  if (consoleId === 7 && isDisk(data)) consoleId = 81;
  return { hash: md5(romData(consoleId, data)), consoleId };
}

module.exports = { hashGame };
