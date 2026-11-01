// The page: a library of the games that have achievements, on one shelf of box covers
// per platform (after a shelf of the games in progress), and for the chosen game its
// wall of badges. LB/RB filter the library by progress and Y sorts it; on the wall
// they change game and view. Header, help prompts, details column and media card sit
// where the theme's Grid layout puts them for the screen's aspect ratio, in fractions
// of the screen width and height as ES-DE does. Driven by a controller through the
// Gamepad API, or by the keyboard.

let S; // the session: colors, sizes, layouts, language and settings from ES-DE
let T; // the words in the language of ES-DE
let L; // the layouts for this aspect ratio
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
// In fractions of the screen height: the progress block at the top of the content,
// and the parts of a shelf
const OVERVIEW = 0.115;
const SHELF = { label: 0.062, cover: 0.17, bar: 0.02, gap: 0.045 };
// The platform name sits at the top of its label space, leaving room above the covers
const SHELF_NAME = 0.03;
// Room beside the shelves for the light around a selected cover, in screen widths
const SHELF_PAD = 0.03;

const vw = f => `${f * 100}vw`;
const vh = f => `${f * 100}vh`;
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const themeUrl = p => '/theme/' + p.replace(/^(\.\/)?(\.\.\/)?/, '');
const badgeUrl = (badge, locked) => `/ra/Badge/${badge}${locked ? '_lock' : ''}.png`;
const percent = f => `${Math.floor(f * 100)}%`;

function el(tag, cls, parent, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  if (parent) parent.appendChild(e);
  return e;
}

// Positions an element like ES-DE: pos and origin, then size, cropSize or maxSize
function place(e, p, { line = false, origin } = {}) {
  if (!p || !p.pos) {
    e.hidden = true;
    return e;
  }
  const size = p.size || p.cropSize || p.maxSize;
  const [ox, oy] = origin || p.origin || (p.cropSize || p.maxSize ? [0.5, 0.5] : [0, 0]);
  e.classList.add('el');
  e.style.left = vw(p.pos[0]);
  e.style.top = vh(p.pos[1]);
  if (size) {
    if (size[0]) e.style.width = vw(size[0]);
    if (size[1]) e.style.height = vh(size[1]);
    if (line && size[1]) e.style.lineHeight = vh(size[1]);
  }
  e.style.transform = `translate(${-ox * 100}%, ${-oy * 100}%)`;
  if (p.cornerRadius) e.style.borderRadius = vw(p.cornerRadius);
  return e;
}

function setVars(vars) {
  for (const [name, value] of Object.entries(vars)) document.documentElement.style.setProperty(`--${name}`, value);
}

const systemInfo = system => S.systems[system] || S.systems._default || { color: 'C9AB79', cover: 0.75 };

// The color scheme of ES-DE; the atmosphere schemes take the system's color
function applyColors(system) {
  const c = S.colors;
  const systemColor = systemInfo(system).color || 'C9AB79';
  const color = v => '#' + v.replace('${systemColor}', systemColor);
  setVars({
    bg: color(c.bgColor), surface: color(c.surfaceColor), title: color(c.titleColor), text: color(c.textColor),
    muted: color(c.mutedColor), list: color(c.listColor), faint: color(c.faintColor), accent: color(c.accentColor),
    placeholder: color(c.placeholderColor), ambient: color(c.ambientColor), glow: color(c.selectionGlowColor),
    'ambient-image': `url(${themeUrl(c.ambientImage)})`, 'glow-image': `url(${themeUrl(c.ambientTileImage)})`,
    dim: c.gridDimOpacity, 'atmosphere-opacity': c.atmosphereOpacity,
  });
  document.getElementById('atmosphere').style.filter = `saturate(${c.atmosphereSaturation})`;
}

function applySizes() {
  const f = S.fontSizes;
  // The footer of a 4:3 screen has no room for the larger prompts of some font sizes
  const help = Number(aspectRatio() === '4:3' ? f.helpSizeNarrow : f.helpSize) * 0.62;
  setVars({
    'caps-size': vh(f.capsSize), 'label-size': vh(f.labelSize), 'tag-size': vh(f.tagSize), 'value-size': vh(f.valueSize),
    'desc-size': vh(f.descSize), 'game-title-size': vh(f.gameTitleSize), 'tile-text': vh(f.gridTextSize),
    'help-size': vh(help), 'help-icon': vh(help * 1.25), 'help-spacing': vw(0.017), 'help-icon-spacing': vw(0.0055),
    'tile-radius': vw(0.0025), 'badge-gap': vw(0.0055), 'tab-gap': vw(0.018), 'list-size': vh(f.listSize),
    'list-margin': vw(L.games.gamelistTextlist.horizontalMargin), 'icon-gap': vw(0.008),
    'selector-width': vw(L.games.gamelistTextlist.selectorWidth), 'selector-height': vh(L.games.gamelistTextlist.selectorHeight),
  });
}

