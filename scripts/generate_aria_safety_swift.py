#!/usr/bin/env python3
"""Generate ForgeCore's ARIA safety lexicon from ``guidance.py``.

``backend/infra/lambda/aria_core/guidance.py`` is the one safety classifier:
emergencies, voice-first triage, refer-out, and the relationship-aware
check-in. The phone decides the same turns offline (Dummy, Local testing, and
the no-network fallback), so its needles, patterns, and copy must be the same
words — not a hand-kept copy that drifts. This script writes them into
``ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/AriaSafetyLexicon.swift``;
``AriaSafetyTriage.swift`` mirrors the control flow, and both Python and Swift
assert ``shared/aria-safety-corpus.json`` row for row.

Usage:

    scripts/generate_aria_safety_swift.py          # rewrite the Swift file
    scripts/generate_aria_safety_swift.py --check  # CI: fail if it is stale

Python ``re.VERBOSE`` patterns are compacted (unescaped whitespace outside a
character class removed) so ICU's ``NSRegularExpression`` reads them without
free-spacing mode.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LAMBDA = REPO / "backend" / "infra" / "lambda"
OUTPUT = (
    REPO
    / "ForgeSwift"
    / "ForgeCore"
    / "Sources"
    / "ForgeCore"
    / "Intelligence"
    / "AriaSafetyLexicon.swift"
)

sys.path.insert(0, str(LAMBDA))
from aria_core import guidance as g  # noqa: E402

NEEDLES = {
    "selfHarm": g._SELF_HARM,
    "escalationRequest": g._ESCALATION_REQUEST,
    "emergencyState": g._EMERGENCY_STATE,
    "chestMarkers": g._CHEST_MARKERS,
    "severeChest": g._SEVERE_CHEST,
    "chestCompanions": g._CHEST_COMPANIONS,
    "strokeStandalone": g._STROKE_STANDALONE,
    "liftChestContext": g._LIFT_CHEST_CONTEXT,
    "liftSoreness": g._LIFT_SORENESS,
    "liftNotSoreness": g._LIFT_NOT_SORENESS,
    "syncopeStandalone": g._SYNCOPE_STANDALONE,
    "notBreathing": g._NOT_BREATHING,
    "unresponsive": g._UNRESPONSIVE,
    "noCirculation": g._NO_CIRCULATION,
    "allergyEmergency": g._ALLERGY_EMERGENCY,
    "howtoCues": g._HOWTO_CUES,
    "firstAidTopics": g._FIRST_AID_TOPICS,
    "directDiagnosis": g._DIRECT_DIAGNOSIS,
    "diagnosisAsk": g._DIAGNOSIS_ASK,
    "conditionTerms": g._CONDITION_TERMS,
    "directMed": g._DIRECT_MED,
    "takeCues": g._TAKE_CUES,
    "symptomTerms": g._SYMPTOM_TERMS,
    "medTerms": g._MED_TERMS,
    "eatingDisorder": g._EATING_DISORDER,
    "helperPerson": g._HELPER_PERSON,
    "sleepRefer": g._SLEEP_REFER,
    "youngChildCues": g._YOUNG_CHILD_CUES,
    "faintCues": g._FAINT_CUES,
    "chestCleared": g._CHEST_CLEARED,
    "chestMskCues": g._CHEST_MSK_CUES,
    "recurringCues": g._RECURRING_CUES,
    "woundNeedsLookCues": g._WOUND_NEEDS_LOOK_CUES,
    "negators": tuple(sorted(g._NEGATORS)),
    "seizureWords": ("seizure", "convulsing"),
    "overdoseWords": ("overdosed", "overdosing"),
    "heartAttack": ("heart attack",),
    "havingAStroke": ("having a stroke",),
    "jawWord": ("jaw",),
    "jawPain": ("ache", "aches", "aching", "pain", "hurt", "hurts", "numb"),
    "firstAidBurnWords": g._FIRST_AID_BURN_WORDS,
    "triageTopics": g.TRIAGE_TOPICS,
}

PATTERNS = {
    "selfHarm": g._SELF_HARM_RE,
    "hurtSelf": g._HURT_SELF_RE,
    "hurtSelfInjury": g._HURT_SELF_INJURY_RE,
    "cantTalkRight": g._CANT_TALK_RIGHT_RE,
    "oneSidedDeficit": g._ONE_SIDED_DEFICIT_RE,
    "allergyCombo": g._ALLERGY_COMBO_RE,
    "bleeding": g._BLEEDING_RE,
    "bleedingTriage": g._BLEEDING_TRIAGE_RE,
    "choking": g._CHOKING_RE,
    "headInjury": g._HEAD_INJURY_RE,
    "headInjuryRedFlag": g._HEAD_INJURY_RED_FLAG_RE,
    "ingestionMed": g._INGESTION_MED_RE,
    "ingestionToxin": g._INGESTION_TOXIN_RE,
    "childIngestion": g._CHILD_INGESTION_RE,
    "poisoned": g._POISONED_RE,
    "ingestionIntent": g._INGESTION_INTENT_RE,
    "ingestionDanger": g._INGESTION_DANGER_RE,
    "helperPronoun": g._HELPER_PRONOUN_RE,
    "firstPerson": g._FIRST_PERSON_RE,
    "yesLead": g._YES_LEAD_RE,
    "noLead": g._NO_LEAD_RE,
    "clauseBreak": g._CLAUSE_BREAK_RE,
    "triageCardiacCue": g._TRIAGE_CARDIAC_CUE_RE,
    "triageIntentCue": g._TRIAGE_INTENT_CUE_RE,
}

COPY = {
    "emergencyOpen": g._EMERGENCY_OPEN,
    "emergencyCpr": g._EMERGENCY_CPR,
    "emergencyCprIfNeeded": g._EMERGENCY_CPR_IF_NEEDED,
    "cardiac": g._EMERGENCY_CARDIAC,
    "cardiacHelper": g._EMERGENCY_CARDIAC_HELPER,
    "stroke": g._EMERGENCY_STROKE,
    "strokeHelper": g._EMERGENCY_STROKE_HELPER,
    "faint": g._EMERGENCY_FAINT,
    "faintHelper": g._EMERGENCY_FAINT_HELPER,
    "patientFallback": g._EMERGENCY_PATIENT_FALLBACK,
    "choking": g._EMERGENCY_CHOKING,
    "chokingHelper": g._EMERGENCY_CHOKING_HELPER,
    "bleeding": g._EMERGENCY_BLEEDING,
    "bleedingHelper": g._EMERGENCY_BLEEDING_HELPER,
    "allergy": g._EMERGENCY_ALLERGY,
    "allergyHelper": g._EMERGENCY_ALLERGY_HELPER,
    "seizureHelper": g._EMERGENCY_SEIZURE_HELPER,
    "head": g._EMERGENCY_HEAD,
    "headHelper": g._EMERGENCY_HEAD_HELPER,
    "ingestion": g._EMERGENCY_INGESTION,
    "ingestionHelper": g._EMERGENCY_INGESTION_HELPER,
    "ingestionIntent": g._EMERGENCY_INGESTION_INTENT,
    "crisisLine": g._CRISIS_LINE,
    "boundaryInfo": g._BOUNDARY_INFO,
    "diagnosisReferOpen": g._DIAGNOSIS_REFER_OPEN,
    "medicationRefer": g._MEDICATION_REFER,
    "eatingDisorderRefer": g._EATING_DISORDER_REFER,
    "chestClearedRefer": g._CHEST_CLEARED_REFER,
}


def compact_verbose(pattern: str) -> str:
    """Drop re.VERBOSE whitespace and comments outside character classes."""
    out: list[str] = []
    in_class = False
    escaped = False
    in_comment = False
    for ch in pattern:
        if in_comment:
            if ch == "\n":
                in_comment = False
            continue
        if escaped:
            out.append(ch)
            escaped = False
            continue
        if ch == "\\":
            out.append(ch)
            escaped = True
            continue
        if in_class:
            out.append(ch)
            if ch == "]":
                in_class = False
            continue
        if ch == "[":
            in_class = True
            out.append(ch)
            continue
        if ch == "#":
            in_comment = True
            continue
        if ch.isspace():
            continue
        out.append(ch)
    return "".join(out)


def pattern_source(compiled: re.Pattern[str]) -> str:
    source = compiled.pattern
    if compiled.flags & re.VERBOSE:
        source = compact_verbose(source)
        # Prove the compaction is the same regex before shipping it.
        plain = re.compile(source)
        for probe in ("her face", "he's having", "she took", "they said my chest pain"):
            assert bool(plain.search(probe)) == bool(compiled.search(probe)), probe
    if '"#' in source:
        raise SystemExit(f"pattern cannot be a Swift raw string: {source!r}")
    return source


def swift_string(text: str) -> str:
    escaped = (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )
    return f'"{escaped}"'


def swift_raw(text: str) -> str:
    return f'#"{text}"#'


def swift_array(values, indent: str = "        ") -> str:
    if not values:
        return "[]"
    body = ",\n".join(f"{indent}{swift_string(v)}" for v in values)
    return f"[\n{body},\n{indent[:-4]}]"


def render() -> str:
    lines: list[str] = [
        "// GENERATED by scripts/generate_aria_safety_swift.py from",
        "// backend/infra/lambda/aria_core/guidance.py. Do not edit by hand:",
        "// change guidance.py, then run the script. CI runs it with --check.",
        "",
        "import Foundation",
        "",
        "/// Needles, patterns, and copy for `AriaSafetyTriage` — the same words",
        "/// the backend's one safety classifier uses.",
        "enum AriaSafetyLexicon {",
        "",
        "    // MARK: Needles (substring, lowercased input)",
        "",
    ]
    for name, values in NEEDLES.items():
        lines.append(f"    static let {name}: [String] = {swift_array(list(values))}")
        lines.append("")
    lines.append("    /// Smart punctuation folded to the straight form every needle uses.")
    lines.append("    static let quoteFolds: [String: String] = [")
    for src, dst in g.QUOTE_FOLDS.items():
        lines.append(f"        {swift_string(src)}: {swift_string(dst)},")
    lines.append("    ]")
    lines.append("")
    lines.append("    // MARK: Patterns (NSRegularExpression, lowercased input)")
    lines.append("")
    for name, compiled in PATTERNS.items():
        lines.append(f"    static let {name}Pattern = {swift_raw(pattern_source(compiled))}")
    lines.append("")
    lines.append("    static let strokeDomainPatterns: [String] = [")
    for compiled in g._STROKE_DOMAINS:
        lines.append(f"        {swift_raw(pattern_source(compiled))},")
    lines.append("    ]")
    lines.append("")
    lines.append("    static let triageDangerPatterns: [String: String] = [")
    for topic, compiled in g._TRIAGE_DANGER.items():
        lines.append(f"        {swift_string(topic)}: {swift_raw(pattern_source(compiled))},")
    lines.append("    ]")
    lines.append("")
    lines.append("    /// Every pattern above, so a test can prove each one compiles in ICU —")
    lines.append("    /// `try? NSRegularExpression` would otherwise turn a bad one into a")
    lines.append("    /// silent miss on a 911 turn.")
    lines.append("    static let allPatterns: [String] = [")
    for name in PATTERNS:
        lines.append(f"        {name}Pattern,")
    lines.append("    ] + strokeDomainPatterns + Array(triageDangerPatterns.values)")
    lines.append("")
    lines.append("    // MARK: Copy")
    lines.append("")
    for name, text in COPY.items():
        lines.append(f"    static let {name} = {swift_string(text)}")
    lines.append("")
    lines.append("    /// Ordered (topic, substring cues); burn words are whole-word.")
    lines.append("    static let firstAidTopicCues: [(topic: String, cues: [String])] = [")
    for topic, cues in g._FIRST_AID_TOPIC_CUES:
        values = ", ".join(swift_string(c) for c in cues)
        lines.append(f"        (topic: {swift_string(topic)}, cues: [{values}]),")
    lines.append("    ]")
    lines.append("")
    lines.append("    static let firstAidSteps: [String: String] = [")
    for key, text in g._FIRST_AID_STEPS.items():
        lines.append(f"        {swift_string(key)}: {swift_string(text)},")
    lines.append("    ]")
    lines.append("")
    lines.append("    /// \"topic.subject\" -> (lead, questions, net).")
    lines.append("    static let triageCopy: [String: (lead: String, questions: [String], net: String)] = [")
    for (topic, subject), (lead, questions, net) in g._TRIAGE_COPY.items():
        qs = ", ".join(swift_string(q) for q in questions)
        lines.append(
            f"        {swift_string(f'{topic}.{subject}')}: "
            f"(lead: {swift_string(lead)}, questions: [{qs}], net: {swift_string(net)}),"
        )
    lines.append("    ]")
    lines.append("")
    lines.append("    /// \"topic.subject.band\" -> resolution copy.")
    lines.append("    static let triageResolution: [String: String] = [")
    for (topic, subject, band), text in g._TRIAGE_RESOLUTION.items():
        lines.append(f"        {swift_string(f'{topic}.{subject}.{band}')}: {swift_string(text)},")
    lines.append("    ]")
    lines.append("")
    lines.append("    /// \"kind.subject\" -> [new, familiar, bond] check-in lines.")
    lines.append("    static let checkIn: [String: [String]] = [")
    for (kind, subject), tiers in g._CHECK_IN.items():
        values = ", ".join(swift_string(t) for t in tiers)
        lines.append(f"        {swift_string(f'{kind}.{subject}')}: [{values}],")
    lines.append("    ]")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if the committed Swift file is stale")
    args = parser.parse_args(argv)
    text = render()
    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != text:
            print(
                f"{OUTPUT.relative_to(REPO)} is stale. Run scripts/generate_aria_safety_swift.py",
                file=sys.stderr,
            )
            return 1
        print(f"{OUTPUT.relative_to(REPO)} matches guidance.py")
        return 0
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
