import time
import unittest

from _support import ensure_api_on_path

ensure_api_on_path()

from ai_router import AIRouter, MAX_PACKAGE_BYTES, RouteRequest  # noqa: E402


class FakeGateway:
    def __init__(
        self,
        responses=None,
        previews=None,
        consensus_answer=None,
        preview_errors=None,
        head_sizes=None,
        head_errors=None,
        consensus_error=None,
    ):
        self.responses = responses or {}
        self.previews = previews or {}
        self.consensus_answer = consensus_answer
        self.preview_errors = preview_errors or {}
        self.head_sizes = head_sizes or {}
        self.head_errors = head_errors or {}
        self.consensus_error = consensus_error
        self.calls = []

    def converse(self, *, model_id, system_prompt, user_prompt, max_tokens, temperature, request_timeout_seconds=None):
        call_kind = "consensus" if "consensus finalizer" in system_prompt else "model"
        self.calls.append(
            {
                "kind": call_kind,
                "model_id": model_id,
                "system_prompt": system_prompt,
                "user_prompt": user_prompt,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "request_timeout_seconds": request_timeout_seconds,
            }
        )
        if call_kind == "consensus":
            if self.consensus_error:
                raise RuntimeError(self.consensus_error)
            return {
                "answer": self.consensus_answer if self.consensus_answer is not None else "consensus answer",
                "usage": {"inputTokens": 10, "outputTokens": 20},
            }
        config = self.responses[model_id]
        time.sleep(config.get("delay", 0))
        if config.get("error"):
            raise RuntimeError(config["error"])
        return {
            "answer": config.get("answer", ""),
            "usage": config.get("usage", {"inputTokens": 10, "outputTokens": 20}),
        }

    def load_preview(self, *, s3_key, max_bytes):
        if s3_key in self.preview_errors:
            raise RuntimeError(self.preview_errors[s3_key])
        return self.previews[s3_key][:max_bytes]

    def head_object_size(self, *, s3_key):
        if s3_key in self.head_errors:
            raise RuntimeError(self.head_errors[s3_key])
        return self.head_sizes[s3_key]


