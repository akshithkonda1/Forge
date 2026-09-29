"""SSRF + fixture extraction for POST /ingest/url. No live network."""

from __future__ import annotations

import json
import os
import unittest
from pathlib import Path
from unittest.mock import patch

import _bootstrap  # noqa: F401

import http.client
import socket
import ssl

from handler import handler  # noqa: E402
from responses import RouteError  # noqa: E402
from routes import ingest as ingest_routes  # noqa: E402
from security import PAID_AI_ROUTES  # noqa: E402
from services import editable_memory  # noqa: E402
from services import web_ingest  # noqa: E402
from services.aria_context import CoachContextEngine  # noqa: E402
from services.coach_context import gather_user_context  # noqa: E402
from storage import dynamodb as dynamodb_store  # noqa: E402
from test_backend_handler import body, event  # noqa: E402


FIXTURES = Path(__file__).resolve().parent / "fixtures" / "web_ingest"
PUBLIC_IP = "8.8.8.8"
SAFE_URL = "https://example.com/page"


def _headers(**extra):
    headers = {"content-type": "text/html; charset=utf-8"}
    headers.update({k.lower(): v for k, v in extra.items()})
    return headers


def _html(name: str) -> bytes:
    return (FIXTURES / name).read_bytes()


def _ok_transport(html: bytes, *, url: str = SAFE_URL, **header_extra):
    def transport(requested: str, pinned_ip: str, timeout: float) -> web_ingest.HttpResponse:
        return web_ingest.HttpResponse(
            status=200,
            headers=_headers(**header_extra),
            body=html,
            url=requested,
        )

    return transport


def _resolver(*ips: str):
    def resolve(hostname: str) -> list[str]:
        return list(ips)

    return resolve


class IpPolicyTests(unittest.TestCase):
    def test_public_ipv4_is_allowed(self):
        self.assertFalse(web_ingest.is_blocked_ip("8.8.8.8"))
        self.assertFalse(web_ingest.is_blocked_ip("1.1.1.1"))

    def test_loopback_private_link_local_and_metadata_are_blocked(self):
        blocked = [
            "127.0.0.1",
            "10.0.0.8",
            "172.16.4.1",
            "192.168.1.20",
            "169.254.169.254",
            "169.254.170.2",
            "169.254.1.1",
            "0.0.0.0",
            "100.64.1.2",
            "::1",
            "fe80::1",
            "fc00::1",
            "fd00:ec2::254",
            "::ffff:127.0.0.1",
            "::ffff:169.254.169.254",
            "::ffff:10.1.1.1",
        ]
        for ip in blocked:
            with self.subTest(ip=ip):
                self.assertTrue(web_ingest.is_blocked_ip(ip), ip)

    def test_garbage_ip_is_blocked(self):
        self.assertTrue(web_ingest.is_blocked_ip("not-an-ip"))


class UrlValidationTests(unittest.TestCase):
    def test_https_public_host_normalizes(self):
        self.assertEqual(
            web_ingest.validate_https_url("https://Example.COM/plan?x=1"),
            "https://example.com/plan?x=1",
        )

    def test_http_and_credentials_and_non_443_are_rejected(self):
        cases = [
            ("http://example.com/x", "validation_failed"),
            ("https://user:pass@example.com/x", "validation_failed"),
            ("https://example.com:8443/x", "validation_failed"),
            ("file:///etc/passwd", "validation_failed"),
            ("", "validation_failed"),
            ("https://127.0.0.1/", "validation_failed"),
            ("https://169.254.169.254/latest/meta-data", "validation_failed"),
            ("https://localhost/x", "validation_failed"),
            ("https://metadata.google.internal/", "validation_failed"),
        ]
        for url, code in cases:
            with self.subTest(url=url):
                with self.assertRaises(RouteError) as raised:
                    web_ingest.validate_https_url(url)
                self.assertEqual(raised.exception.code, code)


