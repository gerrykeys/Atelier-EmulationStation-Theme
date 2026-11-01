// The user's ES-DE games matched with RetroAchievements: each game file is identified
// by its hash, which is looked up in the site's list of supported files for its console.
// The hashes are remembered by file size and date, so only new or changed files are
// read again. A file whose hash isn't listed is matched by title instead and marked as
// an unsupported version: RetroArch won't unlock anything with it, but the app can
// still show the game's achievements and which versions the site supports.
//
// The configuration (Web API key and username) and the cache live in
// <ES-DE home>/atelier/achievements, outside the theme folder, so updating or
// reinstalling the theme keeps them and the key never ends up in a copy of the theme.
//
// Run on its own it prints the matches:
//   node library.js [--app <ES-DE application folder>] [--data <folder>]

const fs = require('fs');
const path = require('path');
const esde = require('./esde');
const { client } = require('./ra');
const { consoleOf } = require('./consoles');
const { hashGame } = require('./rhash');

// "Lion King, The (USA)" and "The Lion King" both become "lion king"
const titleKey = s => s.replace(/[([][^)\]]*[)\]]/g, ' ').replace(/^(.*), (the|a|an)\b/i, '$2 $1').toLowerCase()
  .replace(/^(the|a|an) /, '').replace(/&/g, 'and').replace(/[^a-z0-9]+/g, ' ').trim();

function arg(name) {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : undefined;
}

// ES-DE, the configuration and, unless configOnly, the RetroAchievements client
function openAll({ app, data, configOnly } = {}) {
  const es = esde.open(app);
  const dataDir = data || path.join(es.home, 'atelier', 'achievements');
  const configFile = path.join(dataDir, 'config.json');
  const config = fs.existsSync(configFile) ? JSON.parse(fs.readFileSync(configFile, 'utf8')) : {};
  if (configOnly) return { es, dataDir, config };
  if (!config.apiKey) throw new Error('RetroAchievements is not set up yet: run "Set up achievements.cmd" in the scripts/runnable folder of the theme first.');
  const ra = client({ apiKey: config.apiKey, username: config.username, cacheDir: path.join(dataDir, 'cache') });
  return { es, ra, dataDir, config };
}

async function matchGames({ es, ra, dataDir }) {
  const hashesFile = path.join(dataDir, 'hashes.json');
  const known = fs.existsSync(hashesFile) ? JSON.parse(fs.readFileSync(hashesFile, 'utf8')) : {};
  const seen = {};
  const lists = {};
  const games = [];
  for (const game of es.allGames()) {
    const consoleId = consoleOf(game.system);
    if (!consoleId) continue;
    const stat = fs.statSync(game.file);
    const stamp = `${stat.size}:${stat.mtimeMs}`;
    let id = known[game.file] && known[game.file].stamp === stamp ? known[game.file] : null;
    if (!id) {
      try {
        id = { stamp, ...hashGame(game.file, consoleId, es.systems[game.system].extensions) };
      } catch (err) {
        id = { stamp, unsupported: err.message };
      }
    }
    seen[game.file] = id;
    const entry = { ...game, hash: id.hash || null, consoleId: id.consoleId || consoleId, ra: null, supported: false, note: id.unsupported || null };
    if (!lists[entry.consoleId]) {
      const byHash = new Map();
      const byTitle = new Map();
      for (const g of await ra.games(entry.consoleId)) {
        for (const h of g.Hashes || []) byHash.set(h.toLowerCase(), g);
        if (!byTitle.has(titleKey(g.Title))) byTitle.set(titleKey(g.Title), g);
      }
      lists[entry.consoleId] = { byHash, byTitle };
    }
    const { byHash, byTitle } = lists[entry.consoleId];
    const exact = id.hash && byHash.get(id.hash);
    const match = exact || byTitle.get(titleKey(game.name)) || byTitle.get(titleKey(path.basename(game.file)));
    if (match) {
      entry.ra = { id: match.ID, title: match.Title, icon: match.ImageIcon, achievements: match.NumAchievements, points: match.Points };
      entry.supported = Boolean(exact);
      if (!exact && id.hash) entry.note = 'this version of the game is not supported';
    } else if (id.hash) {
      entry.note = 'no achievements for this game';
    }
    games.push(entry);
  }
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(hashesFile, JSON.stringify(seen, null, 1));
  return games;
}

module.exports = { openAll, matchGames };

if (require.main === module) {
  (async () => {
    const ctx = openAll({ app: arg('--app'), data: arg('--data') });
    const games = await matchGames(ctx);
    for (const g of games) {
      const result = g.ra ? `${g.ra.title} (game ${g.ra.id}, ${g.ra.achievements} achievements)` : '-';
      console.log(`${g.system.padEnd(8)} ${g.name.padEnd(28)} ${result}${g.note ? `: ${g.note}` : ''}`);
    }
    const count = test => games.filter(test).length;
    console.log(`${count(g => g.supported)} of ${games.length} games can unlock achievements, ` +
      `${count(g => g.ra && !g.supported)} more need another version of the file`);
  })().catch(err => {
    console.error(err.message);
    process.exit(1);
  });
}
