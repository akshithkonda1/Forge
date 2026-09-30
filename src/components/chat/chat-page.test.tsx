import { act, cleanup, render } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/components/brand/aria-mark", () => ({
  AriaMark: () => null,
}));

import { useAppStore } from "@/stores/useAppStore";

import { ChatPage } from "./chat-page";

describe("ChatPage speech", () => {
  const cancel = vi.fn();

  beforeEach(() => {
    cancel.mockClear();
    HTMLElement.prototype.scrollIntoView = vi.fn();
    Object.defineProperty(window, "speechSynthesis", {
      configurable: true,
      writable: true,
      value: { cancel, speak: vi.fn() },
    });
    useAppStore.setState({ activeTab: "chat" });
  });

  afterEach(() => {
    cleanup();
    useAppStore.setState({ activeTab: "home" });
  });

  it("cancels speech when the tab switches to Home", () => {
    render(<ChatPage />);
    expect(cancel).not.toHaveBeenCalled();

    act(() => {
      useAppStore.getState().setActiveTab("home");
    });

    expect(cancel).toHaveBeenCalled();
  });
});
