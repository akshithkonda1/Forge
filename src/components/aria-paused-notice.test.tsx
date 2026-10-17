import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { AriaPausedNotice } from "./aria-paused-notice";

describe("AriaPausedNotice", () => {
  it("shows the calm break on chat, tutorial, onboarding, and the switcher", () => {
    const { rerender } = render(<AriaPausedNotice surface="chat" />);
    expect(screen.getByRole("status").textContent?.toLowerCase()).toContain(
      "taking a break"
    );
    rerender(<AriaPausedNotice surface="tutorial" />);
    expect(screen.getByRole("status").textContent?.toLowerCase()).toContain("skip");
    rerender(<AriaPausedNotice surface="onboarding" />);
    expect(screen.getByRole("status").textContent?.toLowerCase()).toContain(
      "keep going"
    );
    rerender(<AriaPausedNotice surface="switcher" />);
    expect(screen.getByRole("status").textContent?.toLowerCase()).toContain(
      "taking a break"
    );
  });
});
