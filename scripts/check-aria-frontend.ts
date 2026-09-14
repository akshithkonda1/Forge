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
  ARIA_ORB_CORE,
  ARIA_RING_FIELD,
  ARIA_RINGS,
  ringEllipse,
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

  assert.equal(ARIA_MARK.kind, "soft-hex-field");
  assert.equal(ARIA_MARK.shape, "rounded-hexagon");
  assert.equal(ARIA_MARK.ringCount, 3);
  assert.equal(ARIA_MARK.cornerRoundness, 0.28);
  assert.equal(ARIA_RINGS.length, 3);
  assert.equal(ARIA_RING_FIELD.ringCount, 3);
  assert.deepEqual([...ARIA_MARK.radii], [0.48, 0.58, 0.78]);
  assert.deepEqual([...ARIA_MARK.eccentricity], [0.1, 0.07, 0.09]);
  assert.deepEqual([...ARIA_MARK.tiltDeg], [-22, 28, 18]);
  assert.equal(ARIA_ORB_CORE.kind, "smart-metal");
  assert.ok(ARIA_ORB_CORE.radius > 0.2);
  assert.ok(ARIA_ORB_CORE.radius < 0.4);

  const still = ringEllipse(0, 99, false, true);
  const still2 = ringEllipse(0, 1, true, true);
  assert.equal(still.rx, still2.rx);
  assert.equal(still.ry, still2.ry);
  assert.equal(still.rotation, still2.rotation);

  console.log("aria frontend check: ok");
}

main();
