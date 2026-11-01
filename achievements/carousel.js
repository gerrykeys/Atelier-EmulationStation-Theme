// The RetroAchievements entry in ES-DE's system carousel. ES-DE only shows the systems
// of its es_systems.xml files, so this adds one to the user's custom_systems file,
// keeping the systems already there. Its only "game" is a small launcher file in the
// app's data folder: choosing it starts the app the way a game starts, and ES-DE comes
// back when the app closes. The launcher reaches this theme folder by a relative path
// and ES-DE finds the launcher through ~, so moving a portable ES-DE keeps them working.

const fs = require('fs');
const path = require('path');

const LAUNCHER = 'RetroAchievements.js';
const BLOCK = /[ \t]*<system>\s*<name>retroachievements<\/name>[\s\S]*?<\/system>[ \t]*\r?\n?/;
const ENTRY = {
  en: ['Achievements', 'Your progress, points and badges in every game of yours that has achievements on RetroAchievements.'],
  it: ['Obiettivi', 'Progressi, punti e badge di ogni tuo gioco che ha obiettivi su RetroAchievements.'],
};

const escape = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const systemsFile = es => path.join(es.home, 'custom_systems', 'es_systems.xml');
const gamelistDir = es => path.join(es.home, 'gamelists', 'retroachievements');

function install(es, dataDir) {
  const dir = path.join(dataDir, 'carousel');
  fs.mkdirSync(dir, { recursive: true });
  let app = path.relative(dir, path.join(__dirname, 'app.js')).replace(/\\/g, '/');
  if (!path.isAbsolute(app) && !app.startsWith('.')) app = `./${app}`;
  fs.writeFileSync(path.join(dir, LAUNCHER), '// Opens the achievements app of the Atelier theme: ES-DE runs this file when\n' +
    '// RetroAchievements is chosen. Written by "Set up achievements".\n' +
    `require(${JSON.stringify(app)});\n`);

  const inHome = path.relative(es.tilde, dir);
  const romPath = inHome.startsWith('..') || path.isAbsolute(inHome) ? dir : `~/${inHome.replace(/\\/g, '/')}`;
  const command = process.platform === 'win32'
    ? '%HIDEWINDOW% %ESCAPESPECIALS% %EMULATOR_OS-SHELL% /C node %ROM%'
    : 'node %ROM%';
  // Sorted after the other systems (ES-DE keeps its grouped Collections system after
  // everything), so ES-DE still starts on the first system as before
  const block = [
    '    <system>',
    '        <name>retroachievements</name>',
    '        <fullname>RetroAchievements</fullname>',
    '        <systemsortname>zzz retroachievements</systemsortname>',
    `        <path>${escape(romPath)}</path>`,
    '        <extension>.js</extension>',
    `        <command label="Atelier">${command}</command>`,
    '        <platform>ignore</platform>',
    '        <theme>retroachievements</theme>',
    '    </system>',
    '',
  ].join('\n');

  const file = systemsFile(es);
  let xml;
  if (fs.existsSync(file)) {
    xml = fs.readFileSync(file, 'utf8');
    if (!BLOCK.test(xml) && !fs.existsSync(`${file}.atelier-backup`)) fs.copyFileSync(file, `${file}.atelier-backup`);
    xml = xml.replace(BLOCK, '');
    if (!xml.includes('</systemList>')) throw new Error(`${file} has no </systemList>: fix or remove it, then run this again.`);
    xml = xml.replace('</systemList>', `${block}</systemList>`);
  } else {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    xml = `<?xml version="1.0"?>\n<!-- Systems added to ES-DE. RetroAchievements opens the achievements app of the Atelier theme. -->\n<systemList>\n${block}</systemList>\n`;
  }
  fs.writeFileSync(file, xml);

  // The entry's details in the game list, unless ES-DE already keeps them
  const list = path.join(gamelistDir(es), 'gamelist.xml');
  if (!fs.existsSync(list)) {
    const [genre, description] = ENTRY[es.language().slice(0, 2)] || ENTRY.en;
    const fields = { path: `./${LAUNCHER}`, name: 'RetroAchievements', desc: description, releasedate: '20261101T000000',
      developer: 'Atelier', publisher: 'RetroAchievements', genre, players: '1' };
    fs.mkdirSync(path.dirname(list), { recursive: true });
    fs.writeFileSync(list, '<?xml version="1.0"?>\n<gameList>\n\t<game>\n' +
      Object.entries(fields).map(([k, v]) => `\t\t<${k}>${escape(v)}</${k}>\n`).join('') + '\t</game>\n</gameList>\n');
  }
  return file;
}

// Takes the entry out again; the custom_systems file goes too if nothing else is left
function remove(es) {
  const file = systemsFile(es);
  if (fs.existsSync(file)) {
    const xml = fs.readFileSync(file, 'utf8').replace(BLOCK, '');
    if (/<system>/.test(xml)) fs.writeFileSync(file, xml);
    else fs.rmSync(file);
  }
  fs.rmSync(`${file}.atelier-backup`, { force: true });
  fs.rmSync(gamelistDir(es), { recursive: true, force: true });
}

module.exports = { install, remove };