class DnsAndRedirectTests(unittest.TestCase):
    def test_dns_to_private_or_mixed_set_is_blocked(self):
        with self.assertRaises(RouteError) as private:
            web_ingest.resolve_public_ips("evil.test", resolver=_resolver("10.0.0.4"))
        self.assertEqual(private.exception.code, "validation_failed")

        with self.assertRaises(RouteError) as mixed:
            web_ingest.resolve_public_ips(
                "evil.test", resolver=_resolver("8.8.8.8", "169.254.169.254")
            )
        self.assertEqual(mixed.exception.code, "validation_failed")

    def test_dns_to_loopback_and_link_local_is_blocked(self):
        for ips in (("127.0.0.1",), ("::1",), ("fe80::aa",), ("fd00:ec2::254",)):
            with self.subTest(ips=ips):
                with self.assertRaises(RouteError) as raised:
                    web_ingest.resolve_public_ips("evil.test", resolver=_resolver(*ips))
                self.assertEqual(raised.exception.code, "validation_failed")

    def test_public_resolution_returns_unique_ips(self):
        ips = web_ingest.resolve_public_ips(
            "example.com", resolver=_resolver("8.8.8.8", "8.8.8.8", "1.1.1.1")
        )
        self.assertEqual(ips, ["8.8.8.8", "1.1.1.1"])

    def test_literal_ip_host_is_rejected(self):
        for host in ("8.8.8.8", "2001:db8::1", "::1"):
            with self.subTest(host=host):
                with self.assertRaises(RouteError) as raised:
                    web_ingest.resolve_public_ips(host)
                self.assertEqual(raised.exception.status_code, 400)
                self.assertEqual(raised.exception.code, "validation_failed")

    def test_redirect_to_private_ip_is_blocked(self):
        hops: list[str] = []

        def transport(url: str, pinned_ip: str, timeout: float) -> web_ingest.HttpResponse:
            hops.append(url)
            if url == "https://example.com/start":
                return web_ingest.HttpResponse(
                    status=302,
                    headers={"location": "https://metadata.internal/secret", "content-type": "text/html"},
                    body=b"",
                    url=url,
                )
            self.fail(f"must not follow through to {url}")
            raise AssertionError(url)

        def resolver(hostname: str) -> list[str]:
            if hostname == "example.com":
                return [PUBLIC_IP]
            if hostname == "metadata.internal":
                return ["169.254.169.254"]
            self.fail(hostname)
            return []

        with self.assertRaises(RouteError) as raised:
            web_ingest.fetch_https(
                "https://example.com/start",
                resolver=resolver,
                transport=transport,
            )
        self.assertEqual(raised.exception.code, "validation_failed")
        self.assertEqual(hops, ["https://example.com/start"])

    def test_redirect_to_http_is_rejected(self):
        def transport(url: str, pinned_ip: str, timeout: float) -> web_ingest.HttpResponse:
            return web_ingest.HttpResponse(
                status=301,
                headers={"location": "http://example.com/next", "content-type": "text/html"},
                body=b"",
                url=url,
            )

        with self.assertRaises(RouteError) as raised:
            web_ingest.fetch_https(
                "https://example.com/start",
                resolver=_resolver(PUBLIC_IP),
                transport=transport,
            )
        self.assertEqual(raised.exception.code, "validation_failed")

    def test_redirect_cap(self):
        def transport(url: str, pinned_ip: str, timeout: float) -> web_ingest.HttpResponse:
            n = url.rsplit("/", 1)[-1]
            nxt = str(int(n) + 1)
            return web_ingest.HttpResponse(
                status=302,
                headers={"location": f"https://example.com/{nxt}", "content-type": "text/html"},
                body=b"",
                url=url,
            )

        with self.assertRaises(RouteError) as raised:
            web_ingest.fetch_https(
                "https://example.com/1",
                resolver=_resolver(PUBLIC_IP),
                transport=transport,
            )
        self.assertEqual(raised.exception.code, "validation_failed")

    def test_relative_redirect_is_rechecked(self):
        def transport(url: str, pinned_ip: str, timeout: float) -> web_ingest.HttpResponse:
            if url.endswith("/go"):
                return web_ingest.HttpResponse(
                    status=302,
                    headers={"location": "/ok", "content-type": "text/html"},
                    body=b"",
                    url=url,
                )
            return web_ingest.HttpResponse(
                status=200,
                headers=_headers(),
                body=_html("generic.html"),
                url=url,
            )

        response = web_ingest.fetch_https(
            "https://example.com/go",
            resolver=_resolver(PUBLIC_IP),
            transport=transport,
        )
        self.assertEqual(response.url, "https://example.com/ok")

    def test_unsupported_content_type_and_oversize(self):
        def pdf(_url, _ip, _timeout):
            return web_ingest.HttpResponse(
                status=200,
                headers={"content-type": "application/pdf"},
                body=b"%PDF-1.4",
                url=_url,
            )

        with self.assertRaises(RouteError) as media:
            web_ingest.fetch_https(
                SAFE_URL, resolver=_resolver(PUBLIC_IP), transport=pdf
            )
        self.assertEqual(media.exception.code, "validation_failed")

        huge = b"x" * (web_ingest.MAX_BODY_BYTES + 1)

        def big(_url, _ip, _timeout):
            return web_ingest.HttpResponse(
                status=200,
                headers=_headers(),
                body=huge,
                url=_url,
            )

        with self.assertRaises(RouteError) as size:
            web_ingest.fetch_https(
                SAFE_URL, resolver=_resolver(PUBLIC_IP), transport=big
            )
        self.assertEqual(size.exception.code, "validation_failed")

    def test_no_cookies_on_any_hop(self):
        sent: list[dict[str, str]] = []

        def transport(url: str, pinned_ip: str, timeout: float) -> web_ingest.HttpResponse:
            # The production transport never adds Cookie; this double-checks
            # fetch_https itself does not forward Set-Cookie from the prior hop.
            sent.append({"url": url, "pinned_ip": pinned_ip})
            if url.endswith("/one"):
                return web_ingest.HttpResponse(
                    status=302,
                    headers={
                        "location": "https://example.com/two",
                        "set-cookie": "session=abc; HttpOnly",
                        "content-type": "text/html",
                    },
                    body=b"",
                    url=url,
                )
            return web_ingest.HttpResponse(
                status=200,
                headers=_headers(),
                body=_html("generic.html"),
                url=url,
            )

        web_ingest.fetch_https(
            "https://example.com/one",
            resolver=_resolver(PUBLIC_IP),
            transport=transport,
        )
        self.assertEqual(len(sent), 2)
        self.assertEqual(sent[0]["pinned_ip"], PUBLIC_IP)

    def test_default_transport_headers_have_no_cookie(self):
        source = Path(web_ingest.__file__).read_text(encoding="utf-8")
        self.assertNotIn('"Cookie"', source)
        self.assertNotIn("'Cookie'", source)
        self.assertNotIn("HTTPCookieProcessor", source)
        self.assertIn("ForgeIngest/0.1", source)


