"""Nyx Dummy hypertune FAIL GATES.

Light, deterministic gates. Dummy/offline default. Bedrock stays off.
A gate is only useful if it (1) fails on a known-bad fixture and (2) passes
on Dummy speak / vault notes the product actually produces.
"""

from __future__ import annotations

import ast
import os
import pathlib
import unittest
from unittest.mock import patch

from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy
from backend.ai.simrunner.aria_simrunner import nyx_eval_gates as nyx
from backend.ai.simrunner.aria_simrunner import speak_quality as sq
from backend.ai.simrunner.aria_simrunner import web_research


_WAKE_SPEAK_SWIFT = (
    "ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/SleepStoryEngine.swift",
    "ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/SleepWakeAdaptation.swift",
    "ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/SleepDepthScorer.swift",
    "ForgeSwift/ForgeSwift/SleepModels.swift",
    "ForgeSwift/ForgeSwift/SleepWakeUpTab.swift",
    "ForgeSwift/ForgeSwift/SleepAlarmTab.swift",
)


class RetrievalProvenanceGates(unittest.TestCase):
    """Vault / editable-memory retrieve must carry source id; speak cannot cite a hole."""

    def test_retrieved_fact_without_source_or_id_fails(self):
        self.assertTrue(
            nyx.retrieved_fact_provenance_failures(
                [{"id": "note-1", "summary": "earlier nights", "source": ""}]
            )
        )
        self.assertTrue(
            nyx.retrieved_fact_provenance_failures(
                [{"summary": "earlier nights", "source": "user"}]
            )
        )
        self.assertEqual(
            nyx.retrieved_fact_provenance_failures(
                [{"id": "note-1", "summary": "earlier nights", "source": "user"}]
            ),
            [],
        )
        self.assertEqual(
            nyx.retrieved_fact_provenance_failures(
                [{"id": "hk-1", "summary": "Last night: 7.6 hours of sleep.", "source_id": "apple-health"}]
            ),
            [],
        )

    def test_speak_citing_memory_without_a_retrievable_note_fails(self):
        hole = "I remember you hate mornings — keep today kind."
        self.assertTrue(nyx.memory_cite_without_note_failures(hole, []))
        self.assertTrue(
            nyx.memory_cite_without_note_failures(
                hole,
                [{"id": "", "source": "", "summary": "you hate mornings"}],
            )
        )
        self.assertEqual(
            nyx.memory_cite_without_note_failures(
                hole,
                [{"id": "n1", "source": "user", "summary": "you hate mornings"}],
            ),
            [],
        )
        friend = "Yeah — about that night, keep today kind."
        self.assertEqual(nyx.memory_cite_without_note_failures(friend, []), [])

    @unittest.skip("owned by #352")
    def test_dummy_web_retrieve_keeps_from_source_label(self):
        with patch.object(web_research, "look_up", return_value="From Some Source: real info.") as look:
            row = dummy.respond("how do I improve my workout routine?", seed=1, engine="stub")
        look.assert_called_once()
        self.assertEqual(nyx.web_cite_provenance_failures("From Some Source: real info."), [])
        self.assertIn("From Some Source", sq.user_visible_blob(row))
        self.assertEqual(sq.speak_failures(row), [])

    def test_dummy_sleep_speak_does_not_cite_a_missing_vault_note(self):
        row = dummy.respond("How did I sleep last night?", seed=11, engine="stub")
        blob = sq.user_visible_blob(row)
        self.assertEqual(nyx.memory_cite_without_note_failures(blob, []), [], blob)


