/**
 * Frontend Aria mark contract.
 * Keep this aligned with shared/aria-mark.json and AriaSigil.swift.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ARIA_MARK } from "../src/lib/aria-mark.ts";
import {
  ARIA_HEX_FIELD,
  ARIA_HEXES,
  ARIA_ORB_CORE,
  hexagonPoints,
} from "../src/lib/aria-ring-field.ts";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");

function main(): void {
  const shared = JSON.parse(
    readFileSync(path.join(root, "shared", "aria-mark.json"), "utf8"),
  ) as typeof ARIA_MARK;

  assert.equal(
    JSON.stringify(ARIA_MARK),
    JSON.stringify(shared),
    "src/lib/aria-mark.ts must match shared/aria-mark.json",
  );

  assert.equal(ARIA_MARK.kind, "hex-field");
  assert.equal(ARIA_MARK.hexCount, 3);
  assert.equal(ARIA_HEXES.length, 3);
  assert.equal(ARIA_HEX_FIELD.hexCount, 3);
  assert.equal(ARIA_ORB_CORE.kind, "smart-metal");
  assert.ok(ARIA_ORB_CORE.radius > 0.2);
  assert.ok(ARIA_ORB_CORE.radius < 0.4);

  const pts = hexagonPoints(100, 100, 40, 0);
  assert.equal(pts.length, 6);
  assert.ok(Math.abs(pts[0]!.x - 140) < 0.001);
  assert.ok(Math.abs(pts[0]!.y - 100) < 0.001);

  console.log("aria frontend check: ok");
}

main();