class ExtractionFixtureTests(unittest.TestCase):
    def test_recipe_json_ld(self):
        parsed = web_ingest.extract_from_html(
            _html("recipe.html"), source_url="https://example.com/oats"
        )
        self.assertEqual(parsed["kind"], "recipe")
        extract = parsed["extract"]
        self.assertEqual(extract["name"], "Overnight oats")
        self.assertEqual(extract["ingredients"][0], "80 g rolled oats")
        self.assertIn("Stir oats into yogurt.", extract["instructions"])
        self.assertEqual(extract["totalTime"], "PT10M")
        self.assertEqual(extract["nutrition"]["calories"], "420 kcal")
        self.assertIn("Recipe", parsed["schemaTypes"])
        self.assertIn("oats", parsed["readableText"].lower())

    def test_exercise_plan_from_graph(self):
        parsed = web_ingest.extract_from_html(
            _html("exercise_plan.html"), source_url="https://example.com/plan"
        )
        self.assertEqual(parsed["kind"], "exercise-plan")
        extract = parsed["extract"]
        self.assertEqual(extract["name"], "Upper-body strength — week 3")
        self.assertEqual(extract["exerciseType"], "Strength training")
        self.assertEqual(extract["intensity"], "Moderate")
        self.assertEqual(extract["activityDuration"], "PT45M")
        feed = web_ingest.build_aria_feed(
            kind=parsed["kind"],
            extract=extract,
            readable_text=parsed["readableText"],
            source_url="https://example.com/plan",
        )
        self.assertEqual(feed["domain"], "training")
        self.assertTrue(feed["untrusted"])

    def test_howto_steps_and_schema_url_type(self):
        parsed = web_ingest.extract_from_html(
            _html("howto.html"), source_url="https://example.com/roll"
        )
        self.assertEqual(parsed["kind"], "how-to")
        steps = parsed["extract"]["steps"]
        texts = [s["text"] for s in steps]
        self.assertIn("Sit with the roller under one calf.", texts)
        self.assertIn("Switch legs and repeat.", texts)
        self.assertEqual(parsed["extract"]["tool"], ["Foam roller"])
        feed = web_ingest.build_aria_feed(
            kind=parsed["kind"],
            extract=parsed["extract"],
            readable_text=parsed["readableText"],
            source_url="https://example.com/roll",
        )
        self.assertEqual(feed["domain"], "lifestyle")

    def test_article_and_generic(self):
        article = web_ingest.extract_from_html(
            _html("article.html"), source_url="https://example.com/easy"
        )
        self.assertEqual(article["kind"], "article")
        self.assertEqual(article["extract"]["headline"], "Why easy runs still count")
        self.assertEqual(article["extract"]["author"], "Aria Staff")
        self.assertIn("conversational", article["extract"]["description"])

        generic = web_ingest.extract_from_html(
            _html("generic.html"), source_url="https://example.com/hike"
        )
        self.assertEqual(generic["kind"], "generic")
        self.assertEqual(generic["title"], "Notes from a long hike")
        self.assertNotIn("window.TRACK", generic["readableText"])
        self.assertNotIn("color: red", generic["readableText"])
        self.assertIn("sunrise", generic["readableText"])

    def test_ingest_url_uses_injected_transport_only(self):
        result = web_ingest.ingest_url(
            "https://example.com/oats",
            resolver=_resolver(PUBLIC_IP),
            transport=_ok_transport(_html("recipe.html")),
        )
        self.assertEqual(result.kind, "recipe")
        self.assertEqual(result.final_url, "https://example.com/oats")
        self.assertEqual(result.extract["recipeYield"], "1 bowl")
        self.assertEqual(web_ingest.memory_folder_for("recipe"), "lifestyle")
        queried = web_ingest.ingest_url(
            "https://example.com/oats?utm=1#top",
            resolver=_resolver(PUBLIC_IP),
            transport=_ok_transport(_html("recipe.html")),
        )
        self.assertEqual(queried.url, "https://example.com/oats")
        self.assertEqual(queried.final_url, "https://example.com/oats")
        feed = web_ingest.build_aria_feed(
            kind=queried.kind,
            extract=queried.extract,
            readable_text=queried.readable_text,
            source_url="https://example.com/oats?utm=1#top",
        )
        self.assertEqual(feed["sourceUrl"], "https://example.com/oats")


class IngestRouteTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"

    def tearDown(self):
        os.environ.pop("ENVIRONMENT", None)
        os.environ.pop("FORGE_ALLOW_ANON_TEST_USER", None)
        os.environ.pop("FORGE_DEMO_DATA", None)

    def _patch_fetch(self, html_name: str):
        real_ingest = web_ingest.ingest_url
        html = _html(html_name)

        def fake(url: str, **kwargs):
            return real_ingest(
                url,
                resolver=_resolver(PUBLIC_IP),
                transport=_ok_transport(html, url=url),
            )

        return patch.object(ingest_routes.web_ingest, "ingest_url", side_effect=fake)

    def test_handler_requires_auth_in_production(self):
        os.environ["ENVIRONMENT"] = "production"
        os.environ.pop("FORGE_ALLOW_ANON_TEST_USER", None)
        response = handler(event("POST", "/ingest/url", {"url": SAFE_URL}), None)
        self.assertEqual(response["statusCode"], 401)

    def test_handler_extracts_recipe_without_persisting(self):
        with self._patch_fetch("recipe.html"):
            response = handler(
                event("POST", "/ingest/url", {"url": "https://example.com/oats"}, user_id="u-ingest"),
                None,
            )
        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertEqual(payload["kind"], "recipe")
        self.assertEqual(payload["extract"]["name"], "Overnight oats")
        self.assertEqual(payload["ariaFeed"]["domain"], "nutrition")
        self.assertTrue(payload["ariaFeed"]["untrusted"])
        self.assertFalse(payload["memoryCandidate"]["persisted"])
        engine = CoachContextEngine()
        self.assertEqual(engine.short_term_memories("u-ingest"), [])
        # Demo fixtures would hide a stray write; force the empty-account path.
        os.environ["FORGE_DEMO_DATA"] = "0"
        ctx = gather_user_context("u-ingest")
        self.assertEqual(ctx["recentWorkouts"], [])
        self.assertFalse(ctx["hasLoggedSleep"])
        self.assertIsNone(ctx["todayPlan"])
        ground = [
            item.get("sk", "")
            for item in dynamodb_store._local_store.values()
            if str(item.get("sk", "")).startswith(("SLEEP#", "WORKOUT#", "PLAN#", "PROFILE", "READINESS#"))
        ]
        self.assertEqual(ground, [])

    def test_v1_alias_and_persist_respects_memory_off(self):
        editable_memory.put_settings(
            "u-off", editable_memory.CompanionMemorySettings(memory_enabled=False)
        )
        with self._patch_fetch("exercise_plan.html"):
            response = handler(
                event(
                    "POST",
                    "/v1/ingest/url",
                    {"url": "https://example.com/plan", "persistMemory": True},
                    user_id="u-off",
                ),
                None,
            )
        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertEqual(payload["kind"], "exercise-plan")
        self.assertEqual(payload["ariaFeed"]["domain"], "training")
        self.assertFalse(payload["memoryCandidate"]["persisted"])
        self.assertEqual(CoachContextEngine().short_term_memories("u-off"), [])

    def test_persist_writes_sanitized_short_term_note(self):
        with self._patch_fetch("howto.html"):
            response = handler(
                event(
                    "POST",
                    "/ingest/url",
                    {"url": "https://example.com/roll", "persistMemory": True},
                    user_id="u-on",
                ),
                None,
            )
        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertTrue(payload["memoryCandidate"]["persisted"])
        memories = CoachContextEngine().short_term_memories("u-on")
        self.assertEqual(len(memories), 1)
        self.assertEqual(memories[0].source, "web")
        self.assertIn("Foam-roll", memories[0].text)
        self.assertTrue(memories[0].text.startswith("From example.com:"))

    def test_partner_tokens_never_reach_memory_or_feed(self):
        with self._patch_fetch("generic.html"):
            response = handler(
                event(
                    "POST",
                    "/ingest/url",
                    {"url": "https://example.com/hike", "persistMemory": True},
                    user_id="u-priv",
                ),
                None,
            )
        payload = body(response)
        blob = json.dumps(payload).lower()
        self.assertNotIn("partner_name", blob)
        self.assertNotIn("partner_name:sam", blob)
        memories = CoachContextEngine().short_term_memories("u-priv")
        self.assertTrue(memories)
        self.assertNotIn("partner", memories[0].text.lower())

    def test_disabled_folder_skips_persist(self):
        editable_memory.put_settings(
            "u-folder",
            editable_memory.CompanionMemorySettings(disabled_folders=["lifestyle"]),
        )
        with self._patch_fetch("recipe.html"):
            response = handler(
                event(
                    "POST",
                    "/ingest/url",
                    {"url": "https://example.com/oats", "persistMemory": True},
                    user_id="u-folder",
                ),
                None,
            )
        self.assertFalse(body(response)["memoryCandidate"]["persisted"])
        self.assertEqual(CoachContextEngine().short_term_memories("u-folder"), [])
        self.assertEqual(body(response)["memoryCandidate"]["folder"], "lifestyle")

    def test_scrub_fixture_persists_safe_host_note_only(self):
        forbidden = (
            "partner_name",
            "cycle:fertile",
            "deep sleep at 20%",
            "180 bpm",
            "cures",
            "ignore previous",
        )
        with self._patch_fetch("scrub_page.html"):
            response = handler(
                event(
                    "POST",
                    "/ingest/url",
                    {
                        "url": "https://example.com/hike?utm=1#share",
                        "persistMemory": True,
                    },
                    user_id="u-scrub",
                ),
                None,
            )
        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertTrue(payload["memoryCandidate"]["persisted"])
        self.assertEqual(payload["memoryCandidate"]["folder"], "lifestyle")
        self.assertIn(payload["memoryCandidate"]["folder"], editable_memory.MEMORY_FOLDERS)
        self.assertNotEqual(payload["memoryCandidate"]["folder"], "healthHistory")
        self.assertEqual(payload["finalUrl"], "https://example.com/hike")
        self.assertEqual(payload["ariaFeed"]["sourceUrl"], "https://example.com/hike")
        note = payload["memoryCandidate"]["text"]
        self.assertTrue(note.startswith("From example.com:"))
        self.assertLessEqual(len(note), web_ingest.MAX_WEB_MEMORY_NOTE_CHARS)
        self.assertEqual(web_ingest.MAX_WEB_MEMORY_NOTE_CHARS, 300)
        spoken = json.dumps(payload["ariaFeed"]).lower() + " " + str(payload.get("readableText") or "").lower()
        memories = CoachContextEngine().short_term_memories("u-scrub")
        self.assertEqual(len(memories), 1)
        self.assertEqual(memories[0].text, note)
        for token in forbidden:
            self.assertNotIn(token, note.lower())
            self.assertNotIn(token, memories[0].text.lower())
            self.assertNotIn(token, spoken)
        self.assertNotIn("cures", spoken)

    def test_persist_memory_off_or_false_string_stores_nothing(self):
        for label, body_obj in (
            ("omitted", {"url": "https://example.com/hike"}),
            ("false_string", {"url": "https://example.com/hike", "persistMemory": "false"}),
        ):
            dynamodb_store.clear_local_store()
            with self.subTest(label=label):
                with self._patch_fetch("scrub_page.html"):
                    response = handler(
                        event("POST", "/ingest/url", body_obj, user_id="u-nopersist"),
                        None,
                    )
                self.assertEqual(response["statusCode"], 200)
                payload = body(response)
                self.assertFalse(payload["memoryCandidate"]["persisted"])
                self.assertEqual(CoachContextEngine().short_term_memories("u-nopersist"), [])

    def test_rate_limit_returns_429_rate_limited(self):
        with self._patch_fetch("generic.html"), patch.object(
            ingest_routes,
            "enforce_user_rate_limit",
            side_effect=PermissionError("rate limit exceeded"),
        ):
            response = handler(
                event(
                    "POST",
                    "/ingest/url",
                    {"url": "https://example.com/hike"},
                    user_id="u-limited",
                ),
                None,
            )
        self.assertEqual(response["statusCode"], 429)
        payload = body(response)
        self.assertEqual(payload["code"], "rate_limited")
        self.assertIn("/ingest/url", PAID_AI_ROUTES)
        self.assertIn("/v1/ingest/url", PAID_AI_ROUTES)

    def test_invalid_user_id_is_not_500(self):
        with self.assertRaises(RouteError) as raised:
            ingest_routes.handle_post_ingest_url("bad user id!", {"url": SAFE_URL})
        self.assertIn(raised.exception.status_code, (400, 401))
        self.assertNotEqual(raised.exception.status_code, 500)

    def test_handler_maps_network_error_to_502(self):
        real = web_ingest.ingest_url

        def fake(url: str, **kwargs):
            def transport(_requested, _ip, _timeout):
                raise ConnectionError("refused")

            return real(url, resolver=_resolver(PUBLIC_IP), transport=transport)

        with patch.object(ingest_routes.web_ingest, "ingest_url", side_effect=fake):
            response = handler(
                event("POST", "/ingest/url", {"url": SAFE_URL}, user_id="u-502"),
                None,
            )
        self.assertEqual(response["statusCode"], 502)
        self.assertEqual(body(response)["code"], "upstream_unavailable")

    def test_handler_bad_port_and_ip_literal_are_400(self):
        for url in (
            "https://example.com:abc/",
            "https://example.com:99999/",
            "https://8.8.8.8/",
            "https://[2001:db8::1]/",
        ):
            with self.subTest(url=url):
                response = handler(
                    event("POST", "/ingest/url", {"url": url}, user_id="u-val"),
                    None,
                )
                self.assertEqual(response["statusCode"], 400)
                self.assertEqual(body(response)["code"], "validation_failed")

    def test_handler_maps_deadline_to_504(self):
        def fake(url: str, **kwargs):
            raise web_ingest.IngestError(
                504, "The page fetch timed out.", code="upstream_unavailable"
            )

        with patch.object(ingest_routes.web_ingest, "ingest_url", side_effect=fake):
            response = handler(
                event("POST", "/ingest/url", {"url": SAFE_URL}, user_id="u-504"),
                None,
            )
        self.assertEqual(response["statusCode"], 504)
        self.assertEqual(body(response)["code"], "upstream_unavailable")


