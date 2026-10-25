#!/usr/bin/env node
/**
 * Large-size stills of the procedural strike mark.
 * Usage: node --experimental-strip-types scripts/capture-strike-mark.mjs [before|after]
 */
import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import * as Mark from "../src/lib/forge-strike-mark.ts";

const OUT = process.env.PREVIEW_OUT || "/opt/cursor/artifacts";
const LABEL = process.argv[2] === "after" ? "after" : "before";
const SIDE = 100;
const idle = Mark.strikePose(1, true);
const paper = `#${Mark.FORGE_STRIKE_MARK.paperHex}`;
const ember = `#${Mark.FORGE_STRIKE_MARK.emberHex}`;
const emberLight = `#${Mark.FORGE_STRIKE_MARK.emberLightHex}`;
const emberDark = `#${Mark.FORGE_STRIKE_MARK.emberDarkHex}`;
const amber = `#${Mark.FORGE_STRIKE_MARK.amberHex}`;
const pivotX = Mark.FORGE_STRIKE_MARK.pivotX * SIDE;
const pivotY = Mark.FORGE_STRIKE_MARK.pivotY * SIDE;
const scale = Mark.flareScale
  ? Mark.flareScale(idle.flare)
  : { x: 1, y: 1, originX: 0.4, originY: 0.84 };
const hammer = Mark.svgPath(Mark.hammerCommands(), SIDE);
const highlight = Mark.hammerHighlightCommands
  ? Mark.svgPath(Mark.hammerHighlightCommands(), SIDE)
  : "";
const flames = [0, 1, 2]
  .map((index) => {
    try {
      const commands = Mark.flameCommands(index, Mark.flareScale ? 1 : idle.flare);
      return commands?.length ? Mark.svgPath(commands, SIDE) : "";
    } catch {
      return "";
    }
  })
  .filter(Boolean);

const CRAFTED = Boolean(Mark.flareScale && Mark.hammerHighlightCommands);

