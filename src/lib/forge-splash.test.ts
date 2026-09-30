import { describe, expect, it } from "vitest";

import { peekPersistedOnboarded } from "@/lib/forge-splash";

describe("peekPersistedOnboarded", () => {
  it("returns false when storage is empty or corrupt", () => {
    window.localStorage.removeItem("forge-web");
    expect(peekPersistedOnboarded()).toBe(false);

    window.localStorage.setItem("forge-web", "{not-json");
    expect(peekPersistedOnboarded()).toBe(false);
  });

  it("reads isOnboarded from persist JSON", () => {
    window.localStorage.setItem(
      "forge-web",
      JSON.stringify({ state: { isOnboarded: true } })
    );
    expect(peekPersistedOnboarded()).toBe(true);
    window.localStorage.removeItem("forge-web");
  });
});
