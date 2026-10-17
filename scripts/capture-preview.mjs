#!/usr/bin/env node
/**
 * Capture iPhone-sized PNGs of /preview screens plus a contact sheet.
 * Usage: node scripts/capture-preview.mjs [baseUrl] [outDir]
 * PREVIEW_SLUGS=home,sleep,train PREVIEW_NO_SHEET=1 to capture a batch.
 */
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ALL_SLUGS = [
  "onboarding-meet",
  "onboarding-health",
  "onboarding-how-are-you",
  "tutorial-beginner",
  "tutorial-competitor",
  "home",
  "lifestyle",
  "sleep",
  "stats",
  "chat",
  "memory",
  "train",
];

const ROOT = dirname(fileURLToPath(import.meta.url));
const REPO = join(ROOT, "..");
const BASE = process.argv[2] || process.env.PREVIEW_BASE_URL || "http://127.0.0.1:3000";
const OUT = process.argv[3] || process.env.PREVIEW_OUT || "/opt/cursor/artifacts";
const STORE = "/cursor/stores/self/preview";
const SLUGS = (process.env.PREVIEW_SLUGS || ALL_SLUGS.join(","))
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);
const NO_SHEET = process.env.PREVIEW_NO_SHEET === "1";

async function waitForServer(url, tries = 60) {
  for (let i = 0; i < tries; i += 1) {
    try {
      const res = await fetch(url, { redirect: "manual" });
      if (res.ok || res.status === 307 || res.status === 308) return;
    } catch {
      /* not up yet */
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error(`Preview server did not respond at ${url}`);
}

async function main() {
  await mkdir(OUT, { recursive: true });
  await mkdir(STORE, { recursive: true });
  await waitForServer(`${BASE}/preview`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 900 },
    deviceScaleFactor: 2,
    reducedMotion: "reduce",
    colorScheme: "dark",
  });
  const page = await context.newPage();
  const manifest = [];

  for (const slug of SLUGS) {
    const url = `${BASE}/preview/s/${slug}`;
    await page.goto(url, { waitUntil: "networkidle" });
    await page.waitForSelector(`[data-preview-phone="${slug}"]`);
    await page.waitForTimeout(400);
    const phone = page.locator(`[data-preview-phone="${slug}"]`);
    const name = `forge_interface_${slug.replace(/-/g, "_")}.png`;
    const dest = join(OUT, name);
    const storeDest = join(STORE, name);
    await phone.screenshot({ path: dest, type: "png" });
    await phone.screenshot({ path: storeDest, type: "png" });
    manifest.push({ slug, path: dest, store: storeDest });
    process.stdout.write(`wrote ${dest}\n`);
    process.stdout.write(`wrote ${storeDest}\n`);
  }

  if (!NO_SHEET) {
    await page.setViewportSize({ width: 1920, height: 3600 });
    await page.goto(`${BASE}/preview`, { waitUntil: "networkidle" });
    await page.waitForSelector("[data-preview-phone]");
    await page.waitForTimeout(800);
    const sheetName = "forge_interface_contact_sheet.png";
    const sheet = join(OUT, sheetName);
    const storeSheet = join(STORE, sheetName);
    await page.screenshot({ path: sheet, type: "png", fullPage: true });
    await page.screenshot({ path: storeSheet, type: "png", fullPage: true });
    manifest.push({ slug: "contact-sheet", path: sheet, store: storeSheet });
    process.stdout.write(`wrote ${sheet}\n`);
    process.stdout.write(`wrote ${storeSheet}\n`);
  }

  await writeFile(join(OUT, "forge_preview_manifest.json"), JSON.stringify({ base: BASE, repo: REPO, files: manifest }, null, 2));
  await writeFile(join(STORE, "forge_preview_manifest.json"), JSON.stringify({ base: BASE, repo: REPO, files: manifest }, null, 2));

  await browser.close();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
