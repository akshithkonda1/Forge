import { act, cleanup, render } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { ARIA_MARK_COMPACT_MAX, ariaMarkShouldSpin, nestLiveReset } from "@/lib/aria-mark";

import { AriaMark } from "./aria-mark";

/**
 * Compact ceiling is 32 (`ARIA_MARK.wordmarkPrimaryMax`). Mid marks (36, 56)
 * spin only when Reduce Motion is off. The nest loop schedules with
 * `requestAnimationFrame` only — `NEST_PAINT_INTERVAL_MS` throttles paint
 * inside `tick`, it does not queue the next frame.
 */
const SPIN_SIZES = [36, 56] as const;
const COMPACT_SIZE = 32;
const ADVANCED_TICKS = 8;

type MediaChangeListener = (event: MediaQueryListEvent) => void;

function createPrefersReducedMotion(matches: boolean) {
  const listeners = new Set<MediaChangeListener>();
  const mediaQueryList = {
    matches,
    media: "(prefers-reduced-motion: reduce)",
    onchange: null as MediaQueryList["onchange"],
    addEventListener(type: string, listener: EventListenerOrEventListenerObject) {
      if (type === "change" && typeof listener === "function") {
        listeners.add(listener as MediaChangeListener);
      }
    },
    removeEventListener(type: string, listener: EventListenerOrEventListenerObject) {
      if (type === "change" && typeof listener === "function") {
        listeners.delete(listener as MediaChangeListener);
      }
    },
    addListener() {},
    removeListener() {},
    dispatchEvent() {
      return true;
    },
    dispatchChange(nextMatches: boolean) {
      mediaQueryList.matches = nextMatches;
      const event = {
        matches: nextMatches,
        media: mediaQueryList.media,
      } as MediaQueryListEvent;
      for (const listener of [...listeners]) {
        listener(event);
      }
    },
    listenerCount() {
      return listeners.size;
    },
  };
  return mediaQueryList;
}

function createFake2dContext(): CanvasRenderingContext2D {
  const gradient = { addColorStop() {} };
  return {
    canvas: document.createElement("canvas"),
    clearRect() {},
    save() {},
    restore() {},
    beginPath() {},
    moveTo() {},
    lineTo() {},
    closePath() {},
    stroke() {},
    fill() {},
    arc() {},
    ellipse() {},
    translate() {},
    rotate() {},
    scale() {},
    createRadialGradient() {
      return gradient;
    },
    fillStyle: "#000",
    strokeStyle: "#000",
    lineCap: "round",
    lineJoin: "round",
    lineWidth: 1,
  } as unknown as CanvasRenderingContext2D;
}

class NoopIntersectionObserver {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
  takeRecords(): IntersectionObserverEntry[] {
    return [];
  }
}

