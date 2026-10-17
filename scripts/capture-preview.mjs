#!/usr/bin/env node
/**
 * Capture iPhone-sized PNGs of /preview screens plus a contact sheet.
 * Usage: node scripts/capture-preview.mjs [baseUrl] [outDir]
 */
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const SLUGS = [
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
    const dest = join(OUT, `forge_preview_${slug.replace(/-/g, "_")}.png`);
    await phone.screenshot({ path: dest, type: "png" });
    manifest.push({ slug, path: dest });
    process.stdout.write(`wrote ${dest}\n`);
  }

  await page.setViewportSize({ width: 1760, height: 3400 });
  await page.goto(`${BASE}/preview`, { waitUntil: "networkidle" });
  await page.waitForSelector("[data-preview-phone]");
  await page.waitForTimeout(800);
  const sheet = join(OUT, "forge_preview_contact_sheet.png");
  await page.screenshot({ path: sheet, type: "png", fullPage: true });
  manifest.push({ slug: "contact-sheet", path: sheet });
  process.stdout.write(`wrote ${sheet}\n`);

  await writeFile(
    join(OUT, "forge_preview_manifest.json"),
    JSON.stringify({ base: BASE, repo: REPO, files: manifest }, null, 2)
  );

  await browser.close();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
