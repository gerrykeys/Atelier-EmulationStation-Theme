// The page: a library of the games that have achievements, on one shelf of box covers
// per platform (after a shelf of the games in progress), and for the chosen game its
// wall of badges. LB/RB filter the library by progress and Y sorts it; on the wall
// they change game and view. Header, help prompts, details column and media card sit
// where the theme's Grid layout puts them for the screen's aspect ratio, in fractions
// of the screen width and height as ES-DE does, with the parts all of Atelier's apps
// share in common/ui/atelier.js. Driven by a controller through the Gamepad API, or by
// the keyboard.

let library = { user: null, games: [] };
const state = { screen: 'games', mode: 'grid', filter: 'all', sort: 'recent', shelf: 0, picks: {}, game: 0, badge: 0, view: 'set', menu: null };
const details = new Map();
const G = {}; // elements of the library
const A = {}; // elements of the wall of badges
let shelves = [];

const FILTERS = ['all', 'playing', 'new', 'done'];
const SORTS = ['recent', 'progress', 'name'];
const VIEWS = ['set', 'locked', 'unlocked'];
// How the library shows the games: shelves of covers, a list of names, names with covers
const MODES = ['grid', 'list', 'covers'];
// In fractions of the screen height: the progress block at the top of the content
const OVERVIEW = 0.115;

const badgeUrl = (badge, locked) => `/ra/Badge/${badge}${locked ? '_lock' : ''}.png`;

function buildGames() {
  const root = document.getElementById('games');
  root.replaceChildren();
  const l = L.achievements;
  const b = contentBox();
  const { art } = header(root, l, 'Retro Achievements');
  art.style.setProperty('--src', `url(${themeUrl('systems/controllers/retroachievements.svg')})`);
  G.corner = corner(root, l);
  // The filters take the place of the label above the bar, which shows their progress
  G.overview = progressBlock(root, b.left, b.top + 0.012, b.right - b.left);
  G.tabs = place(el('div', 'tabs', root), { pos: [b.left, b.top + 0.012], size: [(b.right - b.left) * 0.85, 0.04] }, { origin: [0, 0.5] });
  G.shelves = place(el('div', 'shelves', root),
    { pos: [b.left - SHELF_PAD, b.top + OVERVIEW], size: [b.right - b.left + 2 * SHELF_PAD, b.bottom - b.top - OVERVIEW + 0.02] });
  G.track = el('div', 'track', G.shelves);
  G.listBox = place(el('div', 'listbox', root), { pos: [b.left, b.top + OVERVIEW], size: [b.right - b.left, b.bottom - b.top - OVERVIEW + 0.02] });
  G.listTrack = el('div', 'track', G.listBox);
  G.message = place(el('div', 'message', root), { pos: [b.left, b.top + OVERVIEW + 0.03], size: [b.right - b.left, 0.2] });
  G.info = place(el('div', 'line caps-light info', root), l.gamelistInfo, { line: true });

  G.title = place(el('div', 'title', root), l.gameTitle);
  place(el('div', 'rule', root), l.captionRule);
  G.caption = place(el('div', 'line caps caption', root), l.genre, { line: true });
  G.tag = tag(root, l);
  const d = l.description;
  G.progress = progressBlock(root, d.pos[0], d.pos[1] + 0.018, d.size[0]);
  G.media = mediaCard(root, l, 'videoStill');
  G.facts = [
    fact(root, l, 'labelReleased', 'releaseDate'), fact(root, l, 'labelDeveloper', 'developer'),
    fact(root, l, 'labelPublisher', 'publisher'), fact(root, l, 'labelPlayers', 'players'),
  ];
  G.next = place(el('div', 'next', root), l.badges);
}