class ProviderNoSpendGates(unittest.TestCase):
    """Dummy/offline must not call Bedrock / generate_response_live / InvokeModel."""

    def setUp(self):
        self._env = os.environ.get("ENVIRONMENT")
        os.environ.pop("ENVIRONMENT", None)

    def tearDown(self):
        if self._env is None:
            os.environ.pop("ENVIRONMENT", None)
        else:
            os.environ["ENVIRONMENT"] = self._env

    def test_dummy_source_does_not_call_live_or_invoke_model(self):
        owned = (
            pathlib.Path(dummy.__file__),
            pathlib.Path(dummy.voice_diagnostics.__file__),
        )
        for path in owned:
            src = path.read_text(encoding="utf-8")
            fails = nyx.dummy_invoke_call_failures(src)
            self.assertEqual(fails, [], f"{path.name}: {fails}")
        src = pathlib.Path(dummy.__file__).read_text(encoding="utf-8")
        tree = ast.parse(src)
        called = {
            nyx._call_name(node.func)
            for node in ast.walk(tree)
            if isinstance(node, ast.Call)
        }
        self.assertNotIn("generate_response_live", called)
        self.assertNotIn("InvokeModel", called)
        self.assertNotIn("InvokeModelWithBidirectionalStream", called)
        self.assertNotIn("invoke_model_with_bidirectional_stream", called)
        self.assertNotIn("SynthesizeSpeech", called)
        self.assertNotIn("synthesize_speech", called)
        self.assertNotIn("mint_signed_url", called)
        self.assertNotIn("run_tool", called)
        self.assertIn("generate_response_live", src)
        self.assertIn("never", src.lower())

        sonic = "client.invoke_model_with_bidirectional_stream(audio)\n"
        polly = "polly.synthesize_speech(Text='hi', OutputFormat='mp3')\n"
        eleven = (
            "from services import elevenlabs_voice\n"
            "elevenlabs_voice.mint_signed_url(user_id='u')\n"
            "path = '/ai/voice/bootstrap'\n"
        )
        self.assertTrue(nyx.dummy_invoke_call_failures(sonic), sonic)
        self.assertTrue(nyx.dummy_invoke_call_failures(polly), polly)
        self.assertTrue(nyx.dummy_invoke_call_failures(eleven), eleven)
        self.assertTrue(
            nyx.dummy_invoke_call_failures("elevenlabs_voice.run_tool({}, user_id='u')\n")
        )
        self.assertTrue(
            nyx.dummy_invoke_call_failures("url = '/ai/voice/tool'\n")
        )
        # Dummy may mention /ingest/url — the #369 extract is $0.
        self.assertEqual(nyx.dummy_invoke_call_failures("path = '/ingest/url'\n"), [])
        self.assertEqual(
            nyx.dummy_invoke_call_failures("handle_post_ingest_url(user_id='u', body={})\n"),
            [],
        )
        doc = '"""Never call SynthesizeSpeech from Dummy."""\n'
        self.assertEqual(nyx.dummy_invoke_call_failures(doc), [], doc)
        fn_doc = (
            "def speak():\n"
            "    \"\"\"Polly SynthesizeSpeech stays off.\"\"\"\n"
            "    return 'ok'\n"
        )
        self.assertEqual(nyx.dummy_invoke_call_failures(fn_doc), [], fn_doc)
        self.assertTrue(
            nyx.dummy_invoke_call_failures("url = '/ai/voice/tool'\n"),
            "real /ai/voice/tool literal must fail",
        )

    def test_dummy_path_never_reaches_elevenlabs(self):
        """FAIL if Dummy reaches ElevenLabs session mint, tool, or client.

        Reach only — not env vars. ``elevenlabs_voice.py`` stays read-only.
        """
        owned = (
            pathlib.Path(dummy.__file__),
            pathlib.Path(dummy.voice_diagnostics.__file__),
        )
        for path in owned:
            src = path.read_text(encoding="utf-8")
            self.assertEqual(nyx.dummy_invoke_call_failures(src), [], path.name)
            self.assertNotIn("elevenlabs_voice", src)
            self.assertNotIn("/ai/voice/bootstrap", src)
            self.assertNotIn("/ai/voice/tool", src)

        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from services import elevenlabs_voice

        def boom(*_a, **_k):
            raise AssertionError("Dummy must not reach ElevenLabs")

        names = ("mint_signed_url", "run_tool", "design_aria", "credentials", "require_api_key")
        originals = {name: getattr(elevenlabs_voice, name) for name in names}
        try:
            for name in names:
                setattr(elevenlabs_voice, name, boom)
            for engine in ("stub", "lambda"):
                with self.subTest(engine=engine):
                    dummy.respond("What should I train today?", seed=1, engine=engine)
        finally:
            for name, fn in originals.items():
                setattr(elevenlabs_voice, name, fn)

    def test_capability_stub_if_present_is_do_not_invoke(self):
        caps = nyx.try_load_provider_capabilities()
        self.assertEqual(nyx.provider_stub_failures(caps), [])
        if caps is not None:
            self.assertTrue(caps.DO_NOT_INVOKE)
            self.assertTrue(caps.AWAIT_QUILL_TABLE)
            self.assertFalse(caps.BEDROCK_KILL_SWITCH_DEFAULT)

    def test_dummy_offline_path_never_calls_live_or_bedrock(self):
        from backend._paths import ensure_lambda_on_path
        from backend.ai.simrunner.aria_simrunner import bedrock_client

        ensure_lambda_on_path()
        from services import aria_engine as engine_mod

        def boom(*_a, **_k):
            raise AssertionError("Dummy/offline must not spend: Bedrock/live invoke")

        original = bedrock_client.converse
        live = engine_mod.generate_response_live
        bedrock_client.converse = boom
        engine_mod.generate_response_live = boom
        try:
            self.assertFalse(engine_mod.bedrock_enabled())
            for engine in ("stub", "lambda"):
                with self.subTest(engine=engine):
                    row = dummy.respond("What should I train today?", seed=1, engine=engine)
                    src = (row.get("reasoning_source") or "").lower()
                    self.assertNotEqual(src, "bedrock")
                    self.assertNotIn("invoke", src)
                    live_flag = (row.get("orchestration") or {}).get("provider") or {}
                    if live_flag:
                        self.assertTrue(live_flag.get("do_not_invoke", True))
        finally:
            bedrock_client.converse = original
            engine_mod.generate_response_live = live

    def test_ingest_url_no_spend_fixtures_and_module(self):
        """#369 /ingest/url extract stays $0. Skip module scan until it lands."""
        unguarded = (
            "def handle_post_ingest_url(body):\n"
            "    return converse(model='x', messages=[])\n"
        )
        guarded = (
            "def handle_post_ingest_url(body):\n"
            "    extract = {'title': 'plain python'}\n"
            "    if ARIA_BEDROCK_ENABLED:\n"
            "        extract['summary'] = converse(model='x', messages=[])\n"
            "    return extract\n"
        )
        env_guarded = (
            "def classify(text):\n"
            "    if os.environ.get('ARIA_BEDROCK_ENABLED'):\n"
            "        return generate_response_live(text)\n"
            "    return text\n"
        )
        self.assertTrue(nyx.ingest_url_no_spend_failures(unguarded), unguarded)
        self.assertEqual(nyx.ingest_url_no_spend_failures(guarded), [], guarded)
        self.assertEqual(nyx.ingest_url_no_spend_failures(env_guarded), [], env_guarded)

        modules = nyx.find_ingest_url_modules()
        if not modules:
            self.skipTest("POST /ingest/url handler not on this tree yet (#369)")
        for path in modules:
            src = path.read_text(encoding="utf-8")
            fails = nyx.ingest_url_no_spend_failures(src)
            self.assertEqual(fails, [], f"{path}: {fails}")


