import { render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("@/components/ui/sheet", () => ({
  Sheet: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

import { useAppStore } from "@/stores/useAppStore";

import { AriaCompanionControls } from "./aria-companion-controls";

function SettingsRowStub({
  label,
  value,
}: {
  label: string;
  value?: React.ReactNode;
}) {
  return (
    <div>
      <span>{label}</span>
      {value}
    </div>
  );
}

describe("AriaCompanionControls", () => {
  afterEach(() => {
    useAppStore.setState({
      userProfile: { ...useAppStore.getState().userProfile, coachingStyle: "balanced" },
    });
  });

  it("does not crash when persisted coachingStyle is invalid", () => {
    useAppStore.setState({
      userProfile: {
        ...useAppStore.getState().userProfile,
        coachingStyle: "typo" as never,
      },
    });

    expect(() =>
      render(<AriaCompanionControls SettingsRow={SettingsRowStub} />)
    ).not.toThrow();
    expect(screen.getAllByText("Check-in").length).toBeGreaterThan(0);
  });
});