function buildAchievements() {
  const root = document.getElementById('achievements');
  root.replaceChildren();
  const l = L.achievements;
  const b = contentBox();
  const { art, title } = header(root, l, '');
  A.headerArt = art;
  A.header = title;
  A.corner = corner(root, l);
  A.overview = progressBlock(root, b.left, b.top + 0.012, b.right - b.left);
  A.wall = place(el('div', 'wall', root), { pos: [b.left, b.top + OVERVIEW], size: [b.right - b.left, b.bottom - b.top - OVERVIEW + 0.02] });
  A.tiles = el('div', 'tiles', A.wall);
  A.message = place(el('div', 'message', root), { pos: [b.left, b.top + OVERVIEW + 0.03], size: [b.right - b.left, 0.2] });
  A.info = place(el('div', 'line caps-light info', root), l.gamelistInfo, { line: true });
  A.title = place(el('div', 'title', root), l.gameTitle);
  place(el('div', 'rule', root), l.captionRule);
  A.caption = place(el('div', 'line caps caption', root), l.genre, { line: true });
  A.tag = tag(root, l);
  A.description = scroller(place(el('div', 'description', root), l.description));
  A.media = mediaCard(root, l, 'videoStill');
  A.facts = [
    fact(root, l, 'labelReleased', 'releaseDate'), fact(root, l, 'labelDeveloper', 'developer'),
    fact(root, l, 'labelPublisher', 'publisher'), fact(root, l, 'labelPlayers', 'players'),
  ];
}

// Help prompts with the theme's icons for the controller chosen in ES-DE
function renderHelp() {
  const menu = ['start', T.help.menu];
  if (keyboard.isOpen()) {
    return showHelp([['dpad_all', T.help.choose], ['a', T.help.type], ['x', T.help.erase], ['y', T.help.space],
      ['start', T.help.done], ['b', T.help.cancel]]);
  }
  if (state.account) return showHelp([['dpad_updown', T.help.choose], ['a', T.help.select], ['b', T.help.close]]);
  showHelp(state.menu !== null
    ? [['dpad_updown', T.help.choose], ['dpad_leftright', T.help.change], ['a', T.help.select], ['b', T.help.close]]
    : state.screen === 'games'
      ? [['dpad_all', T.help.choose], ['button_lr', T.help.filter], ['y', T.help.sort], ['a', T.help.select], ['b', T.help.back], menu]
      : [['dpad_all', T.help.choose], ['button_lr', T.help.game], ['y', T.help.view], ['b', T.help.back], menu]);
}

function duration(seconds) {
  if (!seconds) return null;
  const minutes = Math.round(seconds / 60);
  return minutes < 60 ? T.minutes(minutes) : T.hours(Math.floor(minutes / 60), minutes % 60);
}

// How far the user got in a game: from its achievements once they are loaded, else
// from the summary of all games that came with the library
function progressOf(g) {
  const d = details.get(g.ra.id);
  if (d) {
    const earned = d.achievements.filter(a => a.earned);
    return {
      unlocked: earned.length, hardcore: d.achievements.filter(a => a.earnedHardcore).length,
      total: d.achievements.length, points: earned.reduce((sum, a) => sum + a.points, 0),
      totalPoints: d.achievements.reduce((sum, a) => sum + a.points, 0),
      last: earned.map(a => parseDate(a.earned).toISOString()).sort().pop() || null, award: d.award,
    };
  }
  const p = g.progress;
  return {
    unlocked: p ? p.awarded : 0, hardcore: p ? p.awardedHardcore : 0, total: (p && p.max) || g.ra.achievements,
    points: null, totalPoints: g.ra.points, last: p && p.last ? parseDate(p.last).toISOString() : null, award: p ? p.award : null,
  };
}
const fraction = p => p.total ? p.unlocked / p.total : 0;

