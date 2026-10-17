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
        <h1 className="preview-gallery-title">This is your interface</h1>
        <p className="preview-gallery-lead">
          This is your interface. {SAMPLE_PERSON}’s name, goals, and progress sit at the center.
          One card anatomy across every screen. Personal and grounded — not a HUD. Geist +
          Instrument Serif, FDS tokens, procedural ARIA mark. Sample data, labeled as sample.
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