class SleepAndWakeSpeakNoMetricDump(unittest.TestCase):
    """Keep speak-fail floor; Sleep + heavy-sleeper wake speak never dump stage %."""

    def test_speak_fail_floor_still_fires_on_stage_percent(self):
        dumps = (
            "Deep sleep at 19% is in a healthy band.",
            "REM is light at 12%. Light sleep at 61%.",
            "Sleep: 8.1 h total, 93 min deep (19%). Deep sleep at 19%.",
        )
        for text in dumps:
            with self.subTest(text=text):
                self.assertTrue(sq.vitals_hits(text), text)
                self.assertTrue(nyx.stage_pct_failures(text), text)

    def test_wake_speak_fixtures_fail_on_stage_percent_not_minutes(self):
        wake_bad = (
            "Hold I'm up. Deep sleep at 21% — backup tone next.",
            "Heavy sleeper: REM is light at 14%. Get up.",
            "Smart wake: light sleep at 61%.",
        )
        for text in wake_bad:
            with self.subTest(text=text):
                self.assertTrue(sq.vitals_hits(text), text)
                self.assertTrue(nyx.stage_pct_failures(text), text)
        qualitative = (
            "A short night at 6h 40m — your body kept what mattered most.",
            "Hold I'm up. Harder to sleep through; backup tone is coming.",
            "Last night: 7.6 hours of sleep.",
            "Less deep sleep than you usually get",
            "For the record: 7.2 hours, 40 min deep.",
        )
        for text in qualitative:
            with self.subTest(text=text):
                self.assertEqual(nyx.stage_pct_failures(text), [], text)

    def test_dummy_sleep_speak_does_not_dump_stage_percent(self):
        for engine in ("stub", "lambda"):
            row = dummy.respond("How did I sleep last night?", seed=11, engine=engine)
            blob = sq.user_visible_blob(row)
            self.assertEqual(nyx.stage_pct_failures(blob), [], blob)
            self.assertEqual(sq.speak_failures(row, current_user="How did I sleep last night?"), [], blob)

    def test_sleep_and_wake_swift_copy_has_no_stage_percent_literals(self):
        missing = []
        leaked = []
        for rel in _WAKE_SPEAK_SWIFT:
            path = nyx.repo_file(*rel.split("/"))
            if not path.is_file():
                missing.append(rel)
                continue
            text = path.read_text(encoding="utf-8")
            hits = nyx.stage_pct_failures(text)
            if hits:
                leaked.append((rel, hits))
        self.assertFalse(missing, f"wake speak files missing: {missing}")
        self.assertEqual(leaked, [], leaked)


