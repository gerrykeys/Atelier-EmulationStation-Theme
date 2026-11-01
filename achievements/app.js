// The achievements app: a small web server, reachable only from this computer, that
// serves the page in ui/ and the data it shows, and a full-screen Microsoft Edge window
// (or Chrome) that shows it. Leaving the page ends both, which hands control back to
// ES-DE. The Web API key stays in this process; the page never sees it.
//
// Usage: node app.js [--app <ES-DE application folder>] [--data <folder>]
//                    [--port <number>] [--no-window]
// --no-window only starts the server and prints its address, for testing in a browser.

const fs = require('fs');
const http = require('http');
const path = require('path');
const { spawn, execFileSync } = require('child_process');
const { openAll, matchGames } = require('./library');
const theme = require('./theme');
const progressImages = require('./progress');

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.ttf': 'font/ttf', '.otf': 'font/otf', '.wav': 'audio/wav',
};
const UI = path.join(__dirname, 'ui');
// The theme files the page may load: fonts, help icons, images, sounds and drawings
const THEME_DIRS = ['core', path.join('systems', 'controllers')];

function arg(name) {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : undefined;
}

const ctx = openAll({ app: arg('--app'), data: arg('--data'), configOnly: true });
const { es, dataDir } = ctx;
let ra = null;
let setupError = null;
try {
  Object.assign(ctx, openAll({ app: arg('--app'), data: arg('--data') }));
  ra = ctx.ra;
} catch (err) {
  setupError = err.message;
}

function session() {
  const lang = es.language();
  const fontSize = es.setting('ThemeFontSize') || 'medium';
  return {
    language: lang,
    labels: theme.labels(lang),
    colors: theme.colors(es.setting('ThemeColorScheme')),
    systems: theme.systems(),
    fontSizes: theme.fontSizes(fontSize),
    layouts: theme.layouts(fontSize),
    aspectRatio: es.setting('ThemeAspectRatio') || 'automatic',
    controller: es.setting('InputControllerType') || 'xbox',
    sounds: es.setting('NavigationSounds') !== 'false',
    volume: Number(es.setting('SoundVolumeNavigation') || 70) / 100,
    username: ctx.config.username || null,
    setupError,
    prefs: readPrefs(),
  };
}

// The view and order chosen in the app's options menu
const prefsFile = path.join(dataDir, 'prefs.json');
function readPrefs() {
  try {
    return JSON.parse(fs.readFileSync(prefsFile, 'utf8'));
  } catch {
    return {};
  }
}
function savePrefs(req) {
  return new Promise(resolve => {
    let body = '';
    req.on('data', chunk => { body = (body + chunk).slice(0, 2000); });
    req.on('end', () => {
      try {
        const { mode, sort } = JSON.parse(body);
        fs.mkdirSync(dataDir, { recursive: true });
        fs.writeFileSync(prefsFile, JSON.stringify({ mode: String(mode), sort: String(sort) }));
      } catch {}
      resolve();
    });
  });
}

// The user's games that have achievements, with how far they got, and their profile
let library = null;
let games = [];
async function loadLibrary() {
  const matched = (await matchGames(ctx)).filter(g => g.ra);
  const [completion, profile] = await Promise.all([
    ra.completion().catch(() => null),
    Promise.resolve(ra.summary()).catch(() => null),
  ]);
  // The progress images in ES-DE, redrawn after the page has its data; never from an
  // empty answer, which would show no unlocks
  if (completion && progressImages.isOn(dataDir)) {
    setTimeout(() => {
      try { progressImages.refresh(es, progressImages.entries(matched, completion)); } catch (err) { console.error(err.message); }
    }, 500);
  }
  const progress = new Map((completion || []).map(c => [c.GameID, c]));
  const collator = new Intl.Collator(es.language().replace('_', '-'), { sensitivity: 'base', numeric: true });
  games = matched.sort((a, b) => collator.compare(a.name, b.name));
  setTimeout(prefetch, 1500);
  return {
    user: profile && { name: profile.User, points: profile.TotalPoints, softcorePoints: profile.TotalSoftcorePoints },
    games: games.map((g, i) => {
      const p = progress.get(g.ra.id);
      const media = type => g.media[type] ? `/media/${i}/${type}` : null;
      return {
        index: i, name: g.name, system: g.system, systemName: g.systemName, description: g.description,
        image: media('screenshots') || media('titlescreens'), backdrop: media('fanart') || media('screenshots'),
        cover: media('covers'),
        // Files that couldn't be hashed (some disc images) aren't known to be unsupported
        ra: g.ra, supported: g.supported || !g.hash, note: g.note,
        progress: p ? { awarded: p.NumAwarded, awardedHardcore: p.NumAwardedHardcore, max: p.MaxPossible, award: p.HighestAwardKind,
          last: p.MostRecentAwardedDate } : null,
      };
    }),
  };
}

