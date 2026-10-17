"use client";

import type { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { HomeIndicator, IosTabBar, StatusBar } from "./chrome";
import type { PreviewTab } from "./catalog";

export const PHONE_WIDTH = 390;
export const PHONE_HEIGHT = 844;

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
      <div className="preview-phone-bezel" aria-hidden />
      <div className="preview-phone-inner">
        <StatusBar />
        <div className="preview-phone-body">{children}</div>
        {tab ? <IosTabBar active={tab} /> : null}
        <HomeIndicator />
      </div>
    </div>
  );
}
