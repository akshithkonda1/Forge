"""Pin COST.md monthly tables to the scripted arithmetic.

The baseline table (Scout off) and the Scout handoff scenario must stay
in lockstep with the rates and assumptions documented in COST.md. CI
runs this next to the serverless cheap-guard.
"""

from __future__ import annotations

import re
from pathlib import Path

COST_MD = Path(__file__).resolve().parents[1] / "COST.md"

DAYS = 30
HOURS = 730  # AWS on-demand month for always-on compute
API_PER_USER_DAY = 10
CHATS_PER_USER_DAY = 3
ROUTER_PER_USER_DAY = 0.2
CHAT_IN, CHAT_OUT = 1800, 400
ROUTER_IN, ROUTER_OUT = 2500, 400
HANDOFFS_PER_USER = DAYS / 7
PLAN_IN, PLAN_OUT = 150, 100
SYNTH_IN, SYNTH_OUT = 3400, 400
FOLLOW_IN, FOLLOW_OUT = 2000, 400
SCOUT_BOX = HOURS * 0.0168 + HOURS * 0.005 + 16 * 0.08  # t4g.small + EIP + 16 GB gp3

# Sonnet → Grok → Opus → ensemble. Classifier mix, not cheap-vs-strong.
TIER_MIX = (0.88, 0.08, 0.035, 0.005)


def sonnet_cost(n_in: float, n_out: float) -> float:
    return (n_in * 2.0 + n_out * 10.0) / 1e6


def grok_cost(n_in: float, n_out: float) -> float:
    return (n_in * 2.0 + n_out * 6.0) / 1e6


def opus_cost(n_in: float, n_out: float) -> float:
    return (n_in * 5.0 + n_out * 25.0) / 1e6


def tier_cost(tier: int, n_in: float, n_out: float) -> float:
    """Per-request token cost. Tier 4 is three independent drafts plus Sonnet synthesis."""
    t1 = sonnet_cost(n_in, n_out)
    t2 = grok_cost(n_in, n_out)
    t3 = opus_cost(n_in, n_out)
    t4 = t1 + t2 + t3 + t1
    return (t1, t2, t3, t4)[tier - 1]


def suite_token_cost(n_in: float, n_out: float) -> float:
    return sum(share * tier_cost(tier, n_in, n_out) for tier, share in enumerate(TIER_MIX, start=1))


def infra_usage(api_calls: float, dynamo_calls: float) -> float:
    http = api_calls * 1.00 / 1e6
    dynamo = dynamo_calls * 2 * 1.25 / 1e6 + dynamo_calls * 8 * 0.25 / 1e6
    return http + dynamo


def usd(value: float) -> str:
    return f"${value:.2f}"


def baseline(users: int) -> dict[str, float]:
    api = users * API_PER_USER_DAY * DAYS
    chats = users * CHATS_PER_USER_DAY * DAYS
    routers = users * ROUTER_PER_USER_DAY * DAYS
    infra = infra_usage(api, api)
    tokens = chats * suite_token_cost(CHAT_IN, CHAT_OUT) + routers * suite_token_cost(
        ROUTER_IN, ROUTER_OUT
    )
    return {"infra": infra, "tokens": tokens, "off": infra, "on": infra + tokens}


def scout_combined(users: int) -> dict[str, float]:
    base = baseline(users)
    handoffs = users * HANDOFFS_PER_USER
    grok = handoffs * (grok_cost(PLAN_IN, PLAN_OUT) + grok_cost(SYNTH_IN, SYNTH_OUT))
    follow = handoffs * suite_token_cost(FOLLOW_IN, FOLLOW_OUT)
    extra_http = handoffs * 2
    extra_ddb = handoffs
    infra = base["infra"] + SCOUT_BOX + infra_usage(extra_http, extra_ddb)
    tokens = base["tokens"] + grok + follow
    return {
        "handoffs": handoffs,
        "infra": infra,
        "tokens": tokens,
        "off": infra,
        "on": infra + tokens,
        "per_off": round(infra, 2) / users,
        "per_on": (round(infra, 2) + round(tokens, 2)) / users,
    }


