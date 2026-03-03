from fastapi import Depends, Header, HTTPException, status
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.security import decode_access_token
from app.db import get_db


def get_current_user(db: Session = Depends(get_db), authorization: str | None = Header(default=None)) -> dict:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="MISSING_AUTH")

    token = authorization.removeprefix("Bearer ").strip()
    payload = decode_access_token(token)

    session_row = db.execute(
        text(
            """
            SELECT s.id::text, s.user_id::text, s.expired_at, s.revoked_at
            FROM auth_sessions s
            WHERE s.id = CAST(:sid AS uuid)
            """
        ),
        {"sid": payload["sid"]},
    ).mappings().first()

    if not session_row or session_row["revoked_at"] is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="SESSION_REVOKED")

    user_row = db.execute(
        text(
            """
            SELECT id::text, email, phone, nickname, avatar_url, status
            FROM users
            WHERE id = CAST(:uid AS uuid)
            """
        ),
        {"uid": payload["sub"]},
    ).mappings().first()

    if not user_row or user_row["status"] != "active":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="USER_DISABLED")

    if user_row["id"] != session_row["user_id"]:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="INVALID_SESSION")

    return dict(user_row)
