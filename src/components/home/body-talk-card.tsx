"use client";

import { METABOLIC_ACCESSORY_NOTE, TRANSLATION_PILLARS, TRANSLATION_TAGLINE } from "@/lib/translation";

export function BodyTalkCard() {
  return (
    <section
      className="rounded-2xl bg-surface p-5"
      aria-labelledby="body-talk-heading"
    >
      <p className="text-xs font-medium uppercase tracking-wider text-text-tertiary">
        What Forge reads
      </p>
      <h2 id="body-talk-heading" className="mt-1 text-lg font-semibold text-text-primary">
        {TRANSLATION_TAGLINE}
      </h2>
      <p className="mt-2 text-sm leading-relaxed text-text-secondary">
        One sentence when the heart signal is in: your cardiovascular age versus
        your actual age. Four bullets per pillar. Glucose is an accessory.
      </p>

      <div className="mt-4 grid grid-cols-2 gap-3">
        {TRANSLATION_PILLARS.map((pillar) => (
          <article
            key={pillar.id}
            className="rounded-xl bg-surface-elevated px-3 py-3"
            data-pillar={pillar.id}
          >
            <h3 className="text-sm font-semibold text-text-primary">{pillar.title}</h3>
            <ul className="mt-2 space-y-1">
              {pillar.bullets.map((bullet) => (
                <li key={bullet} className="text-xs leading-snug text-text-secondary">
                  {bullet}
                </li>
              ))}
            </ul>
          </article>
        ))}
      </div>

      <p className="mt-4 text-xs leading-relaxed text-text-tertiary" data-testid="sold-separately">
        {METABOLIC_ACCESSORY_NOTE}
      </p>
    </section>
  );
}
