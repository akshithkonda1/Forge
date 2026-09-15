"""Contract twin of iOS AriaFirstBond.

SimRunner cannot tap ChatView. This module is the yes/no understanding
check the iOS first conversation uses, so CI fails if that contract drifts.
"""

from __future__ import annotations

from dataclasses import dataclass

YES_NO = ("Yes.", "No.", "Not sure.")
STAY = ("I'm here.", "What did you actually see?", "Not now.")
INVITE = ("How did I sleep?", "What should I train?", "How do I show up?", "I'll come back.")

# Same roster as iOS AriaCoachAgent.rawValue — keep lockstep.
IOS_AGENT_KINDS = (
    "aria", "workout", "recovery", "sleep", "lifestyle", "progress", "cycle",
)

BEATS = (
    "opening", "notDoctor", "health", "notGame", "specialists", "howToAsk", "invite", "done",
)


def parse_answer(raw: str) -> str:
    t = raw.strip()
    lower = t.lower()
    if "come back" in lower or "not now" in lower or "look around" in lower or lower == "later":
        return "leave"
    if "did you see" in lower or "what did you" in lower:
        return "seeHealth"
    if lower in {"i'm here", "i’m here", "i am here", "hi", "hey", "hello", "stay"}:
        return "stay"
    if lower in {
        "yes", "yes.", "yeah", "yep", "yup", "ok", "okay", "okay.", "fair",
        "true", "right", "got it", "works", "agreed",
    }:
        return "yes"
    if lower in {"no", "no.", "nope", "nah", "not really", "wrong", "no thanks"}:
        return "no"
    if "not sure" in lower or lower in {"maybe", "kind of", "kinda"}:
        return "unsure"
    if lower.startswith("yes"):
        return "yes"
    if lower.startswith("no"):
        return "no"
    return "other"


def should_handoff(text: str) -> bool:
    if parse_answer(text) != "other":
        return False
    lower = text.lower()
    needles = (
        "sleep", "slept", "train", "workout", "show up", "period",
        "eat", "hungry", "protein", "tired", "hrv", "sore",
    )
    return any(n in lower for n in needles) or len(text) > 48


@dataclass(frozen=True)
class Turn:
    message: str
    replies: tuple[str, ...]
    next: str

    @property
    def finishes(self) -> bool:
        return self.next == "done"


def start(*, name: str, has_health: bool, goal: str | None, cycle: bool) -> Turn:
    who = name.split()[0] if name.strip() else ""
    hi = f"{who}. I'm ARIA." if who else "Hey. I'm ARIA."
    health = (
        "I just read Apple Health on this phone."
        if has_health else
        "I don't have your Health yet, so I won't pretend I do."
    )
    goal_line = f" You mentioned {goal.lower()}." if goal else ""
    msg = (
        f"{hi} I'm going to be in this tab with you — not a help article, not a quest log. "
        f"{health}{goal_line} Before we go: a few yes-or-no so we're the same person. Stay?"
    )
    return Turn(msg, STAY, "opening")


def advance(beat: str, user_text: str, *, cycle: bool = False) -> Turn:
    answer = parse_answer(user_text)
    if answer == "leave":
        return Turn("I'll be here. This tab is ours.", (), "done")
    if should_handoff(user_text):
        return Turn("", (), "done")
    chain = {
        "opening": ("notDoctor", "I'm a lifestyle coach, not a doctor. Fair?", YES_NO),
        "notDoctor": ("health", "I read Apple Health. I don't invent your night. Work for you?", YES_NO),
        "health": ("notGame", "This isn't a game. No XP for chatting. Okay?", YES_NO),
        "notGame": (
            "specialists",
            (
                "You talk to me. I bring in Train, Recover, Fuel, Life when a question needs them. "
                + ("Cycle too, because you shared that. " if cycle else "Cycle stays out until you share it. ")
                + "Sound right?"
            ),
            YES_NO,
        ),
        "specialists": (
            "howToAsk",
            'Best way to use me: one true sentence. Want to try that?',
            YES_NO,
        ),
        "howToAsk": ("invite", "Ask me something true. Sleep, training, how you show up.", INVITE),
        "invite": ("done", "I'll be here. This tab is ours.", ()),
    }
    nxt, msg, replies = chain.get(beat, ("done", "I'll be here. This tab is ours.", ()))
    if answer == "no" and beat == "notDoctor":
        msg = "I can still help you live the day. I just won't diagnose. " + msg
    return Turn(msg, replies, nxt)
