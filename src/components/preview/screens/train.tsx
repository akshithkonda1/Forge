"use client";

import { DISCOVERY } from "../copy";
import { SAMPLE_SESSION } from "../sample-data";
import { Capsule, Eyebrow, PrimaryCta, Tessera } from "../primitives";

export function TrainScreen() {
  return (
    <div className="flex h-full flex-col px-5 pb-3 pt-1">
      <p className="type-eyebrow">Session hub</p>
      <h1 className="preview-display mt-1 text-[1.5rem]">{SAMPLE_SESSION.name}</h1>
      <p className="preview-body mt-1 text-text-secondary">
        {SAMPLE_SESSION.exercises.length} moves · {SAMPLE_SESSION.duration} min ·{" "}
        {SAMPLE_SESSION.intensity}. I never coach form.
      </p>
      <div className="mt-3 flex flex-wrap gap-1.5">
        <Capsule>{SAMPLE_SESSION.type}</Capsule>
        <Capsule>Commercial gym</Capsule>
        <Capsule>Barbell · rack · cables</Capsule>
      </div>

      <PrimaryCta className="mt-4">Start session</PrimaryCta>

      <Tessera className="mt-4 px-0 py-1">
        {SAMPLE_SESSION.exercises.map((ex) => (
          <div
            key={ex.name}
            className="flex min-h-[44px] items-center justify-between border-b border-[color:var(--preview-hairline)] px-4 py-2.5 last:border-b-0"
          >
            <span className="preview-body text-text-primary">
              <span className="mr-2.5 inline-block w-4 text-right tabular-nums text-text-tertiary">
                {ex.n}
              </span>
              {ex.name}
            </span>
            <span className="type-caption text-text-tertiary">{ex.rx}</span>
          </div>
        ))}
      </Tessera>

      <Tessera className="mt-3">
        <Eyebrow>Discovery</Eyebrow>
        <p className="preview-body mt-2 text-text-secondary">{DISCOVERY.suggest}</p>
        <p className="type-title mt-3 text-text-primary">{DISCOVERY.move}</p>
        <p className="type-micro mt-1 text-text-tertiary">{DISCOVERY.reason}</p>
        <div className="mt-3 flex flex-wrap gap-1.5">
          <Capsule tone="paper">{DISCOVERY.tried}</Capsule>
          <Capsule>{DISCOVERY.notInterested}</Capsule>
          <Capsule>{DISCOVERY.save}</Capsule>
        </div>
      </Tessera>
    </div>
  );
}
