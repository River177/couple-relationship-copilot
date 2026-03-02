from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db import get_db
from app.services.memos import sync_daily_memory

router = APIRouter()


class DailyMediaIn(BaseModel):
    media_type: Literal["image", "video"]
    url: str
    cover_url: str | None = None
    duration_sec: int | None = None
    width: int | None = None
    height: int | None = None
    size_bytes: int | None = None
    sort_order: int = Field(default=0, ge=0)


class DailyEntryIn(BaseModel):
    couple_id: str
    author_user_id: str
    event_type: Literal["date", "gift", "interaction", "other"] = "other"
    mood_score: int = Field(ge=1, le=5)
    content: str
    event_time: datetime | None = None
    media: list[DailyMediaIn] = Field(default_factory=list)


class DailyMediaOut(BaseModel):
    id: str
    media_type: str
    url: str
    cover_url: str | None = None
    duration_sec: int | None = None
    width: int | None = None
    height: int | None = None
    size_bytes: int | None = None
    sort_order: int


class DailyEntryOut(BaseModel):
    id: str
    couple_id: str
    author_user_id: str
    event_type: str
    mood_score: int
    content: str
    event_time: datetime
    created_at: datetime
    memos_status: str | None = None
    memos_ref_id: str | None = None
    media: list[DailyMediaOut] = Field(default_factory=list)


@router.post("", response_model=DailyEntryOut)
def create_daily_entry(payload: DailyEntryIn, db: Session = Depends(get_db)):
    entry_payload = payload.model_dump(exclude={"media"})

    row = db.execute(
        text(
            """
            INSERT INTO daily_entries (
              couple_id, author_user_id, event_type, mood_score, content, event_time
            )
            VALUES (
              :couple_id::uuid, :author_user_id::uuid, :event_type, :mood_score, :content, COALESCE(:event_time, NOW())
            )
            RETURNING id::text, couple_id::text, author_user_id::text, event_type, mood_score, content, event_time, created_at
            """
        ),
        entry_payload,
    ).mappings().one()

    media_rows = []
    for m in payload.media:
        media_row = db.execute(
            text(
                """
                INSERT INTO daily_media (
                    entry_id, media_type, url, cover_url, duration_sec, width, height, size_bytes, sort_order
                ) VALUES (
                    :entry_id::uuid, :media_type, :url, :cover_url, :duration_sec, :width, :height, :size_bytes, :sort_order
                )
                RETURNING id::text, media_type, url, cover_url, duration_sec, width, height, size_bytes, sort_order
                """
            ),
            {"entry_id": row["id"], **m.model_dump()},
        ).mappings().one()
        media_rows.append(media_row)

    # local memory index (for retrieval/traceability)
    memory_text = f"[{row['event_type']}] mood={row['mood_score']} content={row['content']}"
    tags = ["daily", row["event_type"], f"mood:{row['mood_score']}"]

    db.execute(
        text(
            """
            INSERT INTO memory_items (
                couple_id, user_id, source_type, source_id, tags, emotion_score, text_body, happened_at, memos_status
            ) VALUES (
                :couple_id::uuid, :user_id::uuid, 'daily', :source_id::uuid, :tags, :emotion_score, :text_body, :happened_at, 'pending'
            )
            ON CONFLICT (source_type, source_id)
            DO UPDATE SET
                tags = EXCLUDED.tags,
                emotion_score = EXCLUDED.emotion_score,
                text_body = EXCLUDED.text_body,
                happened_at = EXCLUDED.happened_at,
                memos_status = 'pending'
            """
        ),
        {
            "couple_id": row["couple_id"],
            "user_id": row["author_user_id"],
            "source_id": row["id"],
            "tags": tags,
            "emotion_score": row["mood_score"],
            "text_body": memory_text,
            "happened_at": row["event_time"],
        },
    )

    db.commit()

    # external MemOS sync (best effort, never breaks write path)
    ok, ref_id = sync_daily_memory(
        couple_id=row["couple_id"],
        author_user_id=row["author_user_id"],
        entry_id=row["id"],
        text_body=memory_text,
        tags=tags,
    )

    db.execute(
        text(
            """
            UPDATE memory_items
            SET memos_status = :status,
                memos_ref_id = COALESCE(:ref_id, memos_ref_id)
            WHERE source_type = 'daily' AND source_id = :source_id::uuid
            """
        ),
        {"status": "synced" if ok else "failed", "ref_id": ref_id, "source_id": row["id"]},
    )
    db.commit()

    mem_row = db.execute(
        text(
            """
            SELECT memos_status, memos_ref_id
            FROM memory_items
            WHERE source_type = 'daily' AND source_id = :source_id::uuid
            """
        ),
        {"source_id": row["id"]},
    ).mappings().first()

    return DailyEntryOut(
        **row,
        memos_status=mem_row["memos_status"] if mem_row else None,
        memos_ref_id=mem_row["memos_ref_id"] if mem_row else None,
        media=[DailyMediaOut(**m) for m in media_rows],
    )


@router.get("/timeline")
def get_timeline(couple_id: str, limit: int = 20, db: Session = Depends(get_db)):
    entry_rows = (
        db.execute(
            text(
                """
                SELECT
                    de.id::text,
                    de.couple_id::text,
                    de.author_user_id::text,
                    de.event_type,
                    de.mood_score,
                    de.content,
                    de.event_time,
                    de.created_at,
                    mi.memos_status,
                    mi.memos_ref_id
                FROM daily_entries de
                LEFT JOIN memory_items mi
                  ON mi.source_type = 'daily' AND mi.source_id = de.id
                WHERE de.couple_id = :couple_id::uuid
                ORDER BY de.event_time DESC
                LIMIT :limit
                """
            ),
            {"couple_id": couple_id, "limit": min(max(limit, 1), 100)},
        )
        .mappings()
        .all()
    )

    if not entry_rows:
        return {"couple_id": couple_id, "items": []}

    entry_ids = [r["id"] for r in entry_rows]
    media_rows = (
        db.execute(
            text(
                """
                SELECT id::text, entry_id::text, media_type, url, cover_url, duration_sec, width, height, size_bytes, sort_order
                FROM daily_media
                WHERE entry_id = ANY(:entry_ids::uuid[])
                ORDER BY sort_order ASC, created_at ASC
                """
            ),
            {"entry_ids": entry_ids},
        )
        .mappings()
        .all()
    )

    media_map: dict[str, list[DailyMediaOut]] = {}
    for m in media_rows:
        media_map.setdefault(m["entry_id"], []).append(
            DailyMediaOut(
                id=m["id"],
                media_type=m["media_type"],
                url=m["url"],
                cover_url=m["cover_url"],
                duration_sec=m["duration_sec"],
                width=m["width"],
                height=m["height"],
                size_bytes=m["size_bytes"],
                sort_order=m["sort_order"],
            )
        )

    items = [
        DailyEntryOut(**r, media=media_map.get(r["id"], [])).model_dump()
        for r in entry_rows
    ]
    return {"couple_id": couple_id, "items": items}
