"""Minimal Bedrock Converse client for opt-in real-model grading.

`boto3` is imported lazily so the default/offline path never touches it. Mirrors
the gateway in `infra/terraform/lambda/ai_router.py:BedrockGateway.converse`. Any
failure raises, and the caller (ARIAEngine.respond) falls back to the stub.
"""

from __future__ import annotations

import os


class BedrockUnavailable(RuntimeError):
    pass


def converse(
    model_id: str,
    system_prompt: str,
    user_prompt: str,
    *,
    max_tokens: int = 700,
    temperature: float = 0.3,
    region: str | None = None,
) -> str:
    """Call Bedrock Converse and return the assistant text. Lazy boto3."""
    try:
        import boto3  # lazy: only on the opt-in real-API path
    except ModuleNotFoundError as exc:
        raise BedrockUnavailable("boto3 is not installed") from exc

    client = boto3.client("bedrock-runtime", region_name=region or os.getenv("AWS_REGION", "us-east-1"))
    response = client.converse(
        modelId=model_id,
        system=[{"text": system_prompt}],
        messages=[{"role": "user", "content": [{"text": user_prompt}]}],
        inferenceConfig={"maxTokens": max_tokens, "temperature": temperature},
    )
    blocks = response.get("output", {}).get("message", {}).get("content", [])
    text = "\n".join(b.get("text", "") for b in blocks if isinstance(b, dict) and b.get("text")).strip()
    if not text:
        raise BedrockUnavailable("empty response from Bedrock")
    return text