function aspectRatio() {
  const set = { '21:9': '21:9', '16:9': '16:9', '16:10': '16:9', '4:3': '4:3' }[S.aspectRatio];
  if (set) return set;
  const r = innerWidth / innerHeight;
  return r >= 2 ? '21:9' : r >= 1.5 ? '16:9' : '4:3';
}

// The content area left of the details column: from the page margin to the end of
// the theme's grid, between the header and the footer
function contentBox() {
  const grid = L.achievements.gamelistGrid;
  const list = L.games.gamelistTextlist;
  const left = L.games.help.pos[0];
  return { left, right: grid.pos[0] + grid.size[0] - (left - grid.pos[0]), top: list.pos[1], bottom: list.pos[1] + list.size[1] };
}

// System drawings, with the theme's fallback for systems that have none
const artChecked = new Map();
function setArt(e, system) {
  const own = themeUrl(`systems/controllers/${system}.svg`);
  const apply = ok => e.style.setProperty('--src', `url(${ok ? own : themeUrl('systems/controllers/custom-collections.svg')})`);
  if (artChecked.has(system)) return apply(artChecked.get(system));
  const img = new Image();
  img.onload = () => { artChecked.set(system, true); apply(true); };
  img.onerror = () => { artChecked.set(system, false); apply(false); };
  img.src = own;
}

// Labels above values, as the facts of the theme
function fact(parent, layout, labelName, valueName) {
  const label = place(el('div', 'line label', parent), layout[labelName], { line: true });
  const value = place(el('div', 'line value', parent), layout[valueName], { line: true });
  return (name, text) => {
    label.textContent = name;
    value.textContent = text ?? '—';
  };
}

// A hairline track filled with the accent up to a fraction
function bar(parent, p) {
  const track = el('div', 'bar', parent);
  if (p) place(track, p);
  const fill = el('div', 'fill', track);
  const set = fraction => { fill.style.width = `${clamp(fraction, 0, 1) * 100}%`; };
  set.track = track;
  return set;
}

// A label with a percentage at the right end, a bar beneath and a line of figures
function progressBlock(parent, x, y, width) {
  const label = place(el('div', 'line label', parent), { pos: [x, y], size: [width * 0.7, 0.03] }, { line: true, origin: [0, 0.5] });
  const value = place(el('div', 'line percent', parent), { pos: [x + width, y], size: [width * 0.3, 0.04] }, { line: true, origin: [1, 0.5] });
  const fill = bar(parent, { pos: [x, y + 0.026], size: [width, 0.004] });
  const sub = place(el('div', 'line sub', parent), { pos: [x, y + 0.06], size: [width, 0.035] }, { line: true, origin: [0, 0.5] });
  return (name, fraction, figures, warning) => {
    label.textContent = name;
    value.textContent = fraction == null ? '' : percent(fraction);
    fill(fraction || 0);
    sub.textContent = figures || '';
    sub.classList.toggle('warning', Boolean(warning));
  };
}

// An image in a rounded card with the ambient light behind and the system drawing as
// placeholder
function mediaCard(parent, layout, imageName) {
  place(el('div', 'ambient', parent), layout.mediaAmbient);
  place(el('div', 'matte', parent), layout.mediaMatte);
  const placeholder = place(el('div', 'art', parent), layout.mediaPlaceholder);
  placeholder.style.setProperty('--tint', 'var(--placeholder)');
  const box = place(el('div', 'matte', parent), layout[imageName]);
  box.style.background = 'none';
  const img = el('img', 'shot', box);
  img.onload = () => img.classList.add('shown');
  return (url, system) => {
    setArt(placeholder, system);
    if (img.getAttribute('src') === url) return;
    img.classList.remove('shown');
    if (url) img.src = url;
    else img.removeAttribute('src');
  };
}

