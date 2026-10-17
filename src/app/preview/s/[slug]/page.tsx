"use client";

import { useParams } from "next/navigation";
import { previewEntry } from "@/components/preview/catalog";
import { PhoneFrame } from "@/components/preview/phone-frame";
import { PREVIEW_SCREENS } from "@/components/preview/registry";

export default function PreviewCapturePage() {
  const params = useParams<{ slug: string }>();
  const entry = previewEntry(params.slug ?? "");
  if (!entry) {
    return (
      <div className="preview-capture">
        <p className="preview-body text-text-tertiary">Unknown screen.</p>
      </div>
    );
  }
  const Screen = PREVIEW_SCREENS[entry.slug];
  return (
    <div className="preview-capture preview-still">
      <PhoneFrame tab={entry.tab} captureId={entry.slug}>
        <Screen />
      </PhoneFrame>
    </div>
  );
}