describe("AriaMark Reduce Motion", () => {
  let media: ReturnType<typeof createPrefersReducedMotion>;
  let rafSpy: ReturnType<typeof vi.spyOn>;
  let cancelSpy: ReturnType<typeof vi.spyOn>;

  function rafCallCount(): number {
    return rafSpy.mock.calls.length;
  }

  function lastScheduledRafId(): number {
    const result = rafSpy.mock.results.at(-1);
    expect(result).toBeDefined();
    expect(result?.type).toBe("return");
    expect(typeof result?.value).toBe("number");
    return Number(result?.value);
  }

  function flushReact(): void {
    act(() => {
      vi.advanceTimersByTime(0);
    });
  }

  /** Spin: each advanced animation frame must queue a brand-new RAF. */
  function assertKeepsQueueingFrames(steps = ADVANCED_TICKS): void {
    expect(rafCallCount()).toBeGreaterThan(0);
    for (let step = 0; step < steps; step += 1) {
      const queuedBefore = rafCallCount();
      const pendingId = lastScheduledRafId();
      act(() => {
        vi.advanceTimersToNextFrame();
      });
      expect(rafCallCount()).toBe(queuedBefore + 1);
      expect(lastScheduledRafId()).not.toBe(pendingId);
    }
  }

  /**
   * No spin: the synchronous first `tick` must not leave a continuing loop.
   * Consume at most one leftover frame, then further ticks must queue nothing.
   */
  function assertNoNewFrameAfterFirstTick(steps = ADVANCED_TICKS): void {
    if (rafCallCount() > 0) {
      expect(rafCallCount()).toBe(1);
      act(() => {
        vi.advanceTimersToNextFrame();
      });
    }
    const afterFirstTick = rafCallCount();
    for (let step = 0; step < steps; step += 1) {
      act(() => {
        vi.advanceTimersToNextFrame();
      });
      expect(rafCallCount()).toBe(afterFirstTick);
    }
  }

  beforeEach(() => {
    nestLiveReset();
    vi.useFakeTimers();
    media = createPrefersReducedMotion(false);

    window.matchMedia = vi.fn(() => media as unknown as MediaQueryList);
    vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockImplementation(((
      id: string
    ) => {
      if (id === "2d") return createFake2dContext();
      return null;
    }) as HTMLCanvasElement["getContext"]);
    rafSpy = vi.spyOn(window, "requestAnimationFrame");
    cancelSpy = vi.spyOn(window, "cancelAnimationFrame");
    vi.stubGlobal("IntersectionObserver", NoopIntersectionObserver);
  });

  afterEach(() => {
    cleanup();
    nestLiveReset();
    vi.useRealTimers();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("ariaMarkShouldSpin is false at 36 and 56 when Reduce Motion is on", () => {
    expect(ARIA_MARK_COMPACT_MAX).toBe(COMPACT_SIZE);
    expect(ariaMarkShouldSpin(36, true)).toBe(false);
    expect(ariaMarkShouldSpin(56, true)).toBe(false);
    expect(ariaMarkShouldSpin(36, false)).toBe(true);
    expect(ariaMarkShouldSpin(56, false)).toBe(true);
    expect(ariaMarkShouldSpin(COMPACT_SIZE, false)).toBe(false);
  });

  it("keeps queueing animation frames at 36 and 56 when Reduce Motion is off", () => {
    media.matches = false;

    for (const size of SPIN_SIZES) {
      rafSpy.mockClear();
      cancelSpy.mockClear();
      const { unmount } = render(<AriaMark size={size} />);
      flushReact();
      expect(ariaMarkShouldSpin(size, false)).toBe(true);
      assertKeepsQueueingFrames();
      unmount();
    }
  });

  it("does not queue a frame after the first tick at 36 or 56 when Reduce Motion is on", () => {
    media.matches = true;

    for (const size of SPIN_SIZES) {
      rafSpy.mockClear();
      cancelSpy.mockClear();
      const { unmount } = render(<AriaMark size={size} />);
      flushReact();
      expect(ariaMarkShouldSpin(size, true)).toBe(false);
      assertNoNewFrameAfterFirstTick();
      unmount();
    }
  });

  it("does not queue a frame after the first tick at compact size 32 even when Reduce Motion is off", () => {
    media.matches = false;
    const { unmount } = render(<AriaMark size={COMPACT_SIZE} />);
    flushReact();
    expect(ariaMarkShouldSpin(COMPACT_SIZE, false)).toBe(false);
    assertNoNewFrameAfterFirstTick();
    unmount();
  });

  it("cancels the pending frame when Reduce Motion turns on mid-session and resumes when it turns off", () => {
    for (const size of SPIN_SIZES) {
      rafSpy.mockClear();
      cancelSpy.mockClear();
      media.matches = false;
      const { unmount } = render(<AriaMark size={size} />);
      flushReact();
      assertKeepsQueueingFrames();

      const pendingId = lastScheduledRafId();
      act(() => {
        media.dispatchChange(true);
      });
      expect(cancelSpy).toHaveBeenCalledWith(pendingId);
      rafSpy.mockClear();
      assertNoNewFrameAfterFirstTick();

      act(() => {
        media.dispatchChange(false);
      });
      assertKeepsQueueingFrames();
      unmount();
    }
  });

  it("removes matchMedia change listeners on unmount", () => {
    const { unmount } = render(<AriaMark size={36} />);
    flushReact();
    expect(media.listenerCount()).toBeGreaterThan(0);
    unmount();
    expect(media.listenerCount()).toBe(0);
  });
});
