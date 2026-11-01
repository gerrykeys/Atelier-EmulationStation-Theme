// Talks to the RetroAchievements web API (https://api-docs.retroachievements.org) with
// the user's own Web API key, and keeps every answer in the cache folder: the app then
// opens at once with the last data it saw, refreshes it in the background, and still
// works offline.

const fs = require('fs');
const path = require('path');

const BASE = 'https://retroachievements.org/API/';
const MEDIA = 'https://media.retroachievements.org/';
const AGENT = 'Atelier-ES-DE-Achievements/1.0';
const DAY = 24 * 60 * 60 * 1000;

function client({ apiKey, username, cacheDir }) {
  if (!apiKey) throw new Error('No RetroAchievements Web API key in the configuration');
  fs.mkdirSync(cacheDir, { recursive: true });

  async function call(endpoint, params = {}) {
    const query = new URLSearchParams({ ...params, y: apiKey });
    const res = await fetch(`${BASE}${endpoint}.php?${query}`, { headers: { 'User-Agent': AGENT }, signal: AbortSignal.timeout(15000) });
    if (res.status === 401) throw new Error('RetroAchievements refused the Web API key');
    if (!res.ok) throw Object.assign(new Error(`RetroAchievements answered ${res.status} for ${endpoint}`), { status: res.status });
    return res.json();
  }

  // The cached answer if it is younger than maxAge, else a fresh one; the cached answer
  // again if the site can't be reached
  async function cached(name, maxAge, fetcher) {
    const file = path.join(cacheDir, `${name}.json`);
    let stale = null;
    if (fs.existsSync(file)) {
      stale = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (Date.now() - stale.time < maxAge) return stale.data;
    }
    try {
      const data = await fetcher();
      fs.writeFileSync(file, JSON.stringify({ time: Date.now(), data }));
      return data;
    } catch (err) {
      if (stale) return stale.data;
      throw err;
    }
  }

  return {
    username,
    // The user's public profile, or null if there is no such user (never cached)
    profile: () => call('API_GetUserProfile', { u: username })
      .catch(err => { if (err.status === 404 || err.status === 422) return null; throw err; }),
    consoles:() => cached('consoles', 30 * DAY, () => call('API_GetConsoleIDs', { a: 1, g: 1 })),
    // Every game of a console that has achievements, with the hashes of its supported files
    games: consoleId => cached(`games-${consoleId}`, 7 * DAY,
      () => call('API_GetGameList', { i: consoleId, f: 1, h: 1 })),
    // The files a game supports, by name, for games whose version isn't among them
    versions: gameId => cached(`versions-${gameId}`, 7 * DAY, () => call('API_GetGameHashes', { i: gameId })),
    // A game's achievements, with the user's unlocks when a username is configured
    game: (gameId, maxAge = 0) => cached(`game-${gameId}`, maxAge, () => username
      ? call('API_GetGameInfoAndUserProgress', { g: gameId, u: username, a: 1 })
      : call('API_GetGameExtended', { i: gameId })),
    // The user's profile and points, kept for offline use
    summary: () => username ? cached('profile', 0, () => call('API_GetUserProfile', { u: username })) : null,
    // How far the user got in every game they played, in pages of 500
    completion: () => username ? cached('completion', 0, async () => {
      const results = [];
      for (let total = Infinity; results.length < total;) {
        const page = await call('API_GetUserCompletionProgress', { u: username, c: 500, o: results.length });
        results.push(...page.Results);
        total = page.Results.length ? page.Total : 0;
      }
      return results;
    }) : [],
    // A badge or game image from the site's media server, such as Badge/711081.png,
    // downloaded once
    async image(remote) {
      const file = path.join(cacheDir, 'media', ...remote.split('/'));
      if (!fs.existsSync(file)) {
        const res = await fetch(`${MEDIA}${remote}`, { headers: { 'User-Agent': AGENT }, signal: AbortSignal.timeout(15000) });
        if (!res.ok) throw Object.assign(new Error(`No image ${remote}`), { status: res.status });
        fs.mkdirSync(path.dirname(file), { recursive: true });
        fs.writeFileSync(file, Buffer.from(await res.arrayBuffer()));
      }
      return file;
    },
  };
}

module.exports = { client };
