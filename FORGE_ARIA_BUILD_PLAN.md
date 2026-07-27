# Forge × ARIA — Complete Build Plan

**Goal:** Build the most advanced health-based conversational intelligence interface on Earth.

**Core Principle:**  
**Forge is powered by Aria** — a high-level contextual engine that gathers data, builds deep understanding of the user, reasons intelligently, and helps proactively through an exceptional iOS experience.

---

## Build Philosophy

Aria is not a chatbot.  
It is a **contextual intelligence engine** that:

- Maintains a living model of the user (lifestyle, patterns, goals, constraints, recovery state)
- Reasons over that context + real-time data
- Delivers personalized, adaptive help
- Learns and improves from every interaction

We are building the **engine first**, then connecting the beautiful interface.

---

## Build Order (Strict)

We follow this specific sequence:

1. **Layers 2 → 5** (Core Engine in Python)
2. **Layer 6** (Polish & Magic in Swift)
3. **Layer 1** (The Bridge — API + Client) — Done last

This ensures the intelligence exists before we wire the UI to it.

> **Implementation note:** Frontend scaffolding (Layer 6 + Swift bridge types) may land first to define contracts; Python engine follows immediately.

---

## Layer Definitions & Implementation

### Layer 2: Persistent Context Engine (Python)

**File:** `backend/app/ai/services/coach_context.py`

`CoachContextEngine` + `UserContext` — persistent lifestyle/goals/patterns/relationship model in DynamoDB.

### Layer 3: Feedback & Learning Loop

**File:** `backend/app/ai/services/feedback.py`

`FeedbackEngine` — reactions and plan outcomes update relationship level and insights.

### Layer 4: Rich Structured Responses

**File:** `backend/app/ai/routes/chat.py`

`POST /ai/chat` → `AriaResponse` with message, rich_card, suggested_actions, context_updates.

### Layer 5: Proactivity & Relationship

`CoachContextEngine.should_be_proactive()` — relationship_level ≥ 3 + recent patterns.

### Layer 6: Polish & Magic (Swift)

- Long-press ARIA avatar → `ContextInspectorView`
- Memory references in high-confidence responses
- Relationship level in chat header
- `ProactiveCardView` on Home / Chat entry

### Layer 1: The Bridge

**Python:** `backend/app/ai/routes/chat.py`  
**Swift:** `ForgeSwift/Services/AriaService.swift`

---

## Folder Structure

### Backend (Python)

```
backend/app/ai/
├── routes/
│   ├── chat.py
│   └── feedback.py
├── services/
│   ├── coach_context.py
│   └── feedback.py
├── storage/
│   ├── dynamodb.py
│   └── s3.py
└── models/
    └── context.py
```

### Frontend (Swift)

```
ForgeSwift/
├── Services/
│   ├── AriaService.swift
│   ├── AriaContextStore.swift
│   └── FeedbackService.swift
├── Models/
│   ├── AriaContext.swift
│   └── AriaResponse.swift
└── Views/Chat/
    ├── ChatView.swift
    ├── ContextInspectorView.swift
    └── ProactiveCardView.swift
```

---

## Next Steps

1. ✅ Live Bedrock/Claude reasoning — `services/aria_engine.generate_response_live` overlays a real Claude (Bedrock Converse) call on the deterministic engine, opt-in via `ARIA_BEDROCK_ENABLED`, with automatic fallback to the deterministic envelope on any failure
2. ✅ Wire `ChatView` → `AriaService` with offline fallback — `ChatView.sendMessage` → `AppStore.sendMessage` → `AriaService.sendMessage(localGenerator:)`. Header shows ⚡ Local badge when `isLocalFallback == true`.
3. ✅ Ship Context Inspector + Proactive cards — `ContextInspectorView` on avatar long-press; `ProactiveCardView` in ChatView + HomeView; memory reference pill rendered above high-confidence trainer bubbles; relationship level in chat header.
4. ✅ Connect feedback loop end-to-end — reactions wired `MessageBubbleView` → `FeedbackService.processReaction`; plan outcomes wired `AppStore.endWorkout` → `FeedbackService.processPlanOutcome`; `backend/app/ai/routes/feedback.py` created per folder spec.

---

**Forge isn't just using AI. Forge is Aria.**