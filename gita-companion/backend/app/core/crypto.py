"""Encryption at rest for personal free text (notes, journal).

AES-256-GCM with a key derived from DATA_ENCRYPTION_KEY. The user id and
the field name are bound as associated data, so a ciphertext cannot be moved
to another account or column. Stored as "v1:<base64(nonce || ciphertext)>".
Values without the prefix are plaintext (written before a key was set, or in
development without a key) and are returned as they are.
"""

from __future__ import annotations

import base64
import hashlib
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

PREFIX = "v1:"


class FieldCipher:
    def __init__(self, secret: str | None):
        self._aead = AESGCM(hashlib.sha256(secret.encode()).digest()) if secret else None

    @property
    def enabled(self) -> bool:
        return self._aead is not None

    def encrypt(self, value: str | None, *, owner: str, field: str) -> str | None:
        if value is None or self._aead is None:
            return value
        nonce = os.urandom(12)
        ct = self._aead.encrypt(nonce, value.encode(), f"{owner}|{field}".encode())
        return PREFIX + base64.b64encode(nonce + ct).decode()

    def decrypt(self, value: str | None, *, owner: str, field: str) -> str | None:
        if value is None or not value.startswith(PREFIX):
            return value
        if self._aead is None:
            raise RuntimeError("encrypted data found but DATA_ENCRYPTION_KEY is not set")
        raw = base64.b64decode(value[len(PREFIX) :])
        return self._aead.decrypt(raw[:12], raw[12:], f"{owner}|{field}".encode()).decode()