// Text that scrolls up slowly when it doesn't fit, as the theme's descriptions do
function scroller(box) {
  const inner = el('div', 'scroll', box);
  let timer = null;
  return content => {
    clearTimeout(timer);
    inner.style.transition = 'none';
    inner.style.transform = 'none';
    inner.replaceChildren(document.createTextNode(content || ''));
    const overflow = inner.scrollHeight - box.clientHeight;
    if (overflow <= 0) return;
    const lineHeight = parseFloat(getComputedStyle(box).fontSize) * 1.55;
    const run = () => {
      const seconds = overflow / lineHeight * 2.2;
      inner.style.transition = `transform ${seconds}s linear`;
      inner.style.transform = `translateY(${-overflow}px)`;
      timer = setTimeout(() => {
        inner.style.transition = 'none';
        inner.style.transform = 'none';
        timer = setTimeout(run, 5000);
      }, seconds * 1000 + 8000);
    };
    timer = setTimeout(run, 5000);
  };
}

// At the right margin of the header line. ES-DE puts the clock there, or beside the system
// status when that moves up, which the page does not show
function corner(parent, layout) {
  return place(el('div', 'line corner', parent),
    { pos: [layout.systemStatus.pos[0], layout.clock.pos[1]], size: [0.3, S.fontSizes.capsSize * 2] },
    { line: true, origin: [1, 0.5] });
}

// The tags beneath the caption, where the theme shows the file tags; the tag font draws
// each bracketed word as an outlined tag
function tag(parent, layout) {
  const e = place(el('div', 'line tags', parent), layout.fileTags, { line: true });
  return words => { e.textContent = words.filter(Boolean).map(w => `(${w})`).join(' '); };
}

function header(root, layout, text) {
  const art = place(el('div', 'art', root), layout.headerArt);
  const title = place(el('div', 'line caps header', root, text), layout.header, { line: true });
  return { art, title };
}

function buildGames() {
  const root = document.getElementById('games');
  root.replaceChildren();
  const l = L.achievements;
  const b = contentBox();
  const { art } = header(root, l, 'RetroAchievements');
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
  const type = S.controller.toLowerCase();
  const family = type.startsWith('ps') ? 'PS' : type.startsWith('switch') ? 'switch' : type === 'snes' ? 'SNES' : 'XBOX';
  const menu = [`button_start_${family}`, T.help.menu];
  const entries = state.menu !== null
    ? [['dpad_updown', T.help.choose], ['dpad_leftright', T.help.change], [`button_a_${family}`, T.help.select],
      [`button_b_${family}`, T.help.close]]
    : state.screen === 'games'
      ? [['dpad_all', T.help.choose], ['button_lr', T.help.filter], [`button_y_${family}`, T.help.sort],
        [`button_a_${family}`, T.help.select], [`button_b_${family}`, T.help.back], menu]
      : [['dpad_all', T.help.choose], ['button_lr', T.help.game], [`button_y_${family}`, T.help.view],
        [`button_b_${family}`, T.help.back], menu];
  const help = document.getElementById('help');
  place(help, { pos: L.games.help.pos }, { origin: [0, 0.5] });
  help.replaceChildren(...entries.map(([icon, label]) => {
    const entry = el('div', 'entry');
    el('div', 'art', entry).style.setProperty('--src', `url(${themeUrl(`core/help/${icon}.svg`)})`);
    el('span', '', entry, label);
    return entry;
  }));
}

