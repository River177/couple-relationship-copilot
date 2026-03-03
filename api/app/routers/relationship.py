import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps.auth import get_current_user

router = APIRouter()


class JoinInviteIn(BaseModel):
    invite_code: str


class UnbindIn(BaseModel):
    confirm_text: str


def _new_invite_code(size: int = 6) -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "".join(secrets.choice(alphabet) for _ in range(size))


@router.post("/invite")
def create_invite(current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    active_couple = db.execute(
        text(
            """
            SELECT id::text FROM couples
            WHERE status = 'active' AND (user_a_id = CAST(:uid AS uuid) OR user_b_id = CAST(:uid AS uuid))
            LIMIT 1
            """
        ),
        {"uid": current_user["id"]},
    ).mappings().first()

    if active_couple:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="ALREADY_BOUND")

    expires_at = datetime.now(timezone.utc) + timedelta(hours=24)

    for _ in range(5):
        code = _new_invite_code()
        try:
            row = db.execute(
                text(
                    """
                    INSERT INTO relationship_invites (inviter_user_id, invite_code, status, expired_at)
                    VALUES (CAST(:inviter_user_id AS uuid), :invite_code, 'pending', :expired_at)
                    RETURNING invite_code, expired_at
                    """
                ),
                {
                    "inviter_user_id": current_user["id"],
                    "invite_code": code,
                    "expired_at": expires_at,
                },
            ).mappings().one()
            db.commit()
            return {
                "invite_code": row["invite_code"],
                "invite_link": f"/invite/{row['invite_code']}",
                "expires_at": row["expired_at"],
            }
        except IntegrityError:
            db.rollback()
            continue

    raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="INVITE_CREATE_FAILED")


@router.post("/join")
def join_invite(payload: JoinInviteIn, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    code = payload.invite_code.strip().upper()

    try:
        invite = db.execute(
            text(
                """
                SELECT id::text, inviter_user_id::text, status, expired_at
                FROM relationship_invites
                WHERE invite_code = :code
                FOR UPDATE
                """
            ),
            {"code": code},
        ).mappings().first()

        if not invite:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="INVALID_CODE")
        if invite["status"] != "pending":
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="INVITE_USED")
        if invite["expired_at"] <= datetime.now(timezone.utc):
            db.execute(
                text("UPDATE relationship_invites SET status = 'expired' WHERE id = CAST(:id AS uuid)"),
                {"id": invite["id"]},
            )
            db.commit()
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="INVITE_EXPIRED")
        if invite["inviter_user_id"] == current_user["id"]:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="SELF_INVITE_NOT_ALLOWED")

        # lock users to reduce race
        db.execute(text("SELECT id FROM users WHERE id = CAST(:uid AS uuid) FOR UPDATE"), {"uid": current_user["id"]})
        db.execute(text("SELECT id FROM users WHERE id = CAST(:uid AS uuid) FOR UPDATE"), {"uid": invite["inviter_user_id"]})

        exists = db.execute(
            text(
                """
                SELECT id::text
                FROM couples
                WHERE status = 'active'
                  AND (
                    user_a_id IN (CAST(:uid AS uuid), CAST(:inviter AS uuid))
                    OR user_b_id IN (CAST(:uid AS uuid), CAST(:inviter AS uuid))
                  )
                LIMIT 1
                """
            ),
            {"uid": current_user["id"], "inviter": invite["inviter_user_id"]},
        ).mappings().first()

        if exists:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="ALREADY_BOUND")

        db.execute(
            text(
                """
                INSERT INTO couples (user_a_id, user_b_id, status, bound_at)
                VALUES (
                  LEAST(CAST(:uid AS text), CAST(:inviter AS text))::uuid,
                  GREATEST(CAST(:uid AS text), CAST(:inviter AS text))::uuid,
                  'active',
                  NOW()
                )
                """
            ),
            {"uid": current_user["id"], "inviter": invite["inviter_user_id"]},
        )

        db.execute(
            text(
                """
                UPDATE relationship_invites
                SET status = 'accepted',
                    accepted_by_user_id = CAST(:uid AS uuid),
                    accepted_at = NOW(),
                    updated_at = NOW()
                WHERE id = CAST(:id AS uuid)
                """
            ),
            {"uid": current_user["id"], "id": invite["id"]},
        )
        db.commit()

    except HTTPException:
        db.rollback()
        raise
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="ALREADY_BOUND") from exc

    partner = db.execute(
        text("SELECT nickname, avatar_url FROM users WHERE id = CAST(:id AS uuid)"),
        {"id": invite["inviter_user_id"]},
    ).mappings().one()

    return {
        "ok": True,
        "status": "bound",
        "partner": {
            "nickname": partner["nickname"],
            "avatar": partner["avatar_url"],
        },
    }


@router.get("/status")
def relationship_status(current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    row = db.execute(
        text(
            """
            SELECT c.id::text,
                   CASE WHEN c.user_a_id = CAST(:uid AS uuid) THEN 'user_a' ELSE 'user_b' END AS role,
                   u.nickname AS partner_nickname,
                   u.avatar_url AS partner_avatar
            FROM couples c
            JOIN users u ON u.id = CASE WHEN c.user_a_id = CAST(:uid AS uuid) THEN c.user_b_id ELSE c.user_a_id END
            WHERE c.status = 'active' AND (c.user_a_id = CAST(:uid AS uuid) OR c.user_b_id = CAST(:uid AS uuid))
            LIMIT 1
            """
        ),
        {"uid": current_user["id"]},
    ).mappings().first()

    if not row:
        return {"status": "unbound", "role": None, "partner": None}

    return {
        "status": "bound",
        "role": row["role"],
        "partner": {"nickname": row["partner_nickname"], "avatar": row["partner_avatar"]},
    }


@router.post("/unbind")
def unbind(payload: UnbindIn, current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    if payload.confirm_text != "UNBIND":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="INVALID_CONFIRM_TEXT")

    result = db.execute(
        text(
            """
            UPDATE couples
            SET status = 'unbound', unbound_at = NOW(), updated_at = NOW()
            WHERE status = 'active' AND (user_a_id = CAST(:uid AS uuid) OR user_b_id = CAST(:uid AS uuid))
            RETURNING id::text
            """
        ),
        {"uid": current_user["id"]},
    ).mappings().first()
    db.commit()

    if not result:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="NOT_BOUND")

    return {"ok": True, "status": "unbound"}
