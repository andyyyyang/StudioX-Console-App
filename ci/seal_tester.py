#!/usr/bin/env python3
"""
把一位測試員加密成 ci/testers.enc 的一行（repo 裡只有密文，看不到 Email）。
只有拿得到 ASC_PRIVATE_KEY 的 GitHub Actions（ci/asc.py 的 sealed_testers）解得開。

  python3 ci/seal_tester.py <公鑰> "王小明 <ming@example.com>" >> ci/testers.enc

公鑰印在 Actions →「TestFlight 邀請」的摘要（python3 ci/asc.py pubkey）。需要 pip install cryptography。
"""
import base64
import os
import sys

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

INFO = b"studiox-testflight-testers-v1"


def seal(public_b64: str, text: str) -> str:
    recipient = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), base64.b64decode(public_b64))
    ephemeral = ec.generate_private_key(ec.SECP256R1())
    shared = ephemeral.exchange(ec.ECDH(), recipient)
    key = HKDF(algorithm=hashes.SHA256(), length=32, salt=None, info=INFO).derive(shared)
    nonce = os.urandom(12)
    point = ephemeral.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
    return base64.b64encode(point + nonce + AESGCM(key).encrypt(nonce, text.encode("utf-8"), INFO)).decode()


if __name__ == "__main__":
    if len(sys.argv) != 3 or "@" not in sys.argv[2]:
        sys.exit(__doc__)
    print(seal(sys.argv[1], sys.argv[2].strip()))
