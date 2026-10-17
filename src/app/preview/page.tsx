"use client";

import { PREVIEW_CATALOG } from "@/components/preview/catalog";
import { PhoneFrame } from "@/components/preview/phone-frame";
import { PREVIEW_SCREENS } from "@/components/preview/registry";
import { SAMPLE_LABEL, SAMPLE_PERSON } from "@/components/preview/copy";

export default function PreviewGalleryPage() {
  return (
    <div className="preview-gallery">
      <header className="preview-gallery-head">
        <p className="preview-gallery-kicker">Forge · PR #472 · {SAMPLE_LABEL}</p>
        <h1 className="preview-gallery-title">The warm health-app pass</h1>
        <p className="preview-gallery-lead">
          iPhone frames of onboarding, the first-launch tutorial, Home, Lifestyle, Sleep, Stats,
          ARIA with the personality switcher, Aria’s memory, and Train discovery. Built from Geist
          + Instrument Serif, FDS tokens, and the procedural ARIA mark.{" "}
          {SAMPLE_PERSON} is sample data — not a live person.
        </p>
      </header>
      <div className="preview-gallery-grid">
        {PREVIEW_CATALOG.map((entry) => {
          const Screen = PREVIEW_SCREENS[entry.slug];
          return (
            <figure key={entry.slug} className="preview-card">
              <figcaption className="preview-card-label">
                <p className="preview-card-title">{entry.title}</p>
                <p className="preview-card-caption">{entry.caption}</p>
              </figcaption>
              <PhoneFrame tab={entry.tab} captureId={entry.slug}>
                <Screen />
              </PhoneFrame>
            </figure>
          );
        })}
      </div>
    </div>
  );
}
