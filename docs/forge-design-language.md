# Forge design language

Forge is a warm, friendly, futuristic health app. Modern, sleek, usable at a
glance — from a first workout to competition day. Typography stays exactly as
shipped (Geist + Instrument Serif via `ForgeFont` / `ForgeType`). Do not
change faces, sizes, weights, or tracking. The ARIA mark is unchanged.

## UI standard: no AI slop

The UI must never look like generic AI-generated slop. It must use the design
tools, assets and creation capabilities already provided — Forge's existing
design system, tokens, typography, procedural ARIA mark and components — and
match or exceed the high bar the existing front end already sets. Elevate what
exists; don't replace it with generic gradients, stock glassmorphism, emoji
filler or template layouts.

## This is your interface

No HUD look anywhere. Iron Man / Tony Stark suit aesthetic is rejected. The
direction is personal and grounded: "this is your interface, this is who you
are." Every page should feel like an interface. The UI should feel like it
deserves to be there — tesserae, a solid sweep, hairline plates. Never cockpit
chrome, scanlines, tick dials, brackets, a reticle, or a suit overlay.

## One card anatomy

Build on the card-based structure. Every screen uses the same anatomy:

- **Page** — `ForgeScreenStack` + `ForgePageHeader` (Home's greeting is the
  personal exception, still on the same spacing rhythm).
- **Card** — `forgeContentCard`: `ForgeLayout.cardPadding` (24) inside a
  tessera at `Radius.xl`, hairline edge, no wash, no halo. Compact banners
  pass `ForgeLayout.compactCardPadding`.
- **Header** — `ForgeCardHeader` (uppercase eyebrow + optional meta / text
  link). Nested tiles use `forgeWell`, not a second card API.
- **Spacing** — `ForgeLayout` only (`sectionGap` 16, `blockGap` 16,
  `rowGap` 12, `tileGap` 8, `pairGap` 4).

Deleted HUD pieces, duplicate widgets, and pre-rewrite chrome must not
resurface. `scripts/check-legacy-ui.py` (Repo Hygiene) fails if
`HudChrome`, `AriaOrb`, `HomeAuroraBackground`, `forgePlate`, or
`forgeGlassCard` call sites return.

## Signature shapes

- **Tessera** — continuous rounded rectangle at `Radius.lg` (18). Cards, mosaic
  tiles, and plates are tesserae of one picture, not competing widgets.
- **Sweep** — a circular arc with round caps. Readiness and progress are one
  solid band. The arc length is the data.
- **Capsule** — chips, Skip, Got it. The only fully round rectangle.
- **Hairline** — 0.5–0.8 pt stroke. Never brackets, scanlines, tick dials,
  Iron Man / Tony Stark suit chrome, or a HUD overlay.

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
lights one tessera. Readiness is one solid sweep on that picture. Hobbies and
free days count too. Tutorial, Home, and Progress read the same mosaic.

## Interaction patterns

- One primary CTA. Skip always visible on teaching.
- One gesture per tutorial beat, in the real UI, never a blocking modal.
- Conversational ARIA, not a form wall. Optional fields stay skippable.
- 44 pt taps. VoiceOver names the tessera (title, number, fill).
- Coach copy, never diagnosis. Crisis hands off to real resources.

Lockstep: `ForgeDesignLanguage`, `ForgeDS`, `shared/design-tokens.json`.