// Filters and sorting use only the summary, so the shelves don't move while the
// achievements of every game load in the background
function summaryOf(g) {
  const p = g.progress;
  const total = (p && p.max) || g.ra.achievements;
  return { unlocked: p ? p.awarded : 0, total, award: p ? p.award : null, last: p && p.last ? parseDate(p.last).toISOString() : '' };
}
function status(g) {
  const s = summaryOf(g);
  if (s.award === 'mastered' || s.award === 'completed' || (s.total && s.unlocked >= s.total)) return 'done';
  return s.unlocked ? 'playing' : 'new';
}
function sorted(list, sort = state.sort) {
  const s = i => summaryOf(library.games[i]);
  const share = i => s(i).total ? s(i).unlocked / s(i).total : 0;
  const compare = {
    recent: (a, b) => s(b).last.localeCompare(s(a).last),
    progress: (a, b) => share(b) - share(a),
    name: () => 0,
  }[sort];
  // The library comes sorted by name, which settles ties
  return [...list].sort((a, b) => compare(a, b) || a - b);
}

function showCorner() {
  const u = library.user;
  const text = u ? `${u.name}  ·  ${T.points(number(u.points))}` : (S.username || '');
  G.corner.textContent = text;
  A.corner.textContent = text;
}

// The library

function shelfData() {
  const all = library.games.map((g, i) => i);
  const shown = sorted(all.filter(i => state.filter === 'all' || status(library.games[i]) === state.filter));
  const out = [];
  if (state.filter === 'all') {
    const playing = sorted(shown.filter(i => status(library.games[i]) === 'playing'), 'recent');
    if (playing.length) out.push({ key: 'continue', title: T.continue, games: playing.slice(0, 12) });
  }
  const bySystem = new Map();
  for (const i of shown) {
    const system = library.games[i].system;
    if (!bySystem.has(system)) bySystem.set(system, []);
    bySystem.get(system).push(i);
  }
  const names = new Intl.Collator(locale());
  const systems = [...bySystem.keys()].sort((a, b) =>
    names.compare(library.games[bySystem.get(a)[0]].systemName, library.games[bySystem.get(b)[0]].systemName));
  for (const system of systems) {
    const games = bySystem.get(system);
    out.push({ key: system, system, title: library.games[games[0]].systemName, games });
  }
  return out;
}

function renderTabs() {
  G.tabs.replaceChildren(...FILTERS.map(f => {
    const count = library.games.filter(g => f === 'all' || status(g) === f).length;
    const tab = el('span', `tab${f === state.filter ? ' active' : ''}${count ? '' : ' empty'}`, null, T.filters[f]);
    el('span', 'count', tab, number(count));
    return tab;
  }));
}

// The progress of the games the filter shows
function renderOverview() {
  const shown = library.games.filter(g => state.filter === 'all' || status(g) === state.filter);
  const unique = new Map(shown.map(g => [g.ra.id, g]));
  let unlocked = 0;
  let total = 0;
  let done = 0;
  for (const g of unique.values()) {
    const s = summaryOf(g);
    unlocked += s.unlocked;
    total += s.total;
    if (status(g) === 'done') done++;
  }
  G.overview('', total ? unlocked / total : 0, T.overallLine(number(unlocked), number(total), number(done), number(unique.size)));
}

// Box covers come from ES-DE's scraped media, else from RetroAchievements, else the
// name is set on the surface color as in the theme's grid; in the list, where there is
// no room for the name, the game's icon stands in
const coverPics = new Map();
function fillCover(pic, g) {
  const d = details.get(g.ra.id);
  const url = g.cover || (d && d.boxArt && `/ra/${d.boxArt}`) || (pic.dataset.icon && `/ra${g.ra.icon}`);
  if (url) {
    const img = pic.querySelector('img') || el('img');
    if (img.getAttribute('src') !== url) img.src = url;
    pic.replaceChildren(img);
  } else if (!pic.firstChild) el('div', 'typo', pic, g.name);
}

