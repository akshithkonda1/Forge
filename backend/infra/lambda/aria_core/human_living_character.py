"""Living-character tags Dummy / plan / habit paths can read without a model.

Python port of ForgeCore's ``HumanLivingCharacter.swift`` (closed chips +
copy). Persistence stays on the client.
"""

from __future__ import annotations

MOVEMENT_TITLE = {"cardio": "Cardio", "strength": "Strength", "mix": "A mix"}
EATING_TITLE = {"light": "Light eater", "moderate": "Moderate", "heavy": "I eat a lot"}
HOBBY_TITLE = {
    "outdoors": "Being outside",
    "gym": "The gym",
    "cooking": "Cooking",
    "making": "Making things",
    "music": "Music",
    "reading": "Reading",
    "games": "Games",
    "rest": "Resting at home",
}

ARCHETYPE_TITLE = {
    "athlete": "Athlete",
    "builder": "Builder",
    "caretaker": "Caretaker",
    "explorer": "Explorer",
    "thinker": "Thinker",
    "balanced": "Balanced",
    "unset": "Unset",
}


def living_tags(
    *,
    archetype: str | None = None,
    nutrition_relationship: str | None = None,
    eating_rhythm: str | None = None,
    movement_preference: str | None = None,
    hobbies: list[str] | None = None,
    sleep_need_preference_hours: float | None = None,
) -> list[str]:
    tags: list[str] = []
    if archetype and archetype != "unset":
        tags.append(f"living:archetype:{archetype}")
    food = (nutrition_relationship or "").strip()
    if food:
        tags.append(f"living:eat:{food.lower()}")
    if eating_rhythm:
        tags.append(f"living:volume:{eating_rhythm}")
    if movement_preference:
        tags.append(f"living:move:{movement_preference}")
    for hobby in (hobbies or [])[:4]:
        tags.append(f"living:hobby:{hobby}")
    if sleep_need_preference_hours is not None:
        tags.append(f"living:sleep_need:{sleep_need_preference_hours:.1f}")
    return tags


def character_line(
    *,
    archetype: str | None = None,
    nutrition_relationship: str | None = None,
    eating_rhythm: str | None = None,
    movement_preference: str | None = None,
    hobbies: list[str] | None = None,
    sleep_need_preference_hours: float | None = None,
) -> str:
    parts: list[str] = []
    if archetype and archetype != "unset":
        title = ARCHETYPE_TITLE.get(archetype, archetype).lower()
        parts.append(f"You live like a {title}.")
    if movement_preference and movement_preference != "mix":
        parts.append(f"You typically like {MOVEMENT_TITLE.get(movement_preference, movement_preference).lower()}.")
    elif movement_preference == "mix":
        parts.append("You like a mix of cardio and strength.")
    hobby_titles = [HOBBY_TITLE.get(h, h).lower() for h in (hobbies or [])[:3]]
    if hobby_titles:
        parts.append("Free days: " + ", ".join(hobby_titles) + ".")
    food = (nutrition_relationship or "").strip()
    if food:
        food_bit = f"Food is {food}"
        if eating_rhythm:
            food_bit += f", {EATING_TITLE.get(eating_rhythm, eating_rhythm).lower()}"
        parts.append(food_bit + ".")
    elif eating_rhythm:
        parts.append(EATING_TITLE.get(eating_rhythm, eating_rhythm) + ".")
    if sleep_need_preference_hours is not None:
        parts.append(f"Sleep want about {sleep_need_preference_hours:.1f} hours.")
    parts.append("I keep this on-device so I don't have to ask the model who you are.")
    return " ".join(parts)


def living_decision_note(tags: list[str]) -> str | None:
    move = None
    for tag in tags:
        if tag.startswith("living:move:"):
            move = tag[len("living:move:"):]
            break
    hobbies = []
    for tag in tags:
        if tag.startswith("living:hobby:"):
            raw = tag[len("living:hobby:"):]
            hobbies.append(HOBBY_TITLE.get(raw, raw).lower())
    bits: list[str] = []
    if move and move != "mix" and move in MOVEMENT_TITLE:
        bits.append(f"You like {MOVEMENT_TITLE[move].lower()}")
    if hobbies:
        if len(hobbies) > 1:
            bits.append(f"free days lean {hobbies[0]} and {hobbies[1]}")
        else:
            bits.append(f"free days lean {hobbies[0]}")
    if not bits:
        return None
    return "; ".join(bits) + " — pulled from your local profile."
