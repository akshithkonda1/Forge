"""Tests for aria_core.circadian_rhythm, the Python port of ForgeCore's
CircadianRhythm.swift (task #12 of the Swift->Python port list -- see
ARIA_INTELLIGENCE_PLAN.md). Translated directly from
CircadianRhythmTests.swift, checked against the Swift source's own
constants and expected values rather than re-derived from the port.

As the Swift suite's own header puts it: the failure mode of this engine is
not a crash -- it is confidently telling someone their afternoon slump is
at 4am, or that they are eleven hours in debt when they slept fine. Every
test here is aimed at a wrong answer that would look plausible on screen.
"""

from __future__ import annotations

import math
import unittest
from datetime import datetime

import _bootstrap  # noqa: F401

from aria_core import circadian_rhythm as cr  # noqa: E402


def _date(day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(2026, 3, day, hour, minute)


def _night(day: int, onset_hour: int, wake_hour: int, onset_minute: int = 0,
           wake_minute: int = 0, asleep_hours: float | None = None) -> cr.Night:
    """A night starting the evening of `day`, ending the following morning.
    Onset at or after 20:00 belongs to the evening of `day`; anything
    earlier on the clock is already past midnight."""
    onset_day = day if onset_hour >= 12 else day + 1
    onset = _date(onset_day, onset_hour, onset_minute)
    wake = _date(day + 1, wake_hour, wake_minute)
    in_bed = (wake - onset).total_seconds() / 3600.0
    return cr.Night(onset=onset, wake=wake, asleep_hours=in_bed if asleep_hours is None else asleep_hours)


def _regular_nights(onset_hour: int = 23, wake_hour: int = 7, asleep_hours: float = 7.5) -> list[cr.Night]:
    """Fourteen identical nights -- the easiest case to reason about."""
    return [_night(d, onset_hour, wake_hour, asleep_hours=asleep_hours) for d in range(1, 15)]


class ClockArithmeticTests(unittest.TestCase):
    def test_normalized_hour_wraps_negatives(self):
        self.assertAlmostEqual(cr.normalized_hour(-1.5), 22.5, places=4)
        self.assertAlmostEqual(cr.normalized_hour(25), 1, places=4)
        self.assertAlmostEqual(cr.normalized_hour(-26), 22, places=4)
        self.assertAlmostEqual(cr.normalized_hour(0), 0, places=4)

    def test_circular_mean_crosses_midnight(self):
        mean = cr._circular_mean([23.5, 0.5])
        self.assertAlmostEqual(min(mean, 24 - mean), 0, places=2,
                                msg="23:30 and 00:30 must average to midnight, not noon")

    def test_circular_mean_matches_arithmetic_mean_away_from_midnight(self):
        self.assertAlmostEqual(cr._circular_mean([6, 7, 8]), 7, places=2)
        self.assertAlmostEqual(cr._circular_mean([7, 7, 7]), 7, places=2)

    def test_circular_spread_zero_for_identical_grows_with_scatter(self):
        self.assertAlmostEqual(cr.circular_spread([7, 7, 7, 7]), 0, places=2)
        tight = cr.circular_spread([6.5, 7, 7.5])
        loose = cr.circular_spread([4, 7, 11])
        self.assertLess(tight, loose)
        self.assertGreater(tight, 0)

    def test_circular_spread_handles_midnight_straddle(self):
        straddling = cr.circular_spread([23.5, 0, 0.5])
        equivalent = cr.circular_spread([11.5, 12, 12.5])
        self.assertAlmostEqual(straddling, equivalent, places=2)


class SleepNeedTests(unittest.TestCase):
    def test_falls_back_to_default_below_five_nights(self):
        sparse = [_night(d, 23, 7, asleep_hours=5.0) for d in range(1, 5)]
        self.assertEqual(cr.sleep_need_hours(sparse), cr.DEFAULT_SLEEP_NEED_HOURS)

    def test_clamped_to_physiological_range(self):
        marathon = _regular_nights(asleep_hours=13)
        self.assertEqual(cr.sleep_need_hours(marathon), cr.MAX_SLEEP_NEED_HOURS)
        deprived = _regular_nights(asleep_hours=4)
        self.assertEqual(cr.sleep_need_hours(deprived), cr.MIN_SLEEP_NEED_HOURS)

    def test_uses_upper_tail_not_the_mean(self):
        nights = [_night(d, 23, 7, asleep_hours=6.0) for d in range(1, 11)]
        nights += [_night(d, 23, 7, asleep_hours=8.6) for d in range(11, 15)]
        need = cr.sleep_need_hours(nights)
        mean = sum(n.asleep_hours for n in nights) / len(nights)
        self.assertGreater(need, mean, "the mean of a deprived person is their deprivation")
        self.assertAlmostEqual(need, 8.6, places=2)

    def test_ignores_nap_sized_fragments(self):
        nights = _regular_nights(asleep_hours=8.0)
        nights.append(_night(20, 23, 7, asleep_hours=0.4))
        self.assertAlmostEqual(cr.sleep_need_hours(nights), 8.0, places=2)


class SleepDebtTests(unittest.TestCase):
    def test_counts_only_shortfalls(self):
        nights = [
            _night(1, 23, 7, asleep_hours=6.0),   # 2h short
            _night(2, 23, 7, asleep_hours=7.5),   # 0.5h short
            _night(3, 23, 7, asleep_hours=8.0),   # even
        ]
        self.assertAlmostEqual(cr.sleep_debt_hours(nights, need=8.0), 2.5, places=2)

    def test_surplus_sleep_does_not_bank_credit(self):
        nights = [
            _night(1, 22, 10, asleep_hours=11.0),  # 3h over
            _night(2, 23, 7, asleep_hours=6.0),    # 2h short
        ]
        self.assertAlmostEqual(cr.sleep_debt_hours(nights, need=8.0), 2.0, places=2,
                                msg="the surplus night must not cancel the short one")

    def test_debt_window_drops_older_nights(self):
        nights = [_night(d, 23, 7, asleep_hours=7.0) for d in range(1, 21)]
        self.assertAlmostEqual(cr.sleep_debt_hours(nights, need=8.0), 14.0, places=2)

    def test_debt_is_zero_without_nights(self):
        self.assertEqual(cr.sleep_debt_hours([], need=8.0), 0)


class PhaseTests(unittest.TestCase):
    def test_none_without_nights(self):
        self.assertIsNone(cr.phase([]))

    def test_recovers_habitual_wake_and_onset(self):
        p = cr.phase(_regular_nights(onset_hour=23, wake_hour=7))
        self.assertAlmostEqual(p.wake_hour, 7, places=1)
        self.assertAlmostEqual(p.onset_hour, 23, places=1)
        self.assertGreater(p.confidence, 0.95, "identical nights are maximally confident")

    def test_handles_post_midnight_onsets(self):
        nights = [_night(d, 0, 8, onset_minute=30, wake_minute=30) for d in range(1, 15)]
        p = cr.phase(nights)
        self.assertAlmostEqual(p.onset_hour, 0.5, places=1, msg="a 00:30 bedtime is 00:30, not 12:30")
        self.assertAlmostEqual(p.wake_hour, 8.5, places=1)

    def test_erratic_schedule_reports_low_confidence(self):
        steady = cr.phase(_regular_nights())
        wakes = [4, 7, 11, 15, 9, 6, 13]
        scattered = [_night(d, 22, wakes[d % 7], asleep_hours=7) for d in range(1, 15)]
        shift = cr.phase(scattered)
        self.assertLess(shift.confidence, steady.confidence)
        self.assertLess(shift.confidence, 0.5)

    def test_uses_only_the_recent_window(self):
        nights = [_night(d, 2, 10) for d in range(1, 17)]
        nights += [_night(d, 22, 6) for d in range(17, 31)]
        p = cr.phase(nights)
        self.assertAlmostEqual(p.wake_hour, 6, places=1, msg="a schedule change should take effect")


class HoursAwakeTests(unittest.TestCase):
    def test_counts_from_wake_and_decays_overnight(self):
        phase = cr.Phase(wake_hour=7, onset_hour=23, confidence=1)
        self.assertAlmostEqual(cr.hours_awake(7, phase), 0, places=2)
        self.assertAlmostEqual(cr.hours_awake(15, phase), 8, places=2)
        self.assertAlmostEqual(cr.hours_awake(23, phase), 16, places=2)

        early_night = cr.hours_awake(1, phase)
        late_night = cr.hours_awake(5, phase)
        self.assertLess(early_night, 16)
        self.assertLess(late_night, early_night)
        self.assertGreaterEqual(late_night, 0)


class CurveTests(unittest.TestCase):
    def test_afternoon_dip_is_real_and_sits_between_two_peaks(self):
        phase = cr.Phase(wake_hour=7, onset_hour=23, confidence=1)
        waking = [(h, e) for h, e in cr.curve(phase, samples_per_hour=12) if 7 <= h <= 23]

        dip_hour, dip_energy = min((s for s in waking if 12 <= s[0] <= 16), key=lambda s: s[1])
        morning_hour, morning_energy = max((s for s in waking if s[0] < dip_hour), key=lambda s: s[1])
        evening_hour, evening_energy = max((s for s in waking if s[0] > dip_hour), key=lambda s: s[1])

        self.assertLess(dip_energy, morning_energy, "no dip after the morning peak")
        self.assertLess(dip_energy, evening_energy, "no recovery into the evening")
        self.assertGreater(dip_hour, 12.5)
        self.assertLess(dip_hour, 15.5)
        self.assertGreater(evening_hour, 16, "the second wind belongs in the evening")

    def test_dip_tracks_wake_time_for_early_riser_and_night_owl(self):
        def dip_clock_hour(wake: float, onset: float) -> float | None:
            phase = cr.Phase(wake_hour=wake, onset_hour=onset, confidence=1)
            day = sorted(
                ((cr.normalized_hour(h - wake), h, e) for h, e in cr.curve(phase, samples_per_hour=12)),
                key=lambda t: t[0],
            )
            for i in range(1, len(day) - 1):
                offset, hour, energy_ = day[i]
                if not (2 < offset < 12):
                    continue
                if energy_ < day[i - 1][2] and energy_ <= day[i + 1][2]:
                    return hour
            return None

        lark = dip_clock_hour(wake=5, onset=21)
        owl = dip_clock_hour(wake=10, onset=2)
        self.assertIsNotNone(lark)
        self.assertIsNotNone(owl)
        self.assertAlmostEqual(cr.normalized_hour(lark - 5), cr.DIP_HOURS_AFTER_WAKE, delta=0.75)
        self.assertAlmostEqual(cr.normalized_hour(owl - 10), cr.DIP_HOURS_AFTER_WAKE, delta=0.75)
        self.assertNotEqual(lark, owl, "the dip is not a fixed clock hour")

    def test_no_phantom_dip_during_the_sleep_window(self):
        phase = cr.Phase(wake_hour=7, onset_hour=23, confidence=1)
        overnight = [(h, e) for h, e in cr.curve(phase, samples_per_hour=12) if h >= 23 or h <= 5]
        deepest_hour, _ = min(overnight, key=lambda s: s[1])
        self.assertGreater(deepest_hour, 3.0)
        self.assertLessEqual(deepest_hour, 5.0)

    def test_energy_stays_in_unit_range(self):
        wake = 4.0
        while wake <= 11.0:
            phase = cr.Phase(wake_hour=wake, onset_hour=cr.normalized_hour(wake + 16), confidence=1)
            for debt in (0.0, 5.0, 20.0, 100.0):
                for _, e in cr.curve(phase, sleep_debt_hours_=debt):
                    self.assertGreaterEqual(e, 0)
                    self.assertLessEqual(e, 1)
            wake += 0.5

    def test_debt_lowers_the_curve_without_moving_its_peaks(self):
        phase = cr.Phase(wake_hour=7, onset_hour=23, confidence=1)
        rested = cr.curve(phase, sleep_debt_hours_=0, samples_per_hour=12)
        tired = cr.curve(phase, sleep_debt_hours_=12, samples_per_hour=12)

        self.assertEqual(len(rested), len(tired))
        for (hour_a, e_a), (_, e_b) in zip(rested, tired):
            if e_a > 0.25:
                self.assertLess(e_b, e_a, f"debt must cost something at {hour_a}:00")

        rested_peak = max(rested, key=lambda s: s[1])[0]
        tired_peak = max(tired, key=lambda s: s[1])[0]
        self.assertAlmostEqual(rested_peak, tired_peak, delta=0.25, msg="debt moved the day's peak")

    def test_covers_the_day_at_the_requested_resolution(self):
        phase = cr.Phase(wake_hour=7, onset_hour=23, confidence=1)
        self.assertEqual(len(cr.curve(phase, samples_per_hour=4)), 96)
        self.assertEqual(len(cr.curve(phase, samples_per_hour=1)), 24)
        self.assertEqual(len(cr.curve(phase, samples_per_hour=0)), 24)


class WindowTests(unittest.TestCase):
    def test_offsets_hold_for_early_riser_and_night_owl(self):
        lark = cr.Phase(wake_hour=5, onset_hour=21, confidence=1)
        owl = cr.Phase(wake_hour=10, onset_hour=2, confidence=1)
        cases = [
            (0.5, cr.GROGGINESS),
            (3.0, cr.MORNING_PEAK),
            (7.5, cr.AFTERNOON_DIP),
            (11.5, cr.EVENING_PEAK),
            (17.0, cr.SLEEP),
        ]
        for offset, expected in cases:
            self.assertEqual(cr.window(cr.normalized_hour(5 + offset), lark), expected)
            self.assertEqual(cr.window(cr.normalized_hour(10 + offset), owl), expected)

    def test_melatonin_window_leads_sleep_onset(self):
        phase = cr.Phase(wake_hour=7, onset_hour=23, confidence=1)
        self.assertEqual(cr.window(21.5, phase), cr.MELATONIN_WINDOW)
        self.assertEqual(cr.window(22.9, phase), cr.MELATONIN_WINDOW)
        self.assertEqual(cr.window(20.5, phase), cr.WINDING_DOWN)
        self.assertEqual(cr.window(23.5, phase), cr.SLEEP)

    def test_every_hour_resolves_for_every_phase(self):
        wake = 0.0
        while wake < 24.0:
            phase = cr.Phase(wake_hour=wake, onset_hour=cr.normalized_hour(wake + 16), confidence=1)
            hour = 0.0
            while hour < 24.0:
                self.assertIn(cr.window(hour, phase), cr.WINDOWS)
                hour += 0.25
            wake += 0.5

    def test_next_window_is_ahead_and_different(self):
        phase = cr.Phase(wake_hour=7, onset_hour=23, confidence=1)
        hour = 0.0
        while hour < 24.0:
            current = cr.window(hour, phase)
            result = cr.next_window(hour, phase)
            self.assertIsNotNone(result, f"no next window from {hour}:00")
            nxt, starts_in = result
            self.assertNotEqual(nxt, current)
            self.assertGreater(starts_in, 0)
            self.assertLessEqual(starts_in, 24)
            hour += 0.5

    def test_grogginess_follows_sleep_and_is_short_lived(self):
        phase = cr.Phase(wake_hour=7, onset_hour=23, confidence=1)
        self.assertEqual(cr.window(6.9, phase), cr.SLEEP)
        self.assertEqual(cr.window(7.0, phase), cr.GROGGINESS)
        self.assertEqual(cr.window(7.9, phase), cr.GROGGINESS)
        self.assertNotEqual(cr.window(8.1, phase), cr.GROGGINESS,
                             "sleep inertia does not last an hour and a half")

    def test_every_window_has_copy(self):
        for w in cr.WINDOWS:
            self.assertTrue(cr.WINDOW_TITLE[w])
            self.assertTrue(cr.WINDOW_GUIDANCE[w])


class EndToEndTests(unittest.TestCase):
    def test_typical_sleeper_produces_a_coherent_schedule(self):
        nights = _regular_nights(onset_hour=23, wake_hour=7, asleep_hours=7.0)
        need = cr.sleep_need_hours(nights)
        debt = cr.sleep_debt_hours(nights, need=need)
        phase = cr.phase(nights)

        self.assertAlmostEqual(need, 7.0, places=2)
        self.assertAlmostEqual(debt, 0, places=2, msg="sleeping to your own estimated need is not a debt")

        self.assertEqual(cr.window(9, phase), cr.MORNING_PEAK)
        self.assertEqual(cr.window(14.5, phase), cr.AFTERNOON_DIP)
        self.assertEqual(cr.window(3, phase), cr.SLEEP)

    def test_underslept_week_shows_debt_and_costs(self):
        nights = [_night(d, 22, 7, asleep_hours=8.5) for d in range(1, 5)]
        nights += [_night(d, 1, 7, asleep_hours=5.5) for d in range(5, 15)]

        need = cr.sleep_need_hours(nights)
        debt = cr.sleep_debt_hours(nights, need=need)
        self.assertAlmostEqual(need, 8.5, places=2)
        self.assertGreater(debt, 20)

        phase = cr.phase(nights)
        tired = cr.energy(15, phase, cr.hours_awake(15, phase), sleep_debt_hours_=debt, sleep_need_hours_=need)
        rested = cr.energy(15, phase, cr.hours_awake(15, phase), sleep_debt_hours_=0, sleep_need_hours_=need)
        self.assertLess(tired, rested)


class MidSleepAndMelatoninTests(unittest.TestCase):
    def test_mid_sleep_is_the_midpoint_between_onset_and_wake(self):
        n = _night(1, 23, 7)
        self.assertEqual(n.mid_sleep, n.onset + (n.wake - n.onset) / 2)

    def test_melatonin_onset_leads_sleep_onset_by_the_lead_time(self):
        phase = cr.Phase(wake_hour=7, onset_hour=23, confidence=1)
        self.assertAlmostEqual(cr.melatonin_onset_hour(phase), 21.0, places=4)


class SwiftRoundingParityTests(unittest.TestCase):
    """Swift's Double.rounded() rounds half away from zero; Python's round()
    uses banker's rounding. _swift_round must match the Swift rule since
    sleep_need_hours_from_durations relies on it for its percentile index."""

    def test_rounds_half_up_for_positive_values(self):
        self.assertEqual(cr._swift_round(2.5), 3)
        self.assertEqual(cr._swift_round(11.7), 12)
        self.assertEqual(cr._swift_round(0.5), 1)

    def test_rounds_half_away_from_zero_for_negative_values(self):
        self.assertEqual(cr._swift_round(-2.5), -3)


if __name__ == "__main__":
    unittest.main()
