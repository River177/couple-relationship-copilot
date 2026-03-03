from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import (
    create_access_token,
    generate_login_code,
    generate_refresh_token,
    hash_token,
)
from app.db import get_db
from app.deps.auth import get_current_user

router = APIRouter()


class SendCodeIn(BaseModel):
    account: str
    type: Literal["email", "phone"]


class LoginIn(BaseModel):
    account: str
    code: str


class RefreshIn(BaseModel):
    refresh_token: str


@router.post("/send-code")
def send_code(payload: SendCodeIn, db: Session = Depends(get_db)):
    code = generate_login_code()
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)

    db.execute(
        text(
            """
            INSERT INTO auth_verification_codes (account, code_hash, purpose, expired_at)
            VALUES (:account, :code_hash, 'login', :expired_at)
            """
        ),
        {
            "account": payload.account.strip().lower(),
            "code_hash": hash_token(code),
            "expired_at": expires_at,
        },
    )
    db.commit()

    response = {"ok": True, "cooldown": 60}
    # dev环境下透出验证码，便于联调
    if settings.app_env != "prod":
        response["dev_code"] = code
    return response


@router.post("/login")
def login(payload: LoginIn, request: Request, db: Session = Depends(get_db)):
    account = payload.account.strip().lower()
    code_hash = hash_token(payload.code.strip())

    code_row = db.execute(
        text(
            """
            SELECT id::text
            FROM auth_verification_codes
            WHERE account = :account
              AND purpose = 'login'
              AND code_hash = :code_hash
              AND consumed_at IS NULL
              AND expired_at > NOW()
            ORDER BY created_at DESC
            LIMIT 1
            """
        ),
        {"account": account, "code_hash": code_hash},
    ).mappings().first()

    if not code_row:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="INVALID_CODE")

    is_email = "@" in account
    user_row = db.execute(
        text(
            """
            SELECT id::text, nickname, avatar_url
            FROM users
            WHERE (email = :account OR phone = :account)
            LIMIT 1
            """
        ),
        {"account": account},
    ).mappings().first()

    if not user_row:
        nickname = account.split("@")[0] if is_email else account[-4:]
        user_row = db.execute(
            text(
                """
                INSERT INTO users (email, phone, nickname)
                VALUES (:email, :phone, :nickname)
                RETURNING id::text, nickname, avatar_url
                """
            ),
            {
                "email": account if is_email else None,
                "phone": None if is_email else account,
                "nickname": nickname,
            },
        ).mappings().one()

    refresh_token = generate_refresh_token()
    refresh_expired_at = datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_ttl_days)

    session_row = db.execute(
        text(
            """
            INSERT INTO auth_sessions (user_id, refresh_token_hash, device_info, ip, user_agent, expired_at)
            VALUES (CAST(:user_id AS uuid), :refresh_token_hash, '{}'::jsonb, :ip, :user_agent, :expired_at)
            RETURNING id::text
            """
        ),
        {
            "user_id": user_row["id"],
            "refresh_token_hash": hash_token(refresh_token),
            "ip": request.client.host if request.client else None,
            "user_agent": request.headers.get("user-agent", ""),
            "expired_at": refresh_expired_at,
        },
    ).mappings().one()

    db.execute(
        text("UPDATE auth_verification_codes SET consumed_at = NOW() WHERE id = CAST(:id AS uuid)"),
        {"id": code_row["id"]},
    )

    relationship_row = db.execute(
        text(
            """
            SELECT c.id::text, u.nickname AS partner_nickname
            FROM couples c
            JOIN users u ON u.id = CASE WHEN c.user_a_id = CAST(:uid AS uuid) THEN c.user_b_id ELSE c.user_a_id END
            WHERE c.status = 'active' AND (c.user_a_id = CAST(:uid AS uuid) OR c.user_b_id = CAST(:uid AS uuid))
            LIMIT 1
            """
        ),
        {"uid": user_row["id"]},
    ).mappings().first()

    db.commit()

    access_token, expires_in = create_access_token(user_id=user_row["id"], session_id=session_row["id"])
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "expires_in": expires_in,
        "user": {
            "nickname": user_row["nickname"],
            "avatar": user_row["avatar_url"],
            "bind_status": "bound" if relationship_row else "unbound",
        },
    }


@router.post("/refresh")
def refresh_token(payload: RefreshIn, db: Session = Depends(get_db)):
    token_hash = hash_token(payload.refresh_token)

    session_row = db.execute(
        text(
            """
            SELECT id::text, user_id::text
            FROM auth_sessions
            WHERE refresh_token_hash = :token_hash
              AND revoked_at IS NULL
              AND expired_at > NOW()
            ORDER BY created_at DESC
            LIMIT 1
            """
        ),
        {"token_hash": token_hash},
    ).mappings().first()

    if not session_row:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="REFRESH_EXPIRED")

    access_token, expires_in = create_access_token(user_id=session_row["user_id"], session_id=session_row["id"])
    return {"access_token": access_token, "expires_in": expires_in}


@router.get("/me")
def me(current_user: dict = Depends(get_current_user), db: Session = Depends(get_db)):
    relationship_row = db.execute(
        text(
            """
            SELECT c.id::text, u.nickname AS partner_nickname, u.avatar_url AS partner_avatar
            FROM couples c
            JOIN users u ON u.id = CASE WHEN c.user_a_id = CAST(:uid AS uuid) THEN c.user_b_id ELSE c.user_a_id END
            WHERE c.status = 'active' AND (c.user_a_id = CAST(:uid AS uuid) OR c.user_b_id = CAST(:uid AS uuid))
            LIMIT 1
            """
        ),
        {"uid": current_user["id"]},
    ).mappings().first()

    return {
        "user": {
            "nickname": current_user["nickname"],
            "avatar": current_user["avatar_url"],
        },
        "relationship": {
            "status": "bound" if relationship_row else "unbound",
            "partner_nickname": relationship_row["partner_nickname"] if relationship_row else None,
            "partner_avatar": relationship_row["partner_avatar"] if relationship_row else None,
        },
    }
