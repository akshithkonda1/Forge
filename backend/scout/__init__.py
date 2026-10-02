"""ARIA Scout — the agentic, always-on research computer ARIA calls when a
turn needs the open web.

Scout runs on one small EC2 instance next to a self-hosted SearXNG
(Google, Bing, DuckDuckGo, Brave, Wikipedia … in one metasearch). A turn
comes in as a scrubbed topic query, never the user's message. Scout plans
searches, reads the best pages through the same SSRF-safe fetcher as
``POST /ingest/url``, cross-checks them, and returns a short cited brief.

The brain is Grok on Amazon Bedrock (``SCOUT_MODEL_ID``) behind the same
``ARIA_BEDROCK_ENABLED`` kill-switch as ``ai_router``. With Bedrock off or
failing, a deterministic rules brain answers instead — extractive, cited,
never invented.

Scout never receives health samples, names, numbers, or coordinates. What
it returns is untrusted outside data: callers must never fold it into
sleep / training / nutrition fields or durable memory.
"""