function markSvg(size, { compact = false } = {}) {
  const tile = compact
    ? `<rect x="0.5" y="0.5" width="99" height="99" rx="28" fill="${ember}" stroke="rgba(255,255,255,0.16)" stroke-width="0.8"/>`
    : "";
  const glow = compact
    ? ""
    : CRAFTED
      ? `<radialGradient id="g${size}" cx="40%" cy="78%" r="22%"><stop offset="0%" stop-color="${ember}" stop-opacity="0.28"/><stop offset="100%" stop-color="${ember}" stop-opacity="0"/></radialGradient>
         <ellipse cx="40" cy="78" rx="18" ry="12" fill="url(#g${size})"/>`
      : "";
  const grads = compact || !CRAFTED
    ? ""
    : `<linearGradient id="h${size}" x1="20%" y1="30%" x2="90%" y2="70%"><stop offset="0%" stop-color="${paper}"/><stop offset="100%" stop-color="#E8E4DE"/></linearGradient>
       <linearGradient id="f0${size}" x1="32%" y1="12%" x2="42%" y2="86%"><stop offset="0%" stop-color="${ember}"/><stop offset="100%" stop-color="${emberDark}"/></linearGradient>
       <linearGradient id="f1${size}" x1="36%" y1="20%" x2="44%" y2="82%"><stop offset="0%" stop-color="${emberLight}"/><stop offset="100%" stop-color="${ember}"/></linearGradient>
       <linearGradient id="f2${size}" x1="39%" y1="38%" x2="42%" y2="76%"><stop offset="0%" stop-color="#FFE6A8"/><stop offset="100%" stop-color="${amber}"/></linearGradient>`;
  const flatFills = compact ? [paper, paper, paper, paper] : [emberDark, ember, amber, paper];
  const flameFills = flames
    .map((d, index) => {
      const fill = !compact && CRAFTED
        ? (index === 3 ? amber : `url(#f${Math.min(index, 2)}${size})`)
        : flatFills[index] ?? paper;
      return `<path d="${d}" fill="${fill}" />`;
    })
    .join("");
  const highlightPath = !compact && highlight
    ? `<path d="${highlight}" fill="rgba(255,255,255,0.22)" />`
    : "";
  const hammerFill = compact || !CRAFTED ? paper : `url(#h${size})`;
  const flameTransform = CRAFTED
    ? `translate(${scale.originX * SIDE} ${scale.originY * SIDE}) scale(${scale.x} ${scale.y}) translate(${-scale.originX * SIDE} ${-scale.originY * SIDE})`
    : "";
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${SIDE} ${SIDE}" overflow="visible">
    <defs>${grads}</defs>
    ${tile}
    <g transform="${compact ? "translate(10 10) scale(0.80)" : ""}">
      ${glow}
      <g transform="${flameTransform}">
        ${flameFills}
      </g>
      <g transform="translate(${pivotX} ${pivotY}) rotate(${idle.hammerAngleDeg})">
        <path d="${hammer}" fill="${hammerFill}" fill-rule="evenodd" stroke="${compact || CRAFTED ? "none" : "rgba(255,255,255,0.16)"}" stroke-width="${compact || CRAFTED ? 0 : 0.7}" />
        ${highlightPath}
      </g>
    </g>
  </svg>`;
}

const html = `<!doctype html>
<html><head><meta charset="utf-8"/>
<style>
  html,body{margin:0;background:#08080C;color:#F7F4F0;font-family:ui-sans-serif,system-ui,sans-serif}
  .stage{position:relative;width:720px;height:720px;overflow:hidden;background:#08080C}
  .wash{position:absolute;inset:-8%;background:
    radial-gradient(ellipse 80% 55% at 50% 8%, rgba(247,244,240,0.08) 0%, rgba(169,216,255,0.05) 28%, transparent 62%),
    radial-gradient(ellipse 70% 50% at 22% 78%, rgba(255,77,0,0.13) 0%, rgba(255,77,0,0.035) 40%, transparent 70%),
    radial-gradient(ellipse 55% 45% at 88% 52%, rgba(169,216,255,0.09) 0%, transparent 65%),
    linear-gradient(180deg, rgba(10,10,10,0.1) 0%, transparent 28%, rgba(10,10,10,0.5) 72%, rgba(10,10,10,0.92) 100%)}
  .hero{position:relative;z-index:1;display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%}
  .word{margin-top:28px;font-size:28px;font-weight:600;letter-spacing:0.22em}
  .tag{margin-top:12px;font-size:13px;color:#84848D;font-weight:500}
  .sheet{display:flex;gap:48px;align-items:end;padding:48px;background:#08080C}
  .cap{margin-top:12px;font-size:12px;letter-spacing:0.14em;text-transform:uppercase;color:#84848D;text-align:center}
</style></head>
<body>
  <div class="stage" id="hero">
    <div class="wash"></div>
    <div class="hero">
      ${markSvg(400)}
      <div class="word">FORGE</div>
      <div class="tag">Forged, not promised. The rest is you.</div>
    </div>
  </div>
  <div class="sheet" id="sizes">
    <div>${markSvg(400)}<div class="cap">Splash 400</div></div>
    <div>${markSvg(176)}<div class="cap">Welcome 176</div></div>
    <div>${markSvg(72)}<div class="cap">Boot 72</div></div>
    <div>${markSvg(22, { compact: true })}<div class="cap">Chip 22</div></div>
  </div>
</body></html>`;

async function main() {
  await mkdir(OUT, { recursive: true });
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({
    viewport: { width: 720, height: 720 },
    deviceScaleFactor: 2,
    colorScheme: "dark",
  });
  await page.setContent(html, { waitUntil: "load" });
  await page.locator("#hero").screenshot({
    path: join(OUT, `strike_mark_${LABEL}_large.png`),
    type: "png",
  });
  await page.setViewportSize({ width: 1400, height: 560 });
  await page.locator("#sizes").screenshot({
    path: join(OUT, `strike_mark_${LABEL}_sizes.png`),
    type: "png",
  });
  await browser.close();
  process.stdout.write(`wrote ${OUT}/strike_mark_${LABEL}_large.png\n`);
  process.stdout.write(`wrote ${OUT}/strike_mark_${LABEL}_sizes.png\n`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
