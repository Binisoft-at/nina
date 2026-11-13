#!/usr/bin/env node
// Renders the Nina icon SVGs to PNG with headless Chromium (Playwright). Called by export.sh.
//
//   node render.js <in.svg> <out.png> <size> [<in.svg> <out.png> <size> ...]
//       Renders each SVG at size x size px. Transparency is kept (iOS/watch flattening is
//       done by export.sh).
//   node render.js --sheet <out.png> <dir>
//       Builds the contact sheet from the PNGs export.sh leaves in <dir>.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

function svgPage(svg, size) {
  return `<!doctype html><html><head><style>
    html, body { margin: 0; padding: 0; background: transparent; }
    svg { display: block; width: ${size}px; height: ${size}px; }
  </style></head><body>${svg}</body></html>`;
}

async function renderSvgs(page, args) {
  if (args.length === 0 || args.length % 3 !== 0) {
    throw new Error('usage: node render.js <in.svg> <out.png> <size> [...]  |  --sheet <out.png> <dir>');
  }
  for (let i = 0; i < args.length; i += 3) {
    const [input, output, sizeArg] = args.slice(i, i + 3);
    const size = parseInt(sizeArg, 10);
    if (!(size > 0)) throw new Error(`bad size "${sizeArg}" for ${input}`);
    const svg = fs.readFileSync(input, 'utf8');
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(svgPage(svg, size));
    await page.screenshot({ path: output, omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } });
    console.log(`rendered ${path.basename(input)} -> ${path.basename(output)} (${size} px)`);
  }
}

// Continuous-corner rounded square (the iOS / macOS icon shape), as an SVG path in px.
function squircle(size, radiusFraction = 0.2237, smoothing = 0.6) {
  const r = size * radiusFraction;
  const p = (1 + smoothing) * r;
  const arc = 90 * (1 - smoothing);
  const rad = (d) => (d * Math.PI) / 180;
  const arcLen = Math.sin(rad(arc / 2)) * r * Math.SQRT2;
  const alpha = (90 - arc) / 2;
  const c = r * Math.tan(rad(alpha / 2)) * Math.cos(rad(45 * smoothing));
  const d = c * Math.tan(rad(45 * smoothing));
  const b = (p - arcLen - c - d) / 3;
  const a = 2 * b;
  const n = (v) => +v.toFixed(3);
  const s = size;
  return [
    `M ${n(s - p)} 0`,
    `c ${n(a)} 0 ${n(a + b)} 0 ${n(a + b + c)} ${n(d)}`, `a ${n(r)} ${n(r)} 0 0 1 ${n(arcLen)} ${n(arcLen)}`,
    `c ${n(d)} ${n(c)} ${n(d)} ${n(b + c)} ${n(d)} ${n(a + b + c)}`,
    `L ${s} ${n(s - p)}`,
    `c 0 ${n(a)} 0 ${n(a + b)} ${n(-d)} ${n(a + b + c)}`, `a ${n(r)} ${n(r)} 0 0 1 ${n(-arcLen)} ${n(arcLen)}`,
    `c ${n(-c)} ${n(d)} ${n(-(b + c))} ${n(d)} ${n(-(a + b + c))} ${n(d)}`,
    `L ${n(p)} ${s}`,
    `c ${n(-a)} 0 ${n(-(a + b))} 0 ${n(-(a + b + c))} ${n(-d)}`, `a ${n(r)} ${n(r)} 0 0 1 ${n(-arcLen)} ${n(-arcLen)}`,
    `c ${n(-d)} ${n(-c)} ${n(-d)} ${n(-(b + c))} ${n(-d)} ${n(-(a + b + c))}`,
    `L 0 ${n(p)}`,
    `c 0 ${n(-a)} 0 ${n(-(a + b))} ${n(d)} ${n(-(a + b + c))}`, `a ${n(r)} ${n(r)} 0 0 1 ${n(arcLen)} ${n(-arcLen)}`,
    `c ${n(c)} ${n(-d)} ${n(b + c)} ${n(-d)} ${n(a + b + c)} ${n(-d)} Z`,
  ].join(' ');
}

