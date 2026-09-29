import { render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import { useAppStore } from "@/stores/useAppStore";

import { SleepBreakdown } from "./sleep-breakdown";
import { SleepScoreRing } from "./sleep-score-ring";
import { SleepTimeline } from "./sleep-timeline";

const originalSleep = useAppStore.getState().sleepData;

describe("sleep empty night", () => {
  afterEach(() => {
    useAppStore.setState({ sleepData: originalSleep });
  });

  it("does not crash the score ring, timeline, or breakdown when sleepData is empty", () => {
    useAppStore.setState({ sleepData: [] });

    expect(() => render(<SleepScoreRing />)).not.toThrow();
    expect(() => render(<SleepTimeline />)).not.toThrow();
    expect(() => render(<SleepBreakdown />)).not.toThrow();
    expect(screen.getAllByText("No sleep logged yet").length).toBe(3);
  });
});
