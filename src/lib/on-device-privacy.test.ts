import { describe, expect, it } from "vitest";
import { visiblePatterns } from "./on-device-privacy";

describe("on-device privacy", () => {
  it("does not invent patterns below the sample bar", () => {
    expect(visiblePatterns()).toEqual([]);
  });
});