def _table_row(text: str, users_label: str) -> list[str]:
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells and cells[0] == users_label:
            return cells
    raise AssertionError(f"no COST.md row for {users_label!r}")


def test_scout_box_matches_documented_seventeen():
    assert round(SCOUT_BOX, 2) == 17.19


def test_per_tier_costs_and_mix():
    chat = [tier_cost(tier, CHAT_IN, CHAT_OUT) for tier in range(1, 5)]
    router = [tier_cost(tier, ROUTER_IN, ROUTER_OUT) for tier in range(1, 5)]
    assert chat == [0.0076, 0.006, 0.019, 0.0402]
    assert router == [0.009, 0.0074, 0.0225, 0.0479]
    assert abs(suite_token_cost(CHAT_IN, CHAT_OUT) - 0.008034) < 1e-12
    assert abs(suite_token_cost(ROUTER_IN, ROUTER_OUT) - 0.009539) < 1e-12
    assert abs(sum(TIER_MIX) - 1.0) < 1e-12
    text = COST_MD.read_text(encoding="utf-8")
    assert "88% / 8% / 3.5% / 0.5%" in text
    assert "$0.0076" in text
    assert "$0.0402" in text


def test_baseline_table_matches_cost_md():
    text = COST_MD.read_text(encoding="utf-8")
    expected = {
        "5": ("$0.01", "$3.90", "**$0.01**", "**$3.91**"),
        "100": ("$0.17", "$78.03", "**$0.17**", "**$78.20**"),
        "1,000": ("$1.65", "$780.29", "**$1.65**", "**$781.94**"),
    }
    users_by_label = {"5": 5, "100": 100, "1,000": 1000}
    for label, cells in expected.items():
        row = _table_row(text, label)
        # Users | API | Chats | Infra | Tokens | Total off | Total on
        got = (row[3], row[4], row[5], row[6])
        assert got == cells, (label, got, cells)
        calc = baseline(users_by_label[label])
        assert usd(calc["infra"]) == cells[0].replace("*", "")
        assert usd(calc["tokens"]) == cells[1].replace("*", "")
        assert usd(round(calc["infra"], 2) + round(calc["tokens"], 2)) == cells[3].replace("*", "")


def test_scout_handoff_table_matches_cost_md():
    text = COST_MD.read_text(encoding="utf-8")
    assert "Short cited digest" in text
    assert "CLIENT_EVIDENCE_CHARS" in text
    assert "global.xai.grok-4.7" in text
    expected = {
        "5": ("21", "$17.20", "$4.30", "**$17.20**", "**$21.50**", "**$3.44**", "**$4.30**"),
        "100": ("429", "$17.36", "$85.99", "**$17.36**", "**$103.35**", "**$0.17**", "**$1.03**"),
        "1,000": ("4,286", "$18.87", "$859.85", "**$18.87**", "**$878.72**", "**$0.02**", "**$0.88**"),
    }
    users_by_label = {"5": 5, "100": 100, "1,000": 1000}
    scout_section = text.split("## Scout handoff scenario", 1)[1]
    for label, cells in expected.items():
        row = _table_row(scout_section, label)
        got = tuple(row[1:])
        assert got == cells, (label, got, cells)
        calc = scout_combined(users_by_label[label])
        assert f"{calc['handoffs']:,.0f}" == cells[0]
        assert usd(calc["infra"]) == cells[1]
        assert usd(calc["tokens"]) == cells[2]
        assert usd(round(calc["infra"], 2) + round(calc["tokens"], 2)) == cells[4].replace("*", "")
        assert usd(calc["per_off"]) == cells[5].replace("*", "")
        assert usd(calc["per_on"]) == cells[6].replace("*", "")


def test_per_handoff_token_line():
    per = grok_cost(PLAN_IN, PLAN_OUT) + grok_cost(SYNTH_IN, SYNTH_OUT) + suite_token_cost(
        FOLLOW_IN, FOLLOW_OUT
    )
    assert abs(per - 0.018564) < 1e-12
    text = COST_MD.read_text(encoding="utf-8")
    assert re.search(r"\$0\.0186", text)
