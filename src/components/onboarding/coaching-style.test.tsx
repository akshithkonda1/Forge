import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/components/brand/aria-mark", () => ({
  AriaMark: () => null,
}));

vi.mock("@/components/brand/premium-atmosphere", () => ({
  PremiumAtmosphere: () => null,
  PremiumEntrance: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  PremiumPrimaryButton: ({
    children,
    ...props
  }: React.ButtonHTMLAttributes<HTMLButtonElement>) => <button {...props}>{children}</button>,
}));

import CoachingStyleScreen from "./coaching-style";

describe("CoachingStyleScreen", () => {
  it("exposes coaching-style options to assistive tech", () => {
    render(<CoachingStyleScreen onComplete={() => {}} />);

    const challenge = screen.getByRole("button", { name: /challenge me/i });
    expect(challenge.getAttribute("aria-hidden")).toBeNull();
    expect(challenge.getAttribute("aria-pressed")).toBe("false");

    expect(screen.getByRole("button", { name: /keep it balanced/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /be patient with me/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /data-driven/i })).toBeTruthy();
  });
});
