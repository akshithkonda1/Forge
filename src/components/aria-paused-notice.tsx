"use client";

import { pausedLineFor } from "@/lib/aria-paused";

export function AriaPausedNotice({
  surface,
}: {
  surface: "chat" | "tutorial" | "onboarding" | "switcher";
}) {
  return (
    <p role="status" className="text-sm leading-relaxed text-text-secondary">
      {pausedLineFor(surface)}
    </p>
  );
}