// The library in the chosen view: the same groups, as shelves of covers or as a list
// under platform headings
function renderLibrary(keep) {
  shelves = shelfData();
  coverPics.clear();
  G.shelves.hidden = state.mode !== 'grid';
  G.listBox.hidden = state.mode === 'grid';
  if (state.mode === 'grid') drawShelves(G, shelves, drawGame);
  else drawList(G, shelves, state.mode === 'covers', drawGame);
  const count = new Set(shelves.flatMap(s => s.games)).size;
  G.info.textContent = `${T.games(number(count))}  ·  ${T.sorts[state.sort]}`;
  message(G.message, shelves.length ? null : (library.games.length ? T.noneHere : T.empty),
    library.games.length ? T.noneHereText : T.emptyText);
  renderTabs();
  renderOverview();
  state.picks = {};
  if (!shelves.length) return clearDetails();
  // Stay on the same game when the library changes, in its platform's group, if it is
  // still there
  let target = [0, 0];
  const found = keep === undefined ? [] : shelves.map((sh, s) => [s, sh.games.indexOf(keep)]).filter(([, n]) => n >= 0);
  if (found.length) target = found.find(([s]) => shelves[s].key !== 'continue') || found[0];
  select(target[0], target[1]);
}

// What the shelves and lists show of a game: its cover, its progress beneath, and in the
// list with covers the achievements unlocked
const drawGame = {
  system: i => library.games[i].system,
  name: i => library.games[i].name,
  fill(pic, i) {
    fillCover(pic, library.games[i]);
    coverPics.set(i, [...(coverPics.get(i) || []), pic]);
  },
  beneath(tile, i, coverHeight) {
    const H = innerHeight;
    const progress = bar(tile);
    progress.track.style.top = `${coverHeight + 0.01 * H}px`;
    progress.track.style.height = `${Math.max(1, Math.round(0.0025 * H))}px`;
    progress(fraction(progressOf(library.games[i])));
  },
  meta(meta, i) {
    const p = progressOf(library.games[i]);
    bar(meta)(fraction(p));
    el('span', '', meta, `${number(p.unlocked)} / ${number(p.total)}`);
  },
};

function select(s, item) {
  state.shelf = clamp(s, 0, shelves.length - 1);
  const shelf = shelves[state.shelf];
  const pick = clamp(item ?? state.picks[shelf.key] ?? 0, 0, shelf.games.length - 1);
  state.picks[shelf.key] = pick;
  state.game = shelf.games[pick];
  if (state.mode === 'grid') highlightShelves(G, shelves, state.shelf, pick, state.picks);
  else highlightList(G, shelves, shelf, pick);
  showGame();
  loadDetails(library.games[state.game]);
}

function clearDetails() {
  G.title.textContent = '';
  G.caption.textContent = '';
  G.tag([]);
  G.progress('', null, '');
  G.media(null, '');
  G.facts.forEach(f => f('', ''));
  G.next.replaceChildren();
}

let detailTimer = null;
function loadDetails(game) {
  clearTimeout(detailTimer);
  if (!details.has(game.ra.id)) detailTimer = setTimeout(() => fetchDetails(game.ra.id), 150);
}

function fetchDetails(id) {
  return fetch(`/api/game?id=${id}`).then(r => r.ok ? r.json() : null).then(d => {
    if (!d || details.has(id)) return;
    details.set(id, d);
    library.games.forEach((g, i) => {
      if (g.ra.id === id) for (const pic of coverPics.get(i) || []) fillCover(pic, g);
    });
    if (library.games[state.game].ra.id === id) {
      showGame();
      if (state.screen === 'achievements') renderWall();
    }
  }).catch(() => {});
}

// The other games' achievements, one at a time, for their covers and details
async function preload() {
  for (const id of new Set(library.games.map(g => g.ra.id))) if (!details.has(id)) await fetchDetails(id);
}

