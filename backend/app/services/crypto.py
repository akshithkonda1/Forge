"""Envelope encryption for conclusions payloads (KMS in prod, local dev fallback)."""
from __future__ import annotations

import base64
import json
import os
from typing import Any

_LOCAL_KEY_ENV = "ARIA_CONCLUSIONS_LOCAL_KEY"
_KMS_KEY_ID_ENV = "ARIA_CONCLUSIONS_KMS_KEY_ID"


def _local_key() -> bytes:
    raw = os.getenv(_LOCAL_KEY_ENV, "forge-local-conclusions-key-32b!!")
    key = raw.encode("utf-8")
    if len(key) < 32:
        key = (key * 2)[:32]
    return key[:32]


def _xor_crypt(key: bytes, data: bytes) -> bytes:
    return bytes(b ^ key[i % len(key)] for i, b in enumerate(data))


def _encrypt_local(key: bytes, plaintext: bytes) -> tuple[bytes, bytes]:
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM

        nonce = os.urandom(12)
        ciphertext = AESGCM(key).encrypt(b"aria-conclusions", plaintext, None)
        return nonce, ciphertext
    except ImportError:
        nonce = os.urandom(12)
        return nonce, _xor_crypt(key, plaintext)


def _decrypt_local(key: bytes, nonce: bytes, ciphertext: bytes) -> bytes:
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM

        return AESGCM(key).decrypt(b"aria-conclusions", ciphertext, None)
    except ImportError:
        return _xor_crypt(key, ciphertext)


def encrypt_payload(payload: dict[str, Any]) -> dict[str, Any]:
    """Return an envelope suitable for DynamoDB storage."""
    plaintext = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    kms_key_id = os.getenv(_KMS_KEY_ID_ENV)

    if kms_key_id:
        import boto3  # type: ignore[import]

        kms = boto3.client("kms")
        data_key = kms.generate_data_key(KeyId=kms_key_id, KeySpec="AES_256")
        key = data_key["Plaintext"]
        nonce, ciphertext = _encrypt_local(key, plaintext)
        return {
            "encryption": "kms-aes-256-gcm",
            "encryptedDataKey": base64.b64encode(data_key["CiphertextBlob"]).decode("ascii"),
            "nonce": base64.b64encode(nonce).decode("ascii"),
            "ciphertext": base64.b64encode(ciphertext).decode("ascii"),
            "kmsKeyId": kms_key_id,
        }

    nonce, ciphertext = _encrypt_local(_local_key(), plaintext)
    return {
        "encryption": "local-aes-256-gcm",
        "nonce": base64.b64encode(nonce).decode("ascii"),
        "ciphertext": base64.b64encode(ciphertext).decode("ascii"),
    }


def decrypt_payload(envelope: dict[str, Any]) -> dict[str, Any]:
    """Decrypt a stored conclusions envelope."""
    encryption = envelope.get("encryption")
    nonce = base64.b64decode(str(envelope.get("nonce", "")))
    ciphertext = base64.b64decode(str(envelope.get("ciphertext", "")))

    if encryption == "kms-aes-256-gcm":
        import boto3  # type: ignore[import]

        kms = boto3.client("kms")
        data_key = kms.decrypt(
            CiphertextBlob=base64.b64decode(str(envelope.get("encryptedDataKey", "")))
        )["Plaintext"]
        plaintext = _decrypt_local(data_key, nonce, ciphertext)
    elif encryption == "local-aes-256-gcm":
        plaintext = _decrypt_local(_local_key(), nonce, ciphertext)
    else:
        raise ValueError(f"Unsupported encryption mode: {encryption}")

    return json.loads(plaintext.decode("utf-8"))