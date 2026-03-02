import json
from datetime import datetime

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db import get_db
from app.services.memos import sync_memory

router = APIRouter()


class ConflictInputIn(BaseModel):
    session_id: str
    user_id: str
    facts: str
    feelings: str
    needs: str
    expectation: str | None = None
    emotion_score: int = Field(ge=1, le=10)


@router.post("/session")
def create_conflict_session(couple_id: str, db: Session = Depends(get_db)):
    row = db.execute(
        text(
            """
            INSERT INTO conflict_sessions (couple_id)
            VALUES (:couple_id::uuid)
            RETURNING id::text, couple_id::text, status, risk_level, created_at
            """
        ),
        {"couple_id": couple_id},
    ).mappings().one()

    memory_text = f"[conflict_session] new session created for couple={row['couple_id']}"
    db.execute(
        text(
            """
            INSERT INTO memory_items (
                couple_id, source_type, source_id, tags, text_body, happened_at, memos_status
            ) VALUES (
                :couple_id::uuid, 'conflict_input', :source_id::uuid, :tags, :text_body, NOW(), 'pending'
            )
            ON CONFLICT (source_type, source_id)
            DO UPDATE SET text_body=EXCLUDED.text_body, tags=EXCLUDED.tags, memos_status='pending'
            """
        ),
        {
            "couple_id": row["couple_id"],
            "source_id": row["id"],
            "tags": ["conflict", "session_created"],
            "text_body": memory_text,
        },
    )

    db.commit()

    ok, ref_id = sync_memory(
        source_type="conflict_input",
        source_id=row["id"],
        couple_id=row["couple_id"],
        user_id="system",
        text_body=memory_text,
        tags=["conflict", "session_created"],
        metadata={"session_id": row["id"]},
    )
    db.execute(
        text(
            """
            UPDATE memory_items
            SET memos_status=:status, memos_ref_id=COALESCE(:ref_id, memos_ref_id)
            WHERE source_type='conflict_input' AND source_id=:source_id::uuid
            """
        ),
        {"status": "synced" if ok else "failed", "ref_id": ref_id, "source_id": row["id"]},
    )
    db.commit()

    return row


@router.post("/input")
def submit_conflict_input(payload: ConflictInputIn, db: Session = Depends(get_db)):
    row = db.execute(
        text(
            """
            INSERT INTO conflict_inputs (
                session_id, user_id, facts, feelings, needs, expectation, emotion_score
            ) VALUES (
                :session_id::uuid, :user_id::uuid, :facts, :feelings, :needs, :expectation, :emotion_score
            )
            ON CONFLICT (session_id, user_id)
            DO UPDATE SET
                facts = EXCLUDED.facts,
                feelings = EXCLUDED.feelings,
                needs = EXCLUDED.needs,
                expectation = EXCLUDED.expectation,
                emotion_score = EXCLUDED.emotion_score,
                updated_at = NOW()
            RETURNING id::text, session_id::text, user_id::text, created_at
            """
        ),
        payload.model_dump(),
    ).mappings().one()

    session_row = db.execute(
        text("SELECT couple_id::text AS couple_id FROM conflict_sessions WHERE id=:sid::uuid"),
        {"sid": payload.session_id},
    ).mappings().first()

    if session_row:
        memory_text = (
            f"[conflict_input] facts={payload.facts}; feelings={payload.feelings}; "
            f"needs={payload.needs}; emotion={payload.emotion_score}"
        )
        tags = ["conflict", "input", f"emotion:{payload.emotion_score}"]
        db.execute(
            text(
                """
                INSERT INTO memory_items (
                    couple_id, user_id, source_type, source_id, scene_session_id, tags,
                    emotion_score, text_body, happened_at, memos_status
                ) VALUES (
                    :couple_id::uuid, :user_id::uuid, 'conflict_input', :source_id::uuid, :scene_session_id::uuid,
                    :tags, :emotion_score, :text_body, NOW(), 'pending'
                )
                ON CONFLICT (source_type, source_id)
                DO UPDATE SET
                    tags=EXCLUDED.tags,
                    emotion_score=EXCLUDED.emotion_score,
                    text_body=EXCLUDED.text_body,
                    memos_status='pending'
                """
            ),
            {
                "couple_id": session_row["couple_id"],
                "user_id": payload.user_id,
                "source_id": row["id"],
                "scene_session_id": payload.session_id,
                "tags": tags,
                "emotion_score": payload.emotion_score,
                "text_body": memory_text,
            },
        )
        db.commit()

        ok, ref_id = sync_memory(
            source_type="conflict_input",
            source_id=row["id"],
            couple_id=session_row["couple_id"],
            user_id=payload.user_id,
            text_body=memory_text,
            tags=tags,
            metadata={"session_id": payload.session_id},
        )
        db.execute(
            text(
                """
                UPDATE memory_items
                SET memos_status=:status, memos_ref_id=COALESCE(:ref_id, memos_ref_id)
                WHERE source_type='conflict_input' AND source_id=:source_id::uuid
                """
            ),
            {"status": "synced" if ok else "failed", "ref_id": ref_id, "source_id": row["id"]},
        )

    db.commit()
    return {"message": "conflict input stored", "data": row}


