"use client";

import type { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { IosTabBar } from "./chrome";
import type { PreviewTab } from "./catalog";

export const PHONE_WIDTH = 390;
export const PHONE_HEIGHT = 844;

/** Quiet iPhone-sized screen. No device chrome. */
export function PhoneFrame({
  children,
  tab,
  className,
  captureId,
}: {
  children: ReactNode;
  tab: PreviewTab;
  className?: string;
  captureId?: string;
}) {
  return (
    <div
      data-preview-phone={captureId}
      className={cn("preview-phone", className)}
      style={{ width: PHONE_WIDTH, height: PHONE_HEIGHT }}
    >
      <div className="preview-phone-inner">
        <div className="preview-phone-body">{children}</div>
        {tab ? <IosTabBar active={tab} /> : null}
      </div>
    </div>
  );
}