class AIRouterTests(unittest.TestCase):
    def test_model_count_scales_with_package_size(self):
        router = AIRouter(gateway=FakeGateway())

        self.assertEqual(router.model_count_for_package_size(1), 1)
        self.assertEqual(router.model_count_for_package_size(4 * 1024 * 1024 * 1024), 2)
        self.assertEqual(router.model_count_for_package_size(8 * 1024 * 1024 * 1024), 3)

    def test_router_escalates_to_second_model_after_primary_timeout(self):
        gateway = FakeGateway(
            responses={
                "anthropic.claude-sonnet-4-6": {"delay": 0.25, "answer": "late sonnet answer"},
                "anthropic.claude-opus-4-7": {"delay": 0.01, "answer": "opus fallback answer"},
                "moonshotai.kimi-k2.5": {"delay": 0.01, "answer": "kimi answer"},
            },
            consensus_answer="consensus from sonnet and opus",
        )
        router = AIRouter(gateway=gateway)
        request = RouteRequest.from_payload(
            {
                "question": "What should I do next?",
                "packageSizeBytes": 1024,
                "settings": {
                    "modelTimeoutSeconds": 0.1,
                    "overallTimeoutSeconds": 0.6,
                    "consensusWindowSeconds": 0.2,
                },
            }
        )

        response = router.route(request)

        self.assertEqual(response["selectedModel"]["slot"], 2)
        self.assertEqual(response["routing"]["launchedModelCount"], 2)
        self.assertEqual(response["finalAnswer"], "consensus from sonnet and opus")
        self.assertEqual(response["answer"], "consensus from sonnet and opus")
        self.assertEqual(response["finalAnswerSource"]["mode"], "2-model-consensus")
        self.assertEqual(response["finalAnswerSource"]["usedModelCount"], 2)
        self.assertEqual(len(gateway.calls), 3)
        self.assertEqual(gateway.calls[-1]["kind"], "consensus")

    def test_large_package_starts_three_models_immediately(self):
        gateway = FakeGateway(
            responses={
                "anthropic.claude-sonnet-4-6": {"delay": 0.1, "answer": "sonnet answer"},
                "anthropic.claude-opus-4-7": {"delay": 0.05, "answer": "opus answer"},
                "moonshotai.kimi-k2.5": {"delay": 0.08, "answer": "kimi answer"},
            },
            consensus_answer="consensus from all three models",
        )
        router = AIRouter(gateway=gateway)
        request = RouteRequest.from_payload(
            {
                "question": "Summarize the uploaded health data.",
                "packageSizeBytes": 9 * 1024 * 1024 * 1024,
                "settings": {
                    "overallTimeoutSeconds": 0.5,
                    "consensusWindowSeconds": 0.12,
                },
            }
        )

        response = router.route(request)

        self.assertEqual(response["routing"]["initialParallelism"], 3)
        self.assertEqual(response["routing"]["launchedModelCount"], 3)
        self.assertEqual(response["finalAnswer"], "consensus from all three models")
        self.assertEqual(response["finalAnswerSource"]["mode"], "3-model-consensus")
        self.assertEqual(response["finalAnswerSource"]["usedModelCount"], 3)
        self.assertEqual(len(gateway.calls), 4)
        self.assertEqual(response["selectedModel"]["slot"], 2)

    def test_router_uses_s3_preview_when_inline_preview_is_missing(self):
        gateway = FakeGateway(
            responses={
                "anthropic.claude-sonnet-4-6": {"delay": 0.01, "answer": "answer"},
                "anthropic.claude-opus-4-7": {"delay": 0.01, "answer": "backup"},
                "moonshotai.kimi-k2.5": {"delay": 0.01, "answer": "backup 2"},
            },
            previews={
                "private/user/metrics.txt": "resting HR 52, HRV 71, sleep efficiency 92%",
            },
        )
        router = AIRouter(gateway=gateway)
        request = RouteRequest.from_payload(
            {
                "question": "What stands out from this data?",
                "packages": [
                    {
                        "id": "metrics",
                        "bytes": 2048,
                        "s3Key": "private/user/metrics.txt",
                    }
                ],
                "settings": {
                    "overallTimeoutSeconds": 0.3,
                    "consensusWindowSeconds": 0.01,
                },
            }
        )

        response = router.route(request)

        self.assertIn("resting HR 52", gateway.calls[0]["user_prompt"])
        self.assertEqual(response["finalAnswer"], "answer")
        self.assertEqual(response["finalAnswerSource"]["mode"], "single-model")
        self.assertEqual(response["finalAnswerSource"]["usedModelCount"], 1)
        self.assertEqual(len(gateway.calls), 1)

    def test_router_falls_back_to_fastest_successful_answer_if_consensus_fails(self):
        gateway = FakeGateway(
            responses={
                "anthropic.claude-sonnet-4-6": {"delay": 0.04, "answer": "sonnet answer"},
                "anthropic.claude-opus-4-7": {"delay": 0.01, "answer": "opus answer"},
                "moonshotai.kimi-k2.5": {"delay": 0.01, "answer": "kimi answer"},
            },
            consensus_answer="",
        )
        router = AIRouter(gateway=gateway)
        request = RouteRequest.from_payload(
            {
                "question": "What is the safest next step?",
                "packageSizeBytes": 4 * 1024 * 1024 * 1024,
                "settings": {
                    "overallTimeoutSeconds": 0.4,
                    "consensusWindowSeconds": 0.08,
                },
            }
        )

        response = router.route(request)

        self.assertEqual(response["finalAnswer"], "opus answer")
        self.assertTrue(response["finalAnswerSource"]["fallbackUsed"])
        self.assertEqual(response["finalAnswerSource"]["fallbackReason"], "consensus_failed")
        self.assertIn("Consensus finalization failed", response["warnings"][0])

    def test_router_skips_consensus_when_remaining_budget_is_too_small(self):
        gateway = FakeGateway(
            responses={
                "anthropic.claude-sonnet-4-6": {"delay": 0.35, "answer": "sonnet answer"},
                "anthropic.claude-opus-4-7": {"delay": 0.01, "answer": "opus answer"},
                "moonshotai.kimi-k2.5": {"delay": 0.01, "answer": "kimi answer"},
            },
            consensus_answer="should not be used",
        )
        router = AIRouter(gateway=gateway)
        request = RouteRequest.from_payload(
            {
                "question": "What should I do next?",
                "packageSizeBytes": 1024,
                "settings": {
                    "modelTimeoutSeconds": 0.1,
                    "overallTimeoutSeconds": 0.5,
                    "consensusWindowSeconds": 0.35,
                },
            }
        )

        response = router.route(request)

        self.assertEqual(response["finalAnswer"], "opus answer")
        self.assertTrue(response["finalAnswerSource"]["fallbackUsed"])
        self.assertEqual(response["finalAnswerSource"]["fallbackReason"], "timeout_budget_exhausted")
        self.assertNotEqual(gateway.calls[-1]["kind"], "consensus")
        self.assertIn("remaining time budget was too small", response["warnings"][0])

    def test_router_degrades_gracefully_when_s3_preview_load_fails(self):
        gateway = FakeGateway(
            responses={
                "anthropic.claude-sonnet-4-6": {"delay": 0.01, "answer": "answer"},
                "anthropic.claude-opus-4-7": {"delay": 0.01, "answer": "backup"},
                "moonshotai.kimi-k2.5": {"delay": 0.01, "answer": "backup 2"},
            },
            preview_errors={
                "private/user/metrics.txt": "missing key",
            },
        )
        router = AIRouter(gateway=gateway)
        request = RouteRequest.from_payload(
            {
                "question": "What stands out from this data?",
                "packages": [
                    {
                        "id": "metrics",
                        "bytes": 2048,
                        "s3Key": "private/user/metrics.txt",
                    }
                ],
            }
        )

        response = router.route(request)

        self.assertEqual(response["finalAnswer"], "answer")
        self.assertIn("Could not load preview for package 'metrics'", response["warnings"][0])

    def test_router_uses_head_object_size_to_scale_initial_fanout(self):
        gateway = FakeGateway(
            responses={
                "anthropic.claude-sonnet-4-6": {"delay": 0.04, "answer": "sonnet answer"},
                "anthropic.claude-opus-4-7": {"delay": 0.02, "answer": "opus answer"},
                "moonshotai.kimi-k2.5": {"delay": 0.03, "answer": "kimi answer"},
            },
            consensus_answer="consensus from inferred size",
            head_sizes={
                "private/user/export.csv": 9 * 1024 * 1024 * 1024,
            },
            previews={
                "private/user/export.csv": "preview text",
            },
        )
        router = AIRouter(gateway=gateway)
        request = RouteRequest.from_payload(
            {
                "question": "Summarize the data.",
                "packages": [
                    {
                        "id": "export",
                        "s3Key": "private/user/export.csv",
                    }
                ],
                "settings": {
                    "overallTimeoutSeconds": 0.5,
                    "consensusWindowSeconds": 0.05,
                },
            }
        )

        response = router.route(request)

        self.assertEqual(response["routing"]["initialParallelism"], 3)
        self.assertEqual(response["routing"]["packageSizeBytes"], 9 * 1024 * 1024 * 1024)
        self.assertEqual(response["finalAnswer"], "consensus from inferred size")

    def test_router_warns_when_s3_object_size_inference_fails(self):
        gateway = FakeGateway(
            responses={
                "anthropic.claude-sonnet-4-6": {"delay": 0.01, "answer": "answer"},
                "anthropic.claude-opus-4-7": {"delay": 0.01, "answer": "backup"},
                "moonshotai.kimi-k2.5": {"delay": 0.01, "answer": "backup 2"},
            },
            head_errors={
                "private/user/export.csv": "access denied",
            },
            previews={
                "private/user/export.csv": "preview text",
            },
        )
        router = AIRouter(gateway=gateway)
        request = RouteRequest.from_payload(
            {
                "question": "Summarize the data.",
                "packages": [
                    {
                        "id": "export",
                        "s3Key": "private/user/export.csv",
                    }
                ],
            }
        )

        response = router.route(request)

        self.assertEqual(response["routing"]["initialParallelism"], 1)
        self.assertIn("Could not infer size for package 'export'", response["warnings"][0])

    def test_request_rejects_packages_over_ten_gigabytes(self):
        with self.assertRaises(Exception) as context:
            RouteRequest.from_payload(
                {
                    "question": "Analyze everything.",
                    "packageSizeBytes": MAX_PACKAGE_BYTES + 1,
                }
            )

        self.assertIn("10 GB routing limit", str(context.exception))


if __name__ == "__main__":
    unittest.main()