let backdropTimer = null;
function showGame() {
  const g = library.games[state.game];
  const d = details.get(g.ra.id);
  const p = progressOf(g);
  applyColors(g.system);
  G.media(g.image, g.system);
  G.title.textContent = g.name;
  G.caption.textContent = g.systemName;
  G.tag([p.award && T.awards[p.award]]);
  if (g.supported) {
    G.progress(T.progress, fraction(p), T.progressLine(number(p.unlocked), number(p.total),
      p.points == null ? null : number(p.points), number(p.totalPoints)));
  } else G.progress(T.progress, fraction(p), T.unsupportedShort, true);
  G.facts[0](T.players, d && number(d.players));
  G.facts[1](T.lastUnlock, date(p.last));
  G.facts[2](S.labels.langPlayTime, d && duration(d.playtime));
  G.facts[3](T.hardcore, p.unlocked ? `${number(p.hardcore)} / ${number(p.total)}` : null);

  // The locked achievement most players have, or the files the site supports
  G.next.replaceChildren();
  if (d && !g.supported && d.versions.length) {
    el('span', 'caps', G.next, T.supported);
    el('span', '', G.next, d.versions.map(v => v.replace(/\.\w+$/, '')).join('  ·  '));
  } else if (d) {
    const easiest = d.achievements.filter(a => !a.earned).sort((a, b) => b.awarded - a.awarded)[0];
    if (easiest) {
      el('span', 'caps', G.next, T.next);
      el('img', '', G.next).src = badgeUrl(easiest.badge);
      const share = d.players ? Math.round(easiest.awarded / d.players * 100) : null;
      el('span', '', G.next, `${easiest.title}${share == null ? '' : `  ·  ${T.ofPlayers(number(share))}`}`);
    }
  }

  const atmosphere = document.getElementById('atmosphere');
  atmosphere.classList.remove('shown');
  clearTimeout(backdropTimer);
  if (S.colors.atmosphereVisible === 'true' && g.backdrop) {
    backdropTimer = setTimeout(() => {
      atmosphere.onload = () => atmosphere.classList.add('shown');
      if (atmosphere.getAttribute('src') === g.backdrop) atmosphere.classList.add('shown');
      else atmosphere.src = g.backdrop;
    }, 250);
  }
}

// The wall of badges

// The achievements in the order of the view: the set's own, the locked ones that most
// players have first, or the unlocked ones from the latest
function wallList(d) {
  const all = d.achievements.map((a, i) => i);
  const a = i => d.achievements[i];
  if (state.view === 'locked') return all.filter(i => !a(i).earned).sort((x, y) => a(y).awarded - a(x).awarded);
  if (state.view === 'unlocked') return all.filter(i => a(i).earned).sort((x, y) => a(y).earned.localeCompare(a(x).earned));
  return all;
}

let wallGeometry = null;
function renderWall() {
  const g = library.games[state.game];
  const d = details.get(g.ra.id);
  const p = progressOf(g);
  A.header.textContent = g.name;
  setArt(A.headerArt, g.system);
  A.media(g.image, g.system);
  A.tiles.replaceChildren();
  A.info.textContent = T.views[state.view];
  A.overview(T.progress, fraction(p), g.supported
    ? T.progressLine(number(p.unlocked), number(p.total), p.points == null ? null : number(p.points), number(p.totalPoints))
    : T.unsupportedShort, !g.supported);
  if (!d) {
    message(A.message, T.loading);
    A.list = [];
    return showBadge();
  }
  A.list = wallList(d);
  message(A.message, A.list.length ? null : T.noneHere);
  const width = A.wall.clientWidth;
  const height = A.wall.clientHeight;
  const item = 0.075 * innerHeight;
  const columns = Math.max(1, Math.floor(width / item));
  const rows = Math.max(1, Math.floor(height / item));
  const cell = [width / columns, height / rows];
  const size = Math.min(...cell);
  wallGeometry = { columns, rows, cellHeight: cell[1] };
  A.list.forEach((index, n) => {
    const a = d.achievements[index];
    const tile = el('div', 'tile', A.tiles);
    tile.style.left = `${(n % columns) * cell[0] + (cell[0] - size) / 2}px`;
    tile.style.top = `${Math.floor(n / columns) * cell[1] + (cell[1] - size) / 2}px`;
    tile.style.width = tile.style.height = `${size}px`;
    el('div', 'glow', tile);
    el('img', '', tile).src = badgeUrl(a.badge, !a.earned);
  });
  selectBadge(state.badge);
}

