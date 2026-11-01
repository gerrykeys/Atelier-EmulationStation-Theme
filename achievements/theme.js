// Reads the look of Atelier from the theme's own files, so the app follows the theme
// as it changes: the colors of the color scheme chosen in ES-DE, the font sizes, the
// language, and the positions of the Index and Grid layouts for every aspect ratio.

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(ROOT, file), 'utf8');

// A small XML reader for the theme files: elements with their attributes, children and
// text, comments left out
function parse(xml) {
  const root = { tag: '', attrs: {}, children: [], text: '' };
  const stack = [root];
  const re = /<!--[\s\S]*?-->|<(\/?)([\w:-]+)((?:\s+[\w:-]+="[^"]*")*)\s*(\/?)>|([^<]+)/g;
  for (const m of xml.replace(/^<\?xml[^>]*>/, '').matchAll(re)) {
    const top = stack[stack.length - 1];
    if (m[5] !== undefined) top.text += m[5];
    else if (m[2] && m[1]) stack.pop();
    else if (m[2]) {
      const attrs = {};
      for (const a of m[3].matchAll(/([\w:-]+)="([^"]*)"/g)) attrs[a[1]] = a[2];
      const node = { tag: m[2], attrs, children: [], text: '' };
      top.children.push(node);
      if (!m[4]) stack.push(node);
    }
  }
  return root;
}

const list = s => (s || '').split(',').map(x => x.trim()).filter(Boolean);
const child = (node, tag) => node.children.find(c => c.tag === tag);
function variables(node) {
  const vars = {};
  const block = node && child(node, 'variables');
  if (block) for (const v of block.children) vars[v.tag] = v.text.trim();
  return vars;
}

const theme = parse(read('theme.xml')).children[0];

function fontSizes(name) {
  const blocks = theme.children.filter(c => c.tag === 'fontSize');
  return variables(blocks.find(c => c.attrs.name === name) || blocks.find(c => c.attrs.name === 'medium'));
}

// The variables of a color scheme, with ${systemColor} left in place: the page sets it
// per game from systems()
function colors(name) {
  const schemes = parse(read('layout/colors.xml')).children[0].children.filter(c => c.tag === 'colorScheme');
  const scheme = schemes.find(c => c.attrs.name === name) || schemes[0];
  return { name: scheme.attrs.name, ...variables(scheme) };
}

// The labels of the theme in a language, falling back to English
function labels(language) {
  const doc = parse(read('layout/languages.xml')).children[0];
  const own = doc.children.find(c => c.tag === 'language' && list(c.attrs.name).includes(language));
  return { ...variables(doc), ...variables(own) };
}

// Each system's color and the shape of its box covers as width/height, such as 0.75
function systems() {
  const out = {};
  const dir = path.join(ROOT, 'systems', 'metadata');
  for (const file of fs.readdirSync(dir)) {
    const xml = fs.readFileSync(path.join(dir, file), 'utf8');
    const color = xml.match(/<systemColor>(\w+)<\/systemColor>/);
    const cover = xml.match(/<systemCoverSize>(\d+)-(\d+)<\/systemCoverSize>/);
    out[file.replace(/\.xml$/, '')] = { color: color ? color[1] : null, cover: cover ? cover[1] / cover[2] : 0.75 };
  }
  return out;
}

// Element properties as numbers or pairs of numbers, with font size variables resolved
function props(node, vars) {
  const out = {};
  for (const p of node.children) {
    const text = p.text.trim().replace(/\$\{(\w+)\}/g, (all, v) => vars[v] ?? all);
    const nums = text.split(/\s+/).map(Number);
    out[p.tag] = nums.every(n => !Number.isNaN(n)) ? (nums.length === 1 ? nums[0] : nums) : text;
  }
  return out;
}

// The gamelist elements of one aspect ratio file for the given variants, later ones
// overriding earlier ones, as ES-DE applies them
function elements(file, variantNames, vars) {
  const out = {};
  const doc = parse(read(file)).children[0];
  const blocks = doc.tag === 'theme' && !doc.children.some(c => c.tag === 'variant') ? [doc]
    : doc.children.filter(c => c.tag === 'variant' && list(c.attrs.name).some(n => variantNames.includes(n)));
  for (const block of blocks) {
    for (const view of block.children.filter(c => c.tag === 'view' && list(c.attrs.name).includes('gamelist'))) {
      for (const el of view.children) {
        for (const name of list(el.attrs.name)) out[name] = { ...out[name], ...props(el, vars) };
      }
    }
  }
  return out;
}

const RATIOS = { '21:9': ['ar-21-9', '21-9'], '16:9': ['ar-16-9', '16-9'], '4:3': ['ar-4-3', '4-3'] };

// The Index layout for the game list and the Grid layout, with its square covers, for
// the wall of badges
function layouts(fontSizeName) {
  const vars = fontSizes(fontSizeName);
  const out = {};
  for (const [ratio, [file, grid]] of Object.entries(RATIOS)) {
    const at = `layout/${file}.xml`;
    out[ratio] = {
      games: elements(at, ['all', 'index', 'indexStill'], vars),
      achievements: { ...elements(at, ['all', 'grid'], vars), ...elements(`layout/grid/${grid}-square.xml`, [], vars) },
    };
  }
  return out;
}

module.exports = { ROOT, colors, fontSizes, labels, layouts, systems };