// A game's achievements and the user's unlocks: fetched once per run, from the cache
// when the site can't be reached
const details = new Map();
function gameDetails(id) {
  if (!details.has(id)) {
    const job = (async () => {
      const data = await ra.game(id);
      const unsupported = games.some(g => g.ra.id === id && !g.supported);
      const versions = unsupported ? await ra.versions(id).then(v => v.Results.map(r => r.Name)).catch(() => []) : [];
      const list = Object.values(data.Achievements || {}).sort((a, b) => a.DisplayOrder - b.DisplayOrder || a.ID - b.ID);
      return {
        id: data.ID, title: data.Title, genre: data.Genre, players: data.NumDistinctPlayers,
        playtime: data.UserTotalPlaytime || 0, award: data.HighestAwardKind || null, versions,
        boxArt: data.ImageBoxArt ? data.ImageBoxArt.replace(/^\//, '') : null,
        achievements: list.map(a => ({
          id: a.ID, title: a.Title, description: a.Description, points: a.Points, retroPoints: a.TrueRatio,
          type: a.Type || null, badge: a.BadgeName, awarded: a.NumAwarded, awardedHardcore: a.NumAwardedHardcore,
          author: a.Author, earned: a.DateEarned || null, earnedHardcore: a.DateEarnedHardcore || null,
        })),
      };
    })();
    job.catch(() => details.delete(id));
    details.set(id, job);
  }
  return details.get(id);
}

// Fetches the other games in the background, one at a time, so browsing doesn't wait
async function prefetch() {
  for (const id of new Set(games.map(g => g.ra.id))) await gameDetails(id).catch(() => {});
}

function send(res, status, body, type = 'application/json') {
  res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  res.end(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body));
}

function sendFile(res, file, maxAge = 0) {
  fs.readFile(file, (err, data) => {
    if (err) return send(res, 404, { error: 'Not found' });
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream',
      'Cache-Control': maxAge ? `max-age=${maxAge}` : 'no-cache' });
    res.end(data);
  });
}

// A path inside dir, or null if the request tries to leave it
function inside(dir, rel) {
  const file = path.resolve(dir, rel);
  return file.startsWith(path.resolve(dir) + path.sep) ? file : null;
}

let browser = null;
let quitting = false;
function quit() {
  if (quitting) return;
  quitting = true;
  // The page closes its window; this only cleans up if it couldn't
  setTimeout(() => {
    if (browser && browser.exitCode === null) {
      if (process.platform === 'win32') {
        try { execFileSync('taskkill', ['/PID', String(browser.pid), '/T', '/F'], { stdio: 'ignore' }); } catch {}
      } else browser.kill();
    }
    process.exit(0);
  }, 3000).unref();
  if (!browser) setTimeout(() => process.exit(0), 200);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const route = decodeURIComponent(url.pathname);
  try {
    if (route === '/') return sendFile(res, path.join(UI, 'index.html'));
    if (route.startsWith('/ui/')) {
      const file = inside(UI, route.slice(4));
      return file ? sendFile(res, file) : send(res, 404, { error: 'Not found' });
    }
    if (route.startsWith('/theme/')) {
      const rel = route.slice(7);
      const file = THEME_DIRS.some(dir => rel.startsWith(dir.replace(/\\/g, '/') + '/')) && inside(theme.ROOT, rel);
      return file ? sendFile(res, file, 3600) : send(res, 404, { error: 'Not found' });
    }
    if (route === '/api/session') return send(res, 200, session());
    if (route === '/api/games') {
      if (setupError) return send(res, 409, { error: setupError });
      if (!library) library = loadLibrary().catch(err => { library = null; throw err; });
      return send(res, 200, await library);
    }
    if (route === '/api/game') return send(res, 200, await gameDetails(Number(url.searchParams.get('id'))));
    const media = route.match(/^\/media\/(\d+)\/(\w+)$/);
    if (media) {
      const file = games[media[1]] && games[media[1]].media[media[2]];
      return file ? sendFile(res, file, 3600) : send(res, 404, { error: 'Not found' });
    }
    const image = route.match(/^\/ra\/((?:Badge|Images)\/[\w-]+\.png)$/);
    if (image) return sendFile(res, await ra.image(image[1]), 86400);
    if (route === '/api/prefs' && req.method === 'POST') {
      await savePrefs(req);
      return send(res, 200, { ok: true });
    }
    if (route === '/api/quit' && req.method === 'POST') {
      send(res, 200, { ok: true });
      return quit();
    }
    send(res, 404, { error: 'Not found' });
  } catch (err) {
    send(res, 500, { error: err.message });
  }
});

function findBrowser() {
  if (process.platform === 'win32') {
    const roots = [process.env['ProgramFiles(x86)'], process.env.ProgramFiles, process.env.LOCALAPPDATA].filter(Boolean);
    const apps = [['Microsoft', 'Edge', 'Application', 'msedge.exe'], ['Google', 'Chrome', 'Application', 'chrome.exe']];
    for (const app of apps) for (const root of roots) {
      const file = path.join(root, ...app);
      if (fs.existsSync(file)) return file;
    }
    return null;
  }
  const mac = ['/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/Applications/Chromium.app/Contents/MacOS/Chromium'];
  for (const file of mac) if (fs.existsSync(file)) return file;
  for (const name of ['microsoft-edge', 'google-chrome', 'chromium', 'chromium-browser']) {
    try { return execFileSync('which', [name], { encoding: 'utf8' }).trim(); } catch {}
  }
  return null;
}

server.listen(Number(arg('--port') || 0), '127.0.0.1', () => {
  const url = `http://127.0.0.1:${server.address().port}/`;
  if (process.argv.includes('--no-window')) return console.log(`Achievements: ${url}`);
  const exe = findBrowser();
  if (!exe) {
    console.error('Microsoft Edge or Google Chrome is needed to show the achievements.');
    process.exit(1);
  }
  // Its own profile, so the window is a process of its own that ends when it closes
  browser = spawn(exe, [
    `--user-data-dir=${path.join(dataDir, 'browser')}`, '--no-first-run', '--no-default-browser-check',
    '--autoplay-policy=no-user-gesture-required', '--kiosk', '--edge-kiosk-type=fullscreen', url,
  ], { stdio: 'ignore' });
  browser.on('exit', () => process.exit(0));
});