function selectBadge(n) {
  if (A.list.length) {
    state.badge = clamp(n, 0, A.list.length - 1);
    const { columns, rows, cellHeight } = wallGeometry;
    // Scrolls only as far as needed to keep the selected row in view
    const row = Math.floor(state.badge / columns);
    A.first = clamp(A.first || 0, row - rows + 1, row);
    A.tiles.style.transform = `translateY(${-A.first * cellHeight}px)`;
    [...A.tiles.children].forEach((t, i) => t.classList.toggle('selected', i === state.badge));
  }
  showBadge();
}

function showBadge() {
  const d = details.get(library.games[state.game].ra.id);
  const a = d && A.list.length ? d.achievements[A.list[state.badge]] : null;
  A.title.textContent = a ? a.title : '';
  A.caption.textContent = a ? T.points(number(a.points)) : '';
  A.tag(a ? [T.types[a.type], a.earnedHardcore && T.hardcore] : []);
  A.description(a ? a.description : '');
  A.facts[0](T.unlockedOn, a && date(a.earnedHardcore || a.earned, true));
  A.facts[1](T.rarity, a && d.players ? `${number(Math.round(a.awarded / d.players * 1000) / 10)}%` : null);
  A.facts[2](T.retroPoints, a && number(a.retroPoints));
  A.facts[3](T.author, a && a.author);
}

// Screens and input

function show(screen) {
  state.screen = screen;
  document.getElementById('games').hidden = screen !== 'games';
  document.getElementById('achievements').hidden = screen !== 'achievements';
  renderHelp();
}

function openWall() {
  state.badge = 0;
  A.first = 0;
  show('achievements');
  renderWall();
}

function actGames(action) {
  if (action === 'b') return quitApp();
  if (action === 'lb' || action === 'rb') {
    play('quicksysselect');
    state.filter = cycle(FILTERS, state.filter, action === 'lb' ? -1 : 1);
    return renderLibrary(shelves.length ? state.game : undefined);
  }
  if (action === 'y') {
    play('select');
    state.sort = cycle(SORTS, state.sort, 1);
    return renderLibrary(shelves.length ? state.game : undefined);
  }
  if (!shelves.length) return;
  const pick = state.picks[shelves[state.shelf].key];
  // In the lists, up and down go through the names across the platforms, left and right
  // jump to the platform before or after
  const target = moveIn(shelves, state.mode !== 'grid', state.shelf, pick, action);
  if (target) {
    play('scroll');
    select(...target);
  } else if (action === 'a') {
    play('select');
    openWall();
  }
}

function actWall(action) {
  if (action === 'b') {
    play('back');
    return show('games');
  }
  if (action === 'y') {
    play('select');
    state.view = cycle(VIEWS, state.view, 1);
    state.badge = 0;
    A.first = 0;
    return renderWall();
  }
  // LB and RB step through the games of the shelf the game was chosen on
  const shelf = shelves[state.shelf];
  if ((action === 'lb' || action === 'rb') && shelf.games.length > 1) {
    play('scroll');
    const pick = (state.picks[shelf.key] + (action === 'lb' ? -1 : 1) + shelf.games.length) % shelf.games.length;
    select(state.shelf, pick);
    return openWall();
  }
  const columns = wallGeometry ? wallGeometry.columns : 1;
  const step = { left: -1, right: 1, up: -columns, down: columns }[action];
  if (!step || !A.list.length) return;
  const next = state.badge + step;
  const sameRow = Math.abs(step) !== 1 || Math.floor(next / columns) === Math.floor(state.badge / columns);
  if (next >= 0 && next < A.list.length && sameRow) {
    play('scroll');
    selectBadge(next);
  }
}

