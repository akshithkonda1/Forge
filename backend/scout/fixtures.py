"""Offline Scout corpus — the deterministic stand-in for the open web.

The Scout dummy's ``offline`` mode searches and reads these pages instead of
the network, so tests, CI and SimRunner exercise the full Scout loop (plan →
search → rank → read → cross-check → cited brief) with byte-identical output
on every run.

Every page is a short paraphrase of long-standing public-health guidance at
the real URL it cites. Keep entries conservative: a fixture that overstates
its source would teach the Dummy to overstate too.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from .search import SearchHit


@dataclass(frozen=True)
class FixturePage:
    url: str
    title: str
    topics: tuple[str, ...]
    text: str


PAGES: tuple[FixturePage, ...] = (
    FixturePage(
        url="https://www.cdc.gov/physical-activity-basics/guidelines/adults.html",
        title="CDC: Physical Activity Guidelines for Adults",
        topics=("training", "progress", "readiness"),
        text=(
            "Adults need at least 150 minutes of moderate-intensity physical activity each week. "
            "Adults also need muscle-strengthening activity that works all major muscle groups on at least two days a week. "
            "Some physical activity is better than none, and moving more and sitting less benefits nearly everyone."
        ),
    ),
    FixturePage(
        url="https://medlineplus.gov/exerciseandphysicalfitness.html",
        title="MedlinePlus: Exercise and Physical Fitness",
        topics=("training", "readiness", "lifestyle"),
        text=(
            "Regular physical activity is one of the most important things you can do for your health. "
            "If you have been inactive, start slowly and build up your activity over time. "
            "Strength training, endurance exercise, balance and flexibility each play a different role in fitness."
        ),
    ),
    FixturePage(
        url="https://www.cdc.gov/sleep/about/index.html",
        title="CDC: About Sleep",
        topics=("sleep", "readiness"),
        text=(
            "Most adults need seven or more hours of sleep each night for good health. "
            "Not getting enough sleep is linked with many chronic health problems and can affect how you think, react and feel. "
            "Keeping a consistent sleep schedule, even on weekends, supports better sleep."
        ),
    ),
    FixturePage(
        url="https://www.nhlbi.nih.gov/health/sleep-deprivation",
        title="NHLBI: Sleep Deprivation and Deficiency",
        topics=("sleep", "readiness"),
        text=(
            "Sleep deficiency means not getting enough sleep, sleeping at the wrong time of day, or not sleeping well. "
            "Sleep deficiency can make it harder to focus, learn and react, and it is linked to a higher risk of injury. "
            "Adults generally need seven or more hours of sleep each night to stay healthy."
        ),
    ),
    FixturePage(
        url="https://ods.od.nih.gov/factsheets/Protein-Consumer/",
        title="NIH Office of Dietary Supplements: Protein",
        topics=("nutrition",),
        text=(
            "Protein is found in foods such as meat, poultry, seafood, eggs, dairy, beans, nuts, seeds and soy products. "
            "The recommended dietary allowance of protein for most adults is about 0.8 grams per kilogram of body weight per day. "
            "Most people in the United States get enough protein from the foods they eat."
        ),
    ),
    FixturePage(
        url="https://medlineplus.gov/fluidandelectrolytebalance.html",
        title="MedlinePlus: Fluid and Electrolyte Balance",
        topics=("nutrition", "heat"),
        text=(
            "Electrolytes are minerals in your body that have an electric charge and help keep fluid levels balanced. "
            "You can lose fluids and electrolytes through heavy sweating, vomiting or diarrhea. "
            "Drinking enough fluids helps keep your body's fluid and electrolyte balance in check."
        ),
    ),
    FixturePage(
        url="https://medlineplus.gov/fever.html",
        title="MedlinePlus: Fever",
        topics=("fever",),
        text=(
            "A fever is a body temperature that is higher than normal and is often a sign that your body is fighting an infection. "
            "Rest and drinking plenty of fluids help when you have a fever. "
            "Contact a health care provider for a very high fever, a fever that lasts more than a few days, or a fever with severe symptoms."
        ),
    ),
    FixturePage(
        url="https://www.cdc.gov/flu/treatment/caring-for-someone.html",
        title="CDC: Caring for Someone Sick at Home",
        topics=("fever",),
        text=(
            "A person with a fever should rest and drink plenty of fluids to prevent dehydration. "
            "Stay home when you are sick to avoid spreading illness to others. "
            "Watch for emergency warning signs such as difficulty breathing or chest pain and seek care right away if they appear."
        ),
    ),
    FixturePage(
        url="https://medlineplus.gov/heatillness.html",
        title="MedlinePlus: Heat Illness",
        topics=("heat",),
        text=(
            "During hot weather, especially with high humidity, sweating is not always enough to cool the body. "
            "Heat exhaustion can cause heavy sweating, weakness, dizziness and nausea, and heat stroke is a medical emergency. "
            "Drink plenty of fluids and limit strenuous activity during the hottest part of the day."
        ),
    ),
    FixturePage(
        url="https://www.airnow.gov/aqi/aqi-basics/",
        title="AirNow: Air Quality Index Basics",
        topics=("heat", "lifestyle"),
        text=(
            "The Air Quality Index tells you how clean or polluted the outdoor air is. "
            "When the air quality is unhealthy, reduce prolonged or heavy exertion outdoors. "
            "Sensitive groups, including people with heart or lung disease, should take extra care on poor air days."
        ),
    ),
    FixturePage(
        url="https://www.womenshealth.gov/menstrual-cycle",
        title="OASH: Your Menstrual Cycle",
        topics=("cycle",),
        text=(
            "The average menstrual cycle is about 28 days long, and cycles between 21 and 35 days are common in adults. "
            "Periods usually last between two and seven days. "
            "Talk to a doctor if your periods suddenly change, become very heavy, or stop for several months."
        ),
    ),
    FixturePage(
        url="https://medlineplus.gov/stress.html",
        title="MedlinePlus: Stress",
        topics=("lifestyle", "readiness"),
        text=(
            "Stress is a feeling of emotional or physical tension, and long-term stress can affect your health. "
            "Regular physical activity, enough sleep and relaxation techniques can help you manage stress. "
            "Reach out to a health care provider if stress feels overwhelming or does not ease."
        ),
    ),
    FixturePage(
        url="https://www.fda.gov/consumers/consumer-updates/spilling-beans-how-much-caffeine-too-much",
        title="FDA: How Much Caffeine Is Too Much?",
        topics=("nutrition", "sleep"),
        text=(
            "For healthy adults, the FDA has cited 400 milligrams of caffeine a day as an amount not generally associated with negative effects. "
            "People vary widely in how sensitive they are to caffeine and how fast they process it. "
            "Too much caffeine can cause trouble sleeping, jitters, anxiety and a fast heart rate."
        ),
    ),
)

_WORD = re.compile(r"[a-z][a-z0-9-]+")
_STOP = frozenset(
    "the and for with that this from are was were have has not you your can will how what does "
    "much many more need needs should get about too".split()
)


def _words(text: str) -> set[str]:
    return {w for w in _WORD.findall(text.lower()) if w not in _STOP and len(w) > 2}


class FixtureSearcher:
    """Deterministic search over ``PAGES``: keyword overlap, topic as tiebreak."""

    def __init__(self, topic: str = "", pages: tuple[FixturePage, ...] = PAGES) -> None:
        self.topic = topic
        self.pages = pages

    def search(self, query: str, *, timeout: float = 0) -> list[SearchHit]:
        want = _words(query)
        if not want:
            return []
        scored: list[tuple[int, int, int, FixturePage]] = []
        for order, page in enumerate(self.pages):
            overlap = len(want & _words(f"{page.title} {page.text} {' '.join(page.topics)}"))
            on_topic = 1 if self.topic and self.topic in page.topics else 0
            if overlap == 0 and not on_topic:
                continue
            scored.append((overlap, on_topic, -order, page))
        scored.sort(key=lambda row: (row[0], row[1], row[2]), reverse=True)
        return [
            SearchHit(url=p.url, title=p.title, snippet=p.text, engines=["offline"], query=query)
            for _o, _t, _r, p in scored[:6]
        ]


def fixture_fetch(url: str) -> tuple[str, str, str]:
    for page in PAGES:
        if page.url == url:
            return page.url, page.title, page.text
    raise LookupError(url)