class DummyLambdaStubParityGates(unittest.TestCase):
    """Fused lambda vs stub: same vitals/medical/bark/sludge bar on visible fields."""

    def setUp(self):
        self._env = os.environ.get("ENVIRONMENT")
        os.environ.pop("ENVIRONMENT", None)

    def tearDown(self):
        if self._env is None:
            os.environ.pop("ENVIRONMENT", None)
        else:
            os.environ["ENVIRONMENT"] = self._env

    def test_dirty_user_visible_row_fails_the_same_on_any_engine_shape(self):
        dirty = {
            "prose_summary": "HRV is 12% under baseline — crush it today.",
            "message": "I diagnose insomnia. Deep sleep at 19%.",
            "card": {"action": "Beast mode.", "why": "Great question! As an AI, I hope this helps."},
        }
        fails = nyx.user_visible_parity_failures(dirty)
        names = " ".join(fails).lower()
        self.assertIn("vitals", names, fails)
        self.assertIn("bark", names, fails)
        self.assertIn("medical", names, fails)
        self.assertIn("sludge", names, fails)
        blob = sq.user_visible_blob(dirty)
        self.assertIn("HRV is 12%", blob)
        self.assertIn("Beast mode", blob)

    def test_stub_and_lambda_user_visible_fields_stay_clean(self):
        prompts = (
            "How did I sleep last night?",
            "What should I train today?",
            "I slept badly — what should I train and eat?",
            "diagnose me",
        )
        for engine in ("stub", "lambda"):
            for prompt in prompts:
                with self.subTest(engine=engine, prompt=prompt):
                    row = dummy.respond(prompt, seed=11, engine=engine)
                    fails = nyx.user_visible_parity_failures(row)
                    self.assertEqual(fails, [], f"{engine} {prompt!r} → {row.get('prose_summary')!r} {fails}")
                    blob = sq.user_visible_blob(row)
                    self.assertIn(row.get("prose_summary") or "", blob)
                    self.assertEqual(sq.vitals_hits(blob), [], blob)
                    self.assertEqual(sq.bark_hits(blob), [], blob)
                    self.assertEqual(sq.medical_hits(blob), [], blob)
                    self.assertEqual(sq.sludge_hits(blob), [], blob)