// The options menu, opened with Start as in ES-DE: the view of the library, its order
// and filter, which apply at once behind it, the RetroAchievements account and the way
// back to ES-DE. The view and the order are kept for the next time.
function menuRows() {
  return [
    { key: 'mode', label: T.menu.view, values: MODES, names: T.modes },
    { key: 'sort', label: T.menu.sort, values: SORTS, names: T.sorts },
    { key: 'filter', label: T.menu.filter, values: FILTERS, names: T.filters },
    { key: 'account', label: T.menu.account },
    { key: 'exit', label: T.menu.exit },
  ];
}

function buildMenu() {
  if (G.menu) G.menu.root.remove();
  G.menu = menuCard();
  if (G.account) G.account.root.remove();
  G.account = menuCard();
}

function renderMenu() {
  renderHelp();
  if (state.menu === null) return G.menu.hide();
  G.menu.show(T.menu.title, menuRows().map(row => row.values
    ? { label: row.label, value: row.names[state[row.key]] }
    : { label: row.label, separated: row.key === 'account' }), state.menu);
}

function savePrefs() {
  fetch('/api/prefs', { method: 'POST', body: JSON.stringify({ mode: state.mode, sort: state.sort }) }).catch(() => {});
}

function actMenu(action) {
  const rows = menuRows();
  const row = rows[state.menu];
  if (action === 'b' || action === 'start') {
    play('back');
    state.menu = null;
    return renderMenu();
  }
  if (action === 'up' || action === 'down') {
    play('scroll');
    state.menu = (state.menu + (action === 'up' ? -1 : 1) + rows.length) % rows.length;
    return renderMenu();
  }
  if (row.key === 'exit') {
    if (action === 'a') quitApp();
    return;
  }
  if (row.key === 'account') {
    if (action !== 'a') return;
    play('select');
    state.menu = null;
    renderMenu();
    return openAccount();
  }
  if (action === 'left' || action === 'right' || action === 'a') {
    play('select');
    state[row.key] = cycle(row.values, state[row.key], action === 'left' ? -1 : 1);
    if (row.key !== 'filter') savePrefs();
    renderLibrary(shelves.length ? state.game : undefined);
    renderMenu();
  }
}

// Signing in: the username, offered from RetroArch when it is signed in there, and the
// Web API key, typed on the on-screen keyboard or a keyboard, then checked with the site
function openAccount() {
  state.account = { user: S.suggestedUser || '', key: '', error: '', busy: false, selected: S.suggestedUser ? 1 : 0 };
  renderAccount();
}

function accountRows() {
  const a = state.account;
  const C = T.account;
  return [
    { label: C.user, value: a.user || '—', plain: true, arrows: false },
    { label: C.key, value: a.key ? '•'.repeat(Math.min(16, a.key.length)) : S.hasKey ? C.saved : '—', plain: Boolean(a.key), arrows: false },
    { label: a.busy ? C.checking : C.connect, separated: true, disabled: !a.user || (!a.key && !S.hasKey) },
  ];
}

function renderAccount() {
  renderHelp();
  if (!state.account) return G.account.hide();
  G.account.show(T.account.title, accountRows(), state.account.selected,
    [T.account.text, state.account.error].filter(Boolean).join('\n'));
}

function actAccount(action) {
  const a = state.account;
  const rows = accountRows();
  if (a.busy) return;
  if (action === 'b') {
    play('back');
    state.account = null;
    return renderAccount();
  }
  if (action === 'up' || action === 'down') {
    play('scroll');
    a.selected = (a.selected + (action === 'up' ? -1 : 1) + rows.length) % rows.length;
    return renderAccount();
  }
  if (action !== 'a' || rows[a.selected].disabled) return;
  play('select');
  if (a.selected === 2) return signIn();
  const key = a.selected === 1;
  G.account.hide();
  keyboard.open({
    title: key ? T.account.key : T.account.user, value: key ? a.key : a.user, mask: false, labels: T.keyboard,
    done: value => {
      a[key ? 'key' : 'user'] = value.trim();
      a.error = '';
      // From the username on to the key, and from the key to signing in
      a.selected = Math.min(2, a.selected + 1);
      renderAccount();
    },
    cancel: renderAccount,
  });
}

