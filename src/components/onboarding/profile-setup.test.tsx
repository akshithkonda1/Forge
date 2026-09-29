import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/components/brand/aria-mark", () => ({
  AriaMark: () => null,
}));

vi.mock("@/components/brand/premium-atmosphere", () => ({
  PremiumAtmosphere: () => null,
  PremiumEntrance: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

import ProfileSetup from "./profile-setup";

describe("ProfileSetup", () => {
  it("gives the name field an accessible name", () => {
    render(<ProfileSetup onNext={() => {}} />);
    expect(screen.getByLabelText("Your name")).toBeTruthy();
  });
});