@router.post("/mediate")
def mediate_conflict(session_id: str, db: Session = Depends(get_db)):
    rows = (
        db.execute(
            text(
                """
                SELECT user_id::text AS user_id, facts, feelings, needs, expectation, emotion_score, created_at
                FROM conflict_inputs
                WHERE session_id = :session_id::uuid
                ORDER BY created_at ASC
                """
            ),
            {"session_id": session_id},
        )
        .mappings()
        .all()
    )

    if not rows:
        return {
            "session_id": session_id,
            "consensus_facts": [],
            "differences": [],
            "needs_translation": [],
            "tonight_action": None,
            "repair_plan_72h": [],
            "note": "No conflict inputs yet",
        }

    needs_translation = [
        {"user_id": r["user_id"], "needs": r["needs"], "emotion_score": r["emotion_score"]}
        for r in rows
    ]

    max_emotion = max(r["emotion_score"] for r in rows)
    tonight_action = "暂停争执，约定20分钟后再沟通" if max_emotion >= 8 else "先复述对方需求，再讨论解决方案"

    result = {
        "session_id": session_id,
        "consensus_facts": [r["facts"] for r in rows if r["facts"]],
        "differences": [r["feelings"] for r in rows if r["feelings"]],
        "needs_translation": needs_translation,
        "tonight_action": tonight_action,
        "repair_plan_72h": [
            {"title": "24小时内一次20分钟无打断沟通", "due_at": (datetime.utcnow()).isoformat()},
            {"title": "48小时内完成一次共同活动", "due_at": (datetime.utcnow()).isoformat()},
            {"title": "72小时回顾这次冲突触发点", "due_at": (datetime.utcnow()).isoformat()},
        ],
    }

    session_row = db.execute(
        text("SELECT couple_id::text AS couple_id FROM conflict_sessions WHERE id=:sid::uuid"),
        {"sid": session_id},
    ).mappings().first()

    if session_row:
        med_row = db.execute(
            text(
                """
                INSERT INTO conflict_mediations (
                    session_id, version, consensus_facts, differences, needs_translation, tonight_action, repair_plan_72h
                ) VALUES (
                    :session_id::uuid,
                    COALESCE((SELECT MAX(version)+1 FROM conflict_mediations WHERE session_id=:session_id::uuid), 1),
                    CAST(:consensus_facts AS jsonb),
                    CAST(:differences AS jsonb),
                    CAST(:needs_translation AS jsonb),
                    :tonight_action,
                    CAST(:repair_plan_72h AS jsonb)
                )
                RETURNING id::text
                """
            ),
            {
                "session_id": session_id,
                "consensus_facts": json.dumps(result["consensus_facts"]),
                "differences": json.dumps(result["differences"]),
                "needs_translation": json.dumps(result["needs_translation"]),
                "tonight_action": result["tonight_action"],
                "repair_plan_72h": json.dumps(result["repair_plan_72h"]),
            },
        ).mappings().one()

        memory_text = f"[conflict_mediation] action={result['tonight_action']}"
        db.execute(
            text(
                """
                INSERT INTO memory_items (
                    couple_id, source_type, source_id, scene_session_id, tags, text_body, happened_at, memos_status
                ) VALUES (
                    :couple_id::uuid, 'mediation', :source_id::uuid, :scene_session_id::uuid,
                    :tags, :text_body, NOW(), 'pending'
                )
                ON CONFLICT (source_type, source_id)
                DO UPDATE SET tags=EXCLUDED.tags, text_body=EXCLUDED.text_body, memos_status='pending'
                """
            ),
            {
                "couple_id": session_row["couple_id"],
                "source_id": med_row["id"],
                "scene_session_id": session_id,
                "tags": ["conflict", "mediation"],
                "text_body": memory_text,
            },
        )
        db.commit()

        ok, ref_id = sync_memory(
            source_type="mediation",
            source_id=med_row["id"],
            couple_id=session_row["couple_id"],
            user_id="system",
            text_body=memory_text,
            tags=["conflict", "mediation"],
            metadata={"session_id": session_id},
        )
        db.execute(
            text(
                """
                UPDATE memory_items
                SET memos_status=:status, memos_ref_id=COALESCE(:ref_id, memos_ref_id)
                WHERE source_type='mediation' AND source_id=:source_id::uuid
                """
            ),
            {"status": "synced" if ok else "failed", "ref_id": ref_id, "source_id": med_row["id"]},
        )
        db.commit()

    return result
