import { cleanup, render } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { ARIA_MARK_COMPACT_MAX, ariaMarkShouldSpin, nestLiveReset } from "@/lib/aria-mark";

import { AriaMark } from "./aria-mark";

/**
 * Compact ceiling is 32 (`ARIA_MARK.wordmarkPrimaryMax`). Mid/hero marks
 * (36 and 56) can spin when Reduce Motion is off; they stay still when it is on.
 */
const STILL_WITH_REDUCE = [36, 56] as const;
const SPIN_SIZE = 36;

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

class NoopIntersectionObserver {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
  takeRecords(): IntersectionObserverEntry[] {
    return [];
  }
}

describe("AriaMark Reduce Motion", () => {
  const pendingFrames = new Map<number, FrameRequestCallback>();
  let nextFrameId = 1;
  let media: ReturnType<typeof createPrefersReducedMotion>;
  let rafSpy: ReturnType<typeof vi.spyOn>;
  let cancelSpy: ReturnType<typeof vi.spyOn>;
  let getContextSpy: ReturnType<typeof vi.spyOn>;

  function pendingLoopCount(): number {
    return pendingFrames.size;
  }

  function flushOneFrame(now = performance.now() + 100): void {
    const scheduled = [...pendingFrames.entries()];
    pendingFrames.clear();
    for (const [, callback] of scheduled) {
      callback(now);
    }
  }

  beforeEach(() => {
    nestLiveReset();
    pendingFrames.clear();
    nextFrameId = 1;
    media = createPrefersReducedMotion(false);

    window.matchMedia = vi.fn(() => media as unknown as MediaQueryList);
    getContextSpy = vi
      .spyOn(HTMLCanvasElement.prototype, "getContext")
      .mockReturnValue(null);
    rafSpy = vi.spyOn(window, "requestAnimationFrame").mockImplementation((callback) => {
      const id = nextFrameId;
      nextFrameId += 1;
      pendingFrames.set(id, callback);
      return id;
    });
    cancelSpy = vi.spyOn(window, "cancelAnimationFrame").mockImplementation((id) => {
      pendingFrames.delete(id);
    });
    vi.stubGlobal("IntersectionObserver", NoopIntersectionObserver);
  });

  afterEach(() => {
    cleanup();
    nestLiveReset();
    getContextSpy.mockRestore();
    rafSpy.mockRestore();
    cancelSpy.mockRestore();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("ariaMarkShouldSpin is false at 36 and 56 when Reduce Motion is on", () => {
    expect(ARIA_MARK_COMPACT_MAX).toBe(32);
    expect(ariaMarkShouldSpin(36, true)).toBe(false);
    expect(ariaMarkShouldSpin(56, true)).toBe(false);
    expect(ariaMarkShouldSpin(SPIN_SIZE, false)).toBe(true);
  });

  it("does not start a continuing animation loop at 36 or 56 when Reduce Motion is on", () => {
    media.matches = true;

    for (const size of STILL_WITH_REDUCE) {
      rafSpy.mockClear();
      pendingFrames.clear();
      const { unmount } = render(<AriaMark size={size} />);
      expect(ariaMarkShouldSpin(size, true)).toBe(false);
      expect(pendingLoopCount()).toBe(0);
      expect(rafSpy).not.toHaveBeenCalled();
      flushOneFrame();
      expect(pendingLoopCount()).toBe(0);
      unmount();
    }
  });

  it("starts the loop with Reduce Motion off, stops on change, and resumes when cleared", async () => {
    const { unmount } = render(<AriaMark size={SPIN_SIZE} />);

    await vi.waitFor(() => {
      expect(pendingLoopCount()).toBeGreaterThan(0);
    });
    expect(rafSpy).toHaveBeenCalled();

    const scheduledBeforeFlush = pendingLoopCount();
    flushOneFrame();
    expect(pendingLoopCount()).toBeGreaterThan(0);
    expect(pendingLoopCount()).toBe(scheduledBeforeFlush);

    media.dispatchChange(true);
    await vi.waitFor(() => {
      expect(pendingLoopCount()).toBe(0);
    });
    expect(cancelSpy).toHaveBeenCalled();
    flushOneFrame();
    expect(pendingLoopCount()).toBe(0);

    media.dispatchChange(false);
    await vi.waitFor(() => {
      expect(pendingLoopCount()).toBeGreaterThan(0);
    });
    flushOneFrame();
    expect(pendingLoopCount()).toBeGreaterThan(0);

    unmount();
  });

  it("removes matchMedia change listeners on unmount", async () => {
    const { unmount } = render(<AriaMark size={SPIN_SIZE} />);

    await vi.waitFor(() => {
      expect(media.listenerCount()).toBeGreaterThan(0);
    });

    const added = media.listenerCount();
    expect(added).toBeGreaterThan(0);
    unmount();
    expect(media.listenerCount()).toBe(0);
  });
});