async function signIn() {
  const a = state.account;
  a.busy = true;
  a.error = '';
  renderAccount();
  let result;
  try {
    result = await (await fetch('/api/account', { method: 'POST', body: JSON.stringify({ username: a.user, apiKey: a.key }) })).json();
  } catch {
    result = { ok: false, reason: 'offline' };
  }
  a.busy = false;
  if (!result.ok) {
    a.error = { user: T.account.wrongUser, key: T.account.wrongKey, missing: T.account.missing }[result.reason] || T.account.offline;
    return renderAccount();
  }
  Object.assign(S, { username: result.username, suggestedUser: result.username, hasKey: true, setupError: null });
  state.account = null;
  renderAccount();
  play('select');
  loadGames();
}

function act(action) {
  if (keyboard.isOpen()) return keyboard.act(action);
  if (state.account) return actAccount(action);
  // Not signed in yet, A opens the sign-in again
  if (S.setupError && state.menu === null) {
    if (action === 'a') {
      play('select');
      return openAccount();
    }
    if (action === 'b') return quitApp();
    if (action !== 'start') return;
  }
  if (state.menu !== null) return actMenu(action);
  if (action === 'start') {
    play('select');
    state.menu = 0;
    return renderMenu();
  }
  if (!library.games.length && action !== 'b') return;
  if (state.screen === 'games') actGames(action);
  else actWall(action);
}

// Start

async function start() {
  await openSession(STRINGS);
  const layout = () => {
    L = S.layouts[aspectRatio()];
    applySizes();
    buildGames();
    buildAchievements();
    buildMenu();
    applyColors('');
    renderMenu();
    showCorner();
  };
  // The covers view was called icons at first
  if (S.prefs.mode === 'icons') S.prefs.mode = 'covers';
  if (MODES.includes(S.prefs.mode)) state.mode = S.prefs.mode;
  if (SORTS.includes(S.prefs.sort)) state.sort = S.prefs.sort;
  layout();
  requestAnimationFrame(poll);
  addEventListener('resize', () => {
    layout();
    if (library.games.length) renderLibrary(state.game);
    if (state.screen === 'achievements') renderWall();
    if (state.account) renderAccount();
    if (keyboard.isOpen()) keyboard.render();
  });

  // Not signed in yet: the sign-in comes first
  if (S.setupError) {
    message(G.message, T.setup, T.setupText);
    return openAccount();
  }
  loadGames();
}

// The library, and the games' details in the background
async function loadGames() {
  message(G.message, T.loading);
  try {
    const res = await fetch('/api/games');
    const data = await res.json();
    if (!res.ok) throw new Error(data.error);
    library = data;
  } catch (err) {
    return message(G.message, T.offline, err.message);
  }
  // For testing: #mode=<m>&filter=<f>&sort=<s>&game=<n> picks a game, &wall=<view> opens
  // its wall, &menu=<row> opens the options menu
  const params = new URLSearchParams(location.hash.slice(1));
  if (MODES.includes(params.get('mode'))) state.mode = params.get('mode');
  if (FILTERS.includes(params.get('filter'))) state.filter = params.get('filter');
  if (SORTS.includes(params.get('sort'))) state.sort = params.get('sort');
  showCorner();
  renderLibrary(params.has('game') ? Number(params.get('game')) : undefined);
  if (VIEWS.includes(params.get('wall'))) {
    state.view = params.get('wall');
    openWall();
  }
  if (params.has('menu')) {
    state.menu = Number(params.get('menu'));
    renderMenu();
  }
  preload();
}

start();