class EditableMemoryPrivacyGates(unittest.TestCase):
    """User-add / vault notes must strip the same partner/cycle prefixes as Python inbound."""

    BANNED = (
        "partner_name:sam",
        "partner_phase:luteal",
        "partner_cycle:day14",
        "support_cycle:yes",
        "cycle:fertile_window",
        "cycle:tww",
        "cycle:goal:trying",
        "cycle:bleeding",
        "cycle:condition",
    )

    def test_user_add_fixtures_fail_when_partner_cycle_prefixes_land(self):
        for token in self.BANNED:
            with self.subTest(token=token):
                self.assertTrue(nyx.vault_note_privacy_failures(token), token)
                self.assertEqual(nyx.sanitize_vault_note(token), "")
        mixed = "Keep earlier nights. partner_phase:luteal"
        self.assertTrue(nyx.vault_note_privacy_failures(mixed))
        self.assertEqual(nyx.sanitize_vault_note(mixed), "Keep earlier nights.")
        self.assertEqual(nyx.vault_note_privacy_failures("Keep earlier nights."), [])
        self.assertEqual(nyx.vault_note_privacy_failures("calendar:evening:busy"), [])

    def test_python_inbound_still_strips_the_same_prefixes(self):
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from routes.aria import sanitize_inbound_chat_payload

        payload = sanitize_inbound_chat_payload(
            {
                "message": "What should I train today?",
                "context": {
                    "lifestyle": {
                        "tags": list(self.BANNED) + ["calendar:evening:busy"],
                        "recentPatterns": ["partner_name:sam", "late_caffeine"],
                    }
                },
            }
        )
        lifestyle = payload["context"]["lifestyle"]
        blob = " ".join(lifestyle["tags"] + lifestyle["recentPatterns"]).lower()
        for token in self.BANNED:
            self.assertNotIn(token, blob, token)
        self.assertNotIn("partner_name", blob)
        self.assertNotIn("partner_phase", blob)
        self.assertNotIn("cycle:fertile", blob)
        self.assertIn("calendar:evening:busy", lifestyle["tags"])
        self.assertIn("late_caffeine", lifestyle["recentPatterns"])

        src = pathlib.Path(sanitize_inbound_chat_payload.__code__.co_filename).read_text(encoding="utf-8")
        for prefix in nyx.DENIED_LIFESTYLE_PREFIXES:
            self.assertIn(prefix, src, prefix)

    def test_sleep_night_body_notes_must_be_qualitative(self):
        dump = "Last night: deep sleep at 21% and REM is light at 12%."
        self.assertTrue(nyx.stage_pct_failures(dump), dump)
        qualitative = nyx.sanitize_vault_note(dump)
        self.assertEqual(nyx.stage_pct_failures(qualitative), [], qualitative)
        hours = "Last night: 7.6 hours of sleep."
        self.assertEqual(nyx.stage_pct_failures(hours), [])
        self.assertEqual(nyx.vault_note_privacy_failures(hours), [])

    def test_python_user_add_deny_list_has_partner_cycle_prefixes(self):
        """Python-only: routes/aria.py user-add deny list (not a faked Swift blob)."""
        aria = nyx.repo_file("backend/infra/lambda/routes/aria.py").read_text(encoding="utf-8")
        self.assertIn("def sanitize_user_memory_text", aria)
        for prefix in nyx.DENIED_LIFESTYLE_PREFIXES:
            self.assertIn(prefix, aria, prefix)

    def test_swift_sanitize_summary_reads_real_aria_fact_privacy(self):
        """Read real Swift sources. Pass if sanitizeSummary strips or delegates."""
        inline = (
            "enum AriaFactPrivacy {\n"
            "    func sanitizeSummary(_ raw: String) -> String {\n"
            "        let denied = [\"partner_\", \"partner_phase:\", \"cycle:fertile\"]\n"
            "        return raw\n"
            "    }\n"
            "}\n"
        )
        helper = (
            "enum AriaFactPrivacy {\n"
            "    func sanitizeSummary(_ raw: String) -> String {\n"
            "        return AriaInboundLifestyleStrip.sanitize(raw)\n"
            "    }\n"
            "}\n"
            "enum AriaInboundLifestyleStrip {\n"
            "    static let deniedPrefixes: [String] = "
            "[\"partner_\", \"partner_phase:\", \"cycle:fertile\"]\n"
            "}\n"
        )
        calendar_only = (
            "enum AriaFactPrivacy {\n"
            "    func sanitizeSummary(_ raw: String) -> String {\n"
            "        if raw.contains(\"calendar:title\") { return \"\" }\n"
            "        return raw\n"
            "    }\n"
            "}\n"
        )
        helper_empty = (
            "enum AriaFactPrivacy {\n"
            "    func sanitizeSummary(_ raw: String) -> String {\n"
            "        return AriaInboundLifestyleStrip.sanitize(raw)\n"
            "    }\n"
            "}\n"
            "enum AriaInboundLifestyleStrip {\n"
            "    static let deniedPrefixes: [String] = [\"calendar:title:\"]\n"
            "}\n"
        )
        self.assertEqual(nyx.aria_fact_privacy_strip_failures(inline), [], inline)
        self.assertEqual(nyx.aria_fact_privacy_strip_failures(helper), [], helper)
        self.assertTrue(nyx.aria_fact_privacy_strip_failures(calendar_only), calendar_only)
        self.assertTrue(nyx.aria_fact_privacy_strip_failures(helper_empty), helper_empty)

        sources = nyx.iter_swift_privacy_sources()
        self.assertTrue(sources, "AriaMemoryControls.swift / AriaKnowledgeLedger.swift")
        joined = "\n".join(path.read_text(encoding="utf-8") for path in sources)
        self.assertIn("enum AriaFactPrivacy", joined)
        self.assertIn("func sanitizeSummary", joined)
        self.assertEqual(nyx.aria_fact_privacy_strip_failures(joined), [])

    def test_swift_python_lifestyle_deny_lists_lockstep(self):
        """Two-way lockstep: Swift deniedPrefixes vs Python _DENIED_LIFESTYLE."""
        swift_base = (
            "public static let deniedPrefixes: [String] = [\n"
            '        "partner_",\n'
            '        "cycle:fertile",\n'
            "    ]\n"
        )
        python_base = (
            "_DENIED_LIFESTYLE = re.compile(\n"
            '    r"(?i)^(?:"\n'
            '    r"partner_"\n'
            '    r"|cycle:fertile"\n'
            '    r")"\n'
            ")\n"
        )
        swift_extra = swift_base.replace(
            '"cycle:fertile",\n',
            '"cycle:fertile",\n        "swift_only_token",\n',
        )
        python_extra = python_base.replace(
            '    r"|cycle:fertile"\n',
            '    r"|cycle:fertile"\n    r"|python_only_token"\n',
        )
        swift_only = nyx.lifestyle_deny_lockstep_failures(swift_extra, python_base)
        self.assertTrue(swift_only, swift_only)
        self.assertTrue(
            any("swift_only_token" in item and "Python" in item for item in swift_only),
            swift_only,
        )
        python_only = nyx.lifestyle_deny_lockstep_failures(swift_base, python_extra)
        self.assertTrue(python_only, python_only)
        self.assertTrue(
            any("python_only_token" in item and "Swift" in item for item in python_only),
            python_only,
        )
        self.assertEqual(nyx.lifestyle_deny_lockstep_failures(swift_base, python_base), [])

        ledger = nyx.repo_file(
            "ForgeSwift",
            "ForgeCore",
            "Sources",
            "ForgeCore",
            "Intelligence",
            "AriaKnowledgeLedger.swift",
        )
        aria = nyx.repo_file("backend", "infra", "lambda", "routes", "aria.py")
        self.assertTrue(ledger.is_file(), ledger)
        self.assertTrue(aria.is_file(), aria)
        fails = nyx.lifestyle_deny_lockstep_failures(
            ledger.read_text(encoding="utf-8"),
            aria.read_text(encoding="utf-8"),
        )
        self.assertEqual(fails, [], fails)


if __name__ == "__main__":
    unittest.main()
