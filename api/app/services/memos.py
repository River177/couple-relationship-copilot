import json
from urllib import error, request

from app.core.config import settings


def sync_memory(*, source_type: str, source_id: str, couple_id: str, user_id: str, text_body: str, tags: list[str], metadata: dict | None = None) -> tuple[bool, str | None]:
    """Best-effort sync to external MemOS service."""
    if not settings.memos_base_url:
        return False, None

    payload = {
        "user_id": f"{settings.memos_user_id_prefix}:{couple_id}:{user_id}",
        "text": text_body,
        "tags": tags,
        "metadata": {
            "source_type": source_type,
            "source_id": source_id,
            "couple_id": couple_id,
            "user_id": user_id,
            **(metadata or {}),
        },
    }

    body = json.dumps(payload).encode("utf-8")
    url = settings.memos_base_url.rstrip("/") + "/memories"
    headers = {"Content-Type": "application/json"}
    if settings.memos_api_key:
        headers["Authorization"] = f"Bearer {settings.memos_api_key}"

    req = request.Request(url, data=body, headers=headers, method="POST")
    try:
        with request.urlopen(req, timeout=8) as resp:
            raw = resp.read().decode("utf-8") if resp.readable() else ""
            data = json.loads(raw) if raw else {}
            ref_id = data.get("id") or data.get("memory_id")
            return True, ref_id
    except (error.URLError, TimeoutError, json.JSONDecodeError):
        return False, None


def sync_daily_memory(*, couple_id: str, author_user_id: str, entry_id: str, text_body: str, tags: list[str]) -> tuple[bool, str | None]:
    return sync_memory(
        source_type="daily",
        source_id=entry_id,
        couple_id=couple_id,
        user_id=author_user_id,
        text_body=text_body,
        tags=tags,
        metadata={"author_user_id": author_user_id},
    )