// The accent colour (light and dark) from the app's AccentColor asset, as hex.
function accentColors() {
  const file = path.join(__dirname, '..', 'App', 'Resources', 'Assets.xcassets', 'AccentColor.colorset', 'Contents.json');
  const json = JSON.parse(fs.readFileSync(file, 'utf8'));
  const hex = (entry) => '#' + ['red', 'green', 'blue']
    .map((k) => Math.round(parseFloat(entry.color.components[k]) * 255).toString(16).padStart(2, '0'))
    .join('').toUpperCase();
  const isDark = (entry) => (entry.appearances || []).some((a) => a.value === 'dark');
  return { light: hex(json.colors.find((e) => !isDark(e))), dark: hex(json.colors.find(isDark)) };
}

// WCAG 2 contrast ratio between two hex colours.
function contrast(hexA, hexB) {
  const lum = (h) => {
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255)
      .map((c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const [hi, lo] = [lum(hexA), lum(hexB)].sort((x, y) => y - x);
  return ((hi + 0.05) / (lo + 0.05)).toFixed(2);
}

function sheetPage(dir) {
  const accent = accentColors();
  const img = (name) => {
    const file = path.join(dir, name);
    if (!fs.existsSync(file)) throw new Error(`contact sheet: missing ${file}`);
    return `data:image/png;base64,${fs.readFileSync(file).toString('base64')}`;
  };
  // An icon as the system shows it: iOS shape, watch circle, or the Mac file as is.
  const icon = (name, size, shape) => {
    const clip = shape === 'ios' ? `clip-path: path('${squircle(size)}');`
      : shape === 'watch' ? 'clip-path: circle(50%);' : '';
    return `<img src="${img(name)}" width="${size}" height="${size}" style="display:block;${clip}">`;
  };
  const tile = (label, name, shape) =>
    `<figure>${icon(name, 232, shape)}<figcaption>${label}</figcaption></figure>`;
  const pair = (label, big, small, shape, bigSize = 60, smallSize = 29) => `
    <div class="pair"><div class="icons">${icon(big, bigSize, shape)}${icon(small, smallSize, shape)}</div>
    <span>${label}</span></div>`;
  const strip = (cls) => `<div class="strip ${cls}">
      ${pair('Light 60 / 29', 'light-60.png', 'light-29.png', 'ios')}
      ${pair('Dark 60 / 29', 'dark-60.png', 'dark-29.png', 'ios')}
      ${pair('Tinted 60 / 29', 'tinted-60.png', 'tinted-29.png', 'ios')}
      ${pair('Mac 32 / 16', 'mac-32.png', 'mac-16.png', 'mac', 32, 16)}
      ${pair('Watch 60 / 29', 'light-60.png', 'light-29.png', 'watch')}
    </div>`;
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    * { box-sizing: border-box; }
    html, body { margin: 0; }
    body { width: 1600px; padding: 48px 64px 56px; background: #F2F2F7; color: #1C1C1E;
           font-family: Inter, -apple-system, 'Helvetica Neue', sans-serif; }
    h1 { font-size: 28px; font-weight: 600; margin: 0; letter-spacing: -0.01em; }
    h2 { font-size: 15px; font-weight: 600; margin: 40px 0 14px; color: #6E6E73;
         text-transform: uppercase; letter-spacing: 0.06em; }
    p.sub { margin: 6px 0 0; font-size: 16px; color: #6E6E73; }
    .row { display: flex; gap: 46px; align-items: flex-start; }
    figure { margin: 0; width: 232px; }
    figcaption { margin-top: 12px; font-size: 15px; font-weight: 500; color: #3A3A3C; text-align: center; }
    .strips { display: flex; gap: 24px; }
    .strip { flex: 1; display: flex; justify-content: space-between; padding: 22px 26px 16px;
             border-radius: 22px; }
    .strip.light { background: #FFFFFF; }
    .strip.dark { background: #1C1C1E; }
    .pair { display: flex; flex-direction: column; align-items: center; gap: 10px; }
    .pair .icons { display: flex; align-items: flex-end; gap: 10px; height: 60px; }
    .pair span { font-size: 12px; color: #8E8E93; white-space: nowrap; }
    .marks { display: flex; gap: 24px; align-items: stretch; }
    .mark { width: 220px; height: 190px; border-radius: 22px; display: flex; align-items: center;
            justify-content: center; }
    .mark.light { background: #FFFFFF; } .mark.dark { background: #1C1C1E; }
    .accent { flex: 1; border-radius: 22px; padding: 26px 28px; display: flex; flex-direction: column;
              justify-content: space-between; }
    .accent.light { background: #FFFFFF; } .accent.dark { background: #1C1C1E; color: #F2F2F7; }
    .accent .meta { font-size: 15px; line-height: 1.5; }
    .accent .meta b { font-weight: 600; }
    .accent .demo { display: flex; gap: 18px; align-items: center; }
    .button { padding: 12px 26px; border-radius: 999px; color: #FFFFFF; font-weight: 600; font-size: 16px; }
    .tint { font-weight: 600; font-size: 16px; }
  </style></head><body>
    <h1>Nina &ndash; Your Nutrition Buddy</h1>
    <p class="sub">App icon: a progress ring that sprouts a leaf. Exported by design/export.sh.</p>
    <h2>Appearances</h2>
    <div class="row">
      ${tile('iOS · Light', 'light.png', 'ios')}
      ${tile('iOS · Dark', 'dark.png', 'ios')}
      ${tile('iOS · Tinted', 'tinted.png', 'ios')}
      ${tile('macOS', 'mac-1024.png', 'mac')}
      ${tile('watchOS', 'light.png', 'watch')}
    </div>
    <h2>Small sizes, true pixels</h2>
    <div class="strips">${strip('light')}${strip('dark')}</div>
    <h2>In-app mark and accent colour</h2>
    <div class="marks">
      <div class="mark light"><img src="${img('mark-120.png')}" width="120" height="120"></div>
      <div class="mark dark"><img src="${img('mark-120.png')}" width="120" height="120"></div>
      <div class="accent light">
        <div class="meta"><b>Accent, light</b> ${accent.light}<br>${contrast(accent.light, '#FFFFFF')} : 1 against white</div>
        <div class="demo"><span class="button" style="background:${accent.light}">Log meal</span>
          <span class="tint" style="color:${accent.light}">Today</span></div>
      </div>
      <div class="accent dark">
        <div class="meta"><b>Accent, dark</b> ${accent.dark}<br>${contrast(accent.dark, '#1C1C1E')} : 1 against #1C1C1E,
          ${contrast(accent.dark, '#000000')} : 1 against black</div>
        <div class="demo"><span class="button" style="background:${accent.dark}">Log meal</span>
          <span class="tint" style="color:${accent.dark}">Today</span></div>
      </div>
    </div>
  </body></html>`;
}

async function renderSheet(page, output, dir) {
  await page.setViewportSize({ width: 1600, height: 900 });
  await page.setContent(sheetPage(dir));
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: output, fullPage: true });
  console.log(`rendered contact sheet -> ${path.basename(output)}`);
}

(async () => {
  const args = process.argv.slice(2);
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ deviceScaleFactor: 1 });
    if (args[0] === '--sheet') {
      if (args.length !== 3) throw new Error('usage: node render.js --sheet <out.png> <dir>');
      await renderSheet(page, args[1], args[2]);
    } else {
      await renderSvgs(page, args);
    }
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
