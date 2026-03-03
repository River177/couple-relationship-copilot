import base64
import hashlib
import hmac
import json
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status

from app.core.config import settings


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("utf-8")


def _b64url_decode(data: str) -> bytes:
    padding = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + padding)


def _json_dumps(data: dict) -> bytes:
    return json.dumps(data, separators=(",", ":")).encode("utf-8")


def create_access_token(user_id: str, session_id: str) -> tuple[str, int]:
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=settings.access_token_ttl_sec)
    payload = {
        "sub": user_id,
        "sid": session_id,
        "exp": int(expires_at.timestamp()),
    }
    header = {"alg": "HS256", "typ": "JWT"}

    h = _b64url_encode(_json_dumps(header))
    p = _b64url_encode(_json_dumps(payload))
    signing_input = f"{h}.{p}".encode("utf-8")
    sig = hmac.new(settings.jwt_secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    token = f"{h}.{p}.{_b64url_encode(sig)}"
    return token, settings.access_token_ttl_sec


def decode_access_token(token: str) -> dict:
    try:
        h, p, s = token.split(".")
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="INVALID_TOKEN") from exc

    signing_input = f"{h}.{p}".encode("utf-8")
    expected_sig = hmac.new(settings.jwt_secret.encode("utf-8"), signing_input, hashlib.sha256).digest()

    if not hmac.compare_digest(expected_sig, _b64url_decode(s)):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="INVALID_TOKEN")

    try:
        payload = json.loads(_b64url_decode(p))
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="INVALID_TOKEN") from exc

    exp = payload.get("exp")
    if not isinstance(exp, int) or exp < int(datetime.now(timezone.utc).timestamp()):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="TOKEN_EXPIRED")

    if not payload.get("sub") or not payload.get("sid"):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="INVALID_TOKEN")

    return payload


def generate_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def generate_login_code() -> str:
    # 6-digit verification code
    return f"{secrets.randbelow(900000) + 100000}"
