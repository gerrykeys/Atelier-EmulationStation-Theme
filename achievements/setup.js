// Asks for the RetroAchievements username and Web API key, checks them with the site
// and saves them in <ES-DE home>/atelier/achievements/config.json. Pressing Enter keeps
// a value saved before. The key is on the site's settings page, under "Keys".
// Then adds RetroAchievements to ES-DE's system carousel (see carousel.js), which
// opens the app. Running it again is safe, also after moving the theme folder.
//
// Usage: node setup.js [--app <ES-DE application folder>] [--data <folder>]
// On Windows, "Set up achievements.cmd" in the theme's scripts/runnable folder runs it.

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { openAll } = require('./library');
const { client } = require('./ra');
const carousel = require('./carousel');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : undefined;
}

(async () => {
  const { es, dataDir, config } = openAll({ app: arg('--app'), data: arg('--data'), configOnly: true });
  console.log(`ES-DE: ${es.home}\n`);
  // Lines are read in turn, so typed and piped answers both work
  const rl = readline.createInterface({ input: process.stdin });
  const lines = rl[Symbol.asyncIterator]();
  const ask = async prompt => {
    process.stdout.write(prompt);
    const { value } = await lines.next();
    return (value || '').trim();
  };
  const username = (await ask(`RetroAchievements username${config.username ? ` [${config.username}]` : ''}: `)) || config.username;
  const apiKey = (await ask(`Web API key${config.apiKey ? ' [keep the saved one]' : ''}: `)) || config.apiKey;
  rl.close();
  if (!username || !apiKey) throw new Error('\nBoth the username and the Web API key are needed.');

  console.log('\nChecking with RetroAchievements...');
  const ra = client({ apiKey, username, cacheDir: path.join(dataDir, 'cache') });
  const profile = await ra.profile();
  if (!profile) throw new Error(`There is no RetroAchievements user called "${username}".`);

  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(path.join(dataDir, 'config.json'), JSON.stringify({ username: profile.User, apiKey }, null, 1));
  console.log(`Saved for ${profile.User} in ${dataDir}`);

  carousel.install(es, dataDir);
  console.log('\nRetroAchievements is in the ES-DE system carousel, after your systems.' +
    '\nRestart ES-DE if it is running. Press B in the app to go back to ES-DE.');
})().catch(err => {
  console.error(err.message);
  process.exit(1);
});
