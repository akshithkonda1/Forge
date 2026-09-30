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
  it("labels the name field with the onboarding question", () => {
    render(<ProfileSetup onNext={() => {}} />);
    expect(screen.getByLabelText("What should ARIA call you?")).toBeTruthy();
  });
});