const locale = () => S.language.replace('_', '-');
const number = n => new Intl.NumberFormat(locale()).format(n);
const parseDate = s => s ? new Date(/Z|[+-]\d\d:?\d\d$/.test(s) ? s : s.replace(' ', 'T') + 'Z') : null;
function date(s, withTime) {
  const d = parseDate(s);
  if (!d) return null;
  const options = { day: 'numeric', month: 'short', year: 'numeric', ...(withTime && { hour: '2-digit', minute: '2-digit' }) };
  return new Intl.DateTimeFormat(locale(), options).format(d);
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

function message(target, title, text) {
  target.hidden = !title;
  if (!title) return;
  target.replaceChildren(el('span', 'caps', null, title), document.createTextNode(text || ''));
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
  if (state.mode === 'grid') drawShelves();
  else drawList();
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

function groupLabel(parent, shelf) {
  const label = el('div', 'shelf-label', parent);
  if (shelf.system) setArt(el('div', 'art', label), shelf.system);
  el('span', '', label, shelf.title);
  el('span', 'count', label, number(shelf.games.length));
  return label;
}

function drawShelves() {
  G.track.replaceChildren();
  const H = innerHeight;
  const pad = SHELF_PAD * innerWidth;
  const coverHeight = SHELF.cover * H;
  const shelfHeight = (SHELF.label + SHELF.cover + SHELF.bar + SHELF.gap) * H;
  shelves.forEach((shelf, s) => {
    const e = el('div', 'shelf', G.track);
    e.style.top = `${s * shelfHeight}px`;
    e.style.height = `${shelfHeight}px`;
    const label = groupLabel(e, shelf);
    label.style.left = `${pad}px`;
    label.style.height = `${SHELF_NAME * H}px`;
    const row = el('div', 'row', e);
    row.style.left = `${pad}px`;
    row.style.top = `${SHELF.label * H}px`;
    shelf.x = [];
    shelf.w = [];
    let x = 0;
    for (const i of shelf.games) {
      const g = library.games[i];
      const width = coverHeight * clamp(systemInfo(g.system).cover || 0.75, 0.6, 1.5);
      const tile = el('div', 'cover', row);
      tile.style.left = `${x}px`;
      tile.style.width = `${width}px`;
      tile.style.height = `${coverHeight}px`;
      el('div', 'glow', tile);
      const pic = el('div', 'pic', tile);
      fillCover(pic, g);
      coverPics.set(i, [...(coverPics.get(i) || []), pic]);
      const progress = bar(tile);
      progress.track.style.top = `${coverHeight + 0.01 * H}px`;
      progress.track.style.height = `${Math.max(1, Math.round(0.0025 * H))}px`;
      progress(fraction(progressOf(g)));
      shelf.x.push(x);
      shelf.w.push(width);
      x += width + coverHeight * 0.16;
    }
    shelf.row = row;
    shelf.el = e;
  });
  G.track.style.transform = 'none';
  G.scroll = 0;
}

// Names one under the other, as in the theme's game lists; with covers, each name has
// the game's whole box cover beside it and its progress beneath
function drawList() {
  G.listTrack.replaceChildren();
  const H = innerHeight;
  const covers = state.mode === 'covers';
  const rowHeight = covers ? 0.09 * H : S.fontSizes.listSize * S.fontSizes.listSpacing * H;
  const headHeight = 0.055 * H;
  const list = L.games.gamelistTextlist;
  G.selector = el('div', 'selector', G.listTrack);
  G.selector.style.width = vw(list.selectorWidth);
  G.selector.style.height = covers ? `${rowHeight * 0.5}px` : vh(list.selectorHeight);
  G.selectorOffset = covers ? rowHeight * 0.25 : list.selectorVerticalOffset * H;
  let y = 0;
  shelves.forEach((shelf, s) => {
    const label = groupLabel(G.listTrack, shelf);
    label.style.top = `${y}px`;
    label.style.height = `${headHeight * 0.6}px`;
    label.style.left = vw(list.horizontalMargin);
    shelf.label = label;
    shelf.rows = [];
    y += headHeight;
    for (const i of shelf.games) {
      const g = library.games[i];
      const row = el('div', `list-row${covers ? ' with-cover' : ''}`, G.listTrack);
      row.style.top = `${y}px`;
      row.style.height = `${rowHeight}px`;
      if (covers) {
        // The whole cover, in a square so that the names line up whatever its shape
        const pic = el('div', 'pic', row);
        pic.dataset.icon = '1';
        fillCover(pic, g);
        coverPics.set(i, [...(coverPics.get(i) || []), pic]);
        const text = el('div', 'text', row);
        el('div', 'name', text, g.name);
        const meta = el('div', 'meta', text);
        const p = progressOf(g);
        bar(meta)(fraction(p));
        el('span', '', meta, `${number(p.unlocked)} / ${number(p.total)}`);
      } else {
        row.style.lineHeight = `${rowHeight}px`;
        row.textContent = g.name;
      }
      shelf.rows.push({ el: row, top: y, height: rowHeight });
      y += rowHeight;
    }
    y += 0.015 * H;
  });
  G.listHeight = y;
}

function select(s, item) {
  state.shelf = clamp(s, 0, shelves.length - 1);
  const shelf = shelves[state.shelf];
  const pick = clamp(item ?? state.picks[shelf.key] ?? 0, 0, shelf.games.length - 1);
  state.picks[shelf.key] = pick;
  state.game = shelf.games[pick];
  if (state.mode === 'grid') highlightShelves(shelf, pick);
  else highlightList(shelf, pick);
  showGame();
  loadDetails(library.games[state.game]);
}

// The selected row stays in the middle of the list, as in the theme's game lists
function highlightList(shelf, pick) {
  shelves.forEach(sh => {
    sh.label.classList.toggle('active', sh === shelf);
    sh.rows.forEach((row, n) => row.el.classList.toggle('selected', sh === shelf && n === pick));
  });
  const row = shelf.rows[pick];
  G.selector.style.top = `${row.top + G.selectorOffset}px`;
  const height = G.listBox.clientHeight;
  const scroll = clamp(row.top + row.height / 2 - height / 2, 0, Math.max(0, G.listHeight - height));
  G.listTrack.style.transform = `translateY(${-scroll}px)`;
}

function highlightShelves(shelf, pick) {
  shelves.forEach((sh, n) => {
    sh.el.classList.toggle('active', n === state.shelf);
    const chosen = state.picks[sh.key] ?? 0;
    [...sh.row.children].forEach((tile, t) => tile.classList.toggle('selected', t === chosen));
  });
  // Scroll the shelf sideways, and the shelves up or down, only as far as needed
  const visible = G.shelves.clientWidth - 2 * SHELF_PAD * innerWidth;
  const peek = SHELF.cover * innerHeight * 0.3;
  shelf.offset = clamp(shelf.offset || 0, shelf.x[pick] + shelf.w[pick] + peek - visible, Math.max(0, shelf.x[pick] - peek));
  shelf.row.style.transform = `translateX(${-shelf.offset}px)`;
  const height = (SHELF.label + SHELF.cover + SHELF.bar + SHELF.gap) * innerHeight;
  // The gap after the last visible shelf may fall outside
  const bottom = (state.shelf + 1) * height - SHELF.gap * innerHeight;
  G.scroll = clamp(G.scroll || 0, bottom - G.shelves.clientHeight, state.shelf * height);
  G.track.style.transform = `translateY(${-G.scroll}px)`;
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

const sounds = {};
let audio = null;
function play(name) {
  if (!S.sounds) return;
  if (!audio) audio = new AudioContext();
  const start = buffer => {
    const source = audio.createBufferSource();
    const gain = audio.createGain();
    gain.gain.value = S.volume;
    source.buffer = buffer;
    source.connect(gain).connect(audio.destination);
    source.start();
  };
  if (!sounds[name]) {
    sounds[name] = fetch(themeUrl(`core/sounds/${name}.wav`)).then(r => r.arrayBuffer())
      .then(data => audio.decodeAudioData(data)).catch(() => null);
  }
  sounds[name].then(buffer => buffer && start(buffer));
}

function quit() {
  play('back');
  fetch('/api/quit', { method: 'POST' }).catch(() => {});
  setTimeout(() => window.close(), 250);
}

const cycle = (list, value, step) => list[(list.indexOf(value) + step + list.length) % list.length];

function actGames(action) {
  if (action === 'b') return quit();
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
  if (state.mode !== 'grid' && ['up', 'down', 'left', 'right'].includes(action)) {
    let [s, n] = [state.shelf, pick];
    const last = shelves.length - 1;
    if (action === 'down') [s, n] = n + 1 < shelves[s].games.length ? [s, n + 1] : [s + 1, 0];
    if (action === 'up') [s, n] = n > 0 ? [s, n - 1] : [s - 1, s > 0 ? shelves[s - 1].games.length - 1 : 0];
    if (action === 'left') [s, n] = n > 0 ? [s, 0] : [s - 1, 0];
    if (action === 'right') [s, n] = [s + 1, 0];
    if (s < 0 || s > last) return;
    play('scroll');
    return select(s, n);
  }
  const moves = {
    left: [state.shelf, pick - 1], right: [state.shelf, pick + 1], up: [state.shelf - 1], down: [state.shelf + 1],
    lt: [0, 0], rt: [shelves.length - 1],
  };
  if (action in moves) {
    const [s, item] = moves[action];
    if (s < 0 || s >= shelves.length || (item !== undefined && (item < 0 || item >= shelves[s].games.length))) return;
    if (s === state.shelf && item === pick) return;
    play('scroll');
    select(s, item);
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
// and filter, which apply at once behind it, and the way back to ES-DE. The view and
// the order are kept for the next time.
function menuRows() {
  return [
    { key: 'mode', label: T.menu.view, values: MODES, names: T.modes },
    { key: 'sort', label: T.menu.sort, values: SORTS, names: T.sorts },
    { key: 'filter', label: T.menu.filter, values: FILTERS, names: T.filters },
    { key: 'exit', label: T.menu.exit },
  ];
}

function buildMenu() {
  const old = document.getElementById('menu');
  if (old) old.remove();
  const root = el('div', '', document.body);
  root.id = 'menu';
  root.hidden = true;
  el('div', 'menu-veil', root);
  el('div', 'menu-glow', root);
  const panel = el('div', 'menu', root);
  const title = el('div', 'menu-title', panel);
  el('span', 'menu-rule', title);
  el('span', '', title, T.menu.title);
  G.menuRows = el('div', '', panel);
  G.menu = root;
}

function renderMenu() {
  G.menu.hidden = state.menu === null;
  renderHelp();
  if (state.menu === null) return;
  G.menuRows.replaceChildren(...menuRows().map((row, n) => {
    const e = el('div', `menu-row${n === state.menu ? ' selected' : ''}${row.values ? '' : ' action'}`);
    el('span', 'menu-label', e, row.label);
    if (row.values) {
      const value = el('span', 'menu-value', e);
      el('span', 'arrow', value, '‹');
      el('span', '', value, row.names[state[row.key]]);
      el('span', 'arrow', value, '›');
    }
    return e;
  }));
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
    if (action === 'a') quit();
    return;
  }
  if (action === 'left' || action === 'right' || action === 'a') {
    play('select');
    state[row.key] = cycle(row.values, state[row.key], action === 'left' ? -1 : 1);
    if (row.key !== 'filter') savePrefs();
    renderLibrary(shelves.length ? state.game : undefined);
    renderMenu();
  }
}

function act(action) {
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

// As in ES-DE: Enter is A, Backspace is B and Escape is Start
const KEYS = {
  ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right', Enter: 'a', ' ': 'a',
  Backspace: 'b', Escape: 'start', PageUp: 'lb', PageDown: 'rb', Home: 'lt', End: 'rt', y: 'y', Y: 'y',
};
addEventListener('keydown', e => {
  if (!KEYS[e.key]) return;
  e.preventDefault();
  act(KEYS[e.key]);
});

// Controllers in the standard layout: buttons A, B, Y, LB, RB, LT, RT, Start and the
// d-pad, or the left stick. Held directions repeat as in ES-DE.
const PAD = { 0: 'a', 1: 'b', 3: 'y', 4: 'lb', 5: 'rb', 6: 'lt', 7: 'rt', 9: 'start', 12: 'up', 13: 'down', 14: 'left', 15: 'right' };
const REPEATS = new Set(['up', 'down', 'left', 'right']);
const held = new Map();
function poll(now) {
  const pressed = new Set();
  for (const pad of navigator.getGamepads()) {
    if (!pad) continue;
    for (const [index, action] of Object.entries(PAD)) if (pad.buttons[index] && pad.buttons[index].pressed) pressed.add(action);
    const [x = 0, y = 0] = pad.axes;
    if (y < -0.5) pressed.add('up');
    if (y > 0.5) pressed.add('down');
    if (x < -0.5) pressed.add('left');
    if (x > 0.5) pressed.add('right');
  }
  for (const action of held.keys()) if (!pressed.has(action)) held.delete(action);
  for (const action of pressed) {
    const since = held.get(action);
    if (since === undefined) {
      held.set(action, now);
      act(action);
    } else if (REPEATS.has(action) && now - since > 500) {
      held.set(action, now - 500 + 110);
      act(action);
    }
  }
  requestAnimationFrame(poll);
}

// Start

async function start() {
  S = await (await fetch('/api/session')).json();
  T = STRINGS[S.language.slice(0, 2)] || STRINGS.en;
  document.documentElement.lang = S.language.slice(0, 2);
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

  if (S.setupError) return message(G.message, T.setup, T.setupText);
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
  addEventListener('resize', () => {
    layout();
    renderLibrary(state.game);
    if (state.screen === 'achievements') renderWall();
  });
}

start();