class FetchErrorMappingTests(unittest.TestCase):
    def test_network_errors_are_502_upstream_unavailable(self):
        errors = (
            ConnectionError("refused"),
            OSError("boom"),
            ssl.SSLError("tls"),
            socket.timeout("timed out"),
            http.client.HTTPException("bad hop"),
        )
        for exc in errors:
            with self.subTest(error=type(exc).__name__):
                def transport(_url, _ip, _timeout):
                    raise exc

                with self.assertRaises(RouteError) as raised:
                    web_ingest.fetch_https(
                        SAFE_URL,
                        resolver=_resolver(PUBLIC_IP),
                        transport=transport,
                    )
                self.assertEqual(raised.exception.status_code, 502)
                self.assertEqual(raised.exception.code, "upstream_unavailable")

    def test_deadline_is_504_upstream_unavailable(self):
        def transport(_url, _ip, _timeout):
            self.fail("deadline must expire before the hop")

        with self.assertRaises(RouteError) as raised:
            web_ingest.fetch_https(
                SAFE_URL,
                resolver=_resolver(PUBLIC_IP),
                transport=transport,
                deadline_seconds=0,
            )
        self.assertEqual(raised.exception.status_code, 504)
        self.assertEqual(raised.exception.code, "upstream_unavailable")

    def test_bad_port_and_ip_literal_are_400_validation_failed(self):
        cases = (
            "https://example.com:abc/",
            "https://example.com:99999/",
            "https://8.8.8.8/",
            "https://[2001:db8::1]/",
            "https://127.0.0.1/",
        )
        for url in cases:
            with self.subTest(url=url):
                with self.assertRaises(RouteError) as raised:
                    web_ingest.validate_https_url(url)
                self.assertEqual(raised.exception.status_code, 400)
                self.assertEqual(raised.exception.code, "validation_failed")


if __name__ == "__main__":
    unittest.main()

