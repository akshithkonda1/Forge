import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { useAppStore } from "@/stores/useAppStore";

import { RecoveryTrends } from "./recovery-trends";
import { SleepBreakdown } from "./sleep-breakdown";
import { SleepPage } from "./sleep-page";
import { SleepScoreRing } from "./sleep-score-ring";
import { SleepTimeline } from "./sleep-timeline";

vi.mock("next/dynamic", async () => {
  const { RecoveryTrends } = await import("./recovery-trends");
  return { default: () => RecoveryTrends };
});

vi.mock("@/components/brand/premium-atmosphere", () => ({
  PremiumAtmosphere: () => null,
  PremiumEntrance: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

const originalSleep = useAppStore.getState().sleepData;

describe("sleep empty night", () => {
  afterEach(() => {
    cleanup();
    useAppStore.setState({ sleepData: originalSleep });
  });

  it("guards ring, timeline, and breakdown so empty sleepData cannot crash", () => {
    useAppStore.setState({ sleepData: [] });

    expect(() => render(<SleepScoreRing />)).not.toThrow();
    expect(() => render(<SleepTimeline />)).not.toThrow();
    expect(() => render(<SleepBreakdown />)).not.toThrow();
    expect(screen.getAllByText("No sleep yet").length).toBe(3);
  });

  it("renders one page empty state and does not show RecoveryTrends charts", () => {
    useAppStore.setState({ sleepData: [] });

    expect(() => render(<RecoveryTrends />)).not.toThrow();
    cleanup();

    expect(() => render(<SleepPage />)).not.toThrow();
    expect(screen.getAllByText("No sleep yet").length).toBe(1);
    expect(screen.queryByText("Sleep Stages")).toBeNull();
    expect(screen.queryByText("Breakdown")).toBeNull();
    expect(screen.queryByText("Recovery Trend")).toBeNull();
  });
});
