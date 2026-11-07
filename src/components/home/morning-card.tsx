"use client";

import type { MorningCard } from "@/lib/aria-morning-card";

export function MorningCardView({ card }: { card: MorningCard }) {
  return (
    <section className="rounded-2xl bg-surface p-5" aria-label={card.empty ? card.call : "Today"}>
      <p className="type-eyebrow mb-3">Today</p>
      {card.empty ? (
        <div>
          <h2 className="type-title text-text-primary mb-2">{card.call}</h2>
          <p className="text-sm text-text-secondary">{card.reason}</p>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          <h2 className="type-title text-text-primary">{card.call}</h2>
          <ol className="space-y-2">
            {card.actions.map((action, index) => (
              <li key={action} className="flex gap-3 text-sm text-text-primary">
                <span className="type-micro text-text-tertiary w-4">{index + 1}</span>
                <span>{action}</span>
              </li>
            ))}
          </ol>
          <p className="text-sm text-text-secondary">{card.reason}</p>
          {card.patternLine ? (
            <p className="text-xs text-text-tertiary">{card.patternLine}</p>
          ) : null}
          {card.ruleLine ? (
            <p className="text-xs text-text-secondary">{card.ruleLine}</p>
          ) : null}
        </div>
      )}
    </section>
  );
}
