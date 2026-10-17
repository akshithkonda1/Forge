# Forge design language

Forge is a health app with its own visual grammar. It is not a game HUD, not a
fitness-bro dashboard, and not a competitor skin. Typography stays exactly as
shipped (Geist + Instrument Serif via `ForgeFont` / `ForgeType`). Do not
change faces, sizes, weights, or tracking.

## Signature shapes

- **Tessera** — continuous rounded rectangle at `Radius.lg` (18). Cards, mosaic
  tiles, and plates are tesserae of one picture, not competing widgets.
- **Sweep** — a circular arc with round caps. Readiness and progress are one
  solid band. The arc length is the data.
- **Capsule** — chips, Skip, Got it. The only fully round rectangle.
- **Hairline** — 0.5–0.8 pt stroke. Never brackets, scanlines, tick dials, or
  Iron Man chrome.

## Surfaces

- One step of elevation: `background` → `surface` → `surfaceElevated`.
- Flat plates. No aurora wash, no halo, no stacked glass.
- A hairline edge, not a glow. Idle screens sit still.

## Color behavior

- Ember is energy, never guilt.
- Miss / rest uses steel-light, never alert red.
- Color fills the sweep; idle surfaces stay quiet.
- One accent note per surface. No gradient costume.

## Motion grammar

- Event-only: a tap, a log, new data. Nothing loops while idle.
- Three springs (`snappy`, `smooth`, `gentle`) and one sweep.
- A progress win is a haptic plus a hairline pulse — not always-on animation.
- Ghost hands are a still pose. Reduce Motion becomes an opacity crossfade.

## Mosaic as the core visual motif

Life is one picture of tesserae: Sleep, Train, Water, Move, Habits. A win
lights one tessera. The HUD is a single tessera of readiness — one solid
sweep. Hobbies and free days count as part of that picture, never a second
dashboard. Tutorial, Home, and Progress read the same mosaic.

## Interaction patterns

- One primary CTA. Skip always visible on teaching.
- One gesture per tutorial beat, in the real UI, never a blocking modal.
- Conversational ARIA, not a form wall. Optional fields stay skippable.
- 44 pt taps. VoiceOver names the tessera (title, number, fill).
- Coach copy, never diagnosis. Crisis hands off to real resources.

Lockstep: `ForgeDesignLanguage`, `ForgeDS`, `shared/design-tokens.json`.
