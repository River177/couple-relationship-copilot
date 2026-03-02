from fastapi import APIRouter, File, HTTPException, UploadFile
from pydantic import BaseModel

from app.core.config import settings
from app.services.storage import (
    build_object_key,
    build_public_url,
    ensure_bucket_exists,
    guess_content_type,
    presign_put_url,
    s3_client,
)

router = APIRouter()


class PresignIn(BaseModel):
    filename: str
    media_type: str  # image|video


@router.post("/presign")
def create_presigned_upload(payload: PresignIn):
    if payload.media_type not in {"image", "video"}:
        raise HTTPException(status_code=400, detail="media_type must be image or video")

    ensure_bucket_exists(settings.s3_bucket)

    object_key = build_object_key(payload.filename, folder=f"daily/{payload.media_type}")
    content_type = guess_content_type(payload.filename)
    put_url = presign_put_url(settings.s3_bucket, object_key, content_type=content_type)

    return {
        "bucket": settings.s3_bucket,
        "object_key": object_key,
        "put_url": put_url,
        "public_url": build_public_url(settings.s3_bucket, object_key),
        "content_type": content_type,
        "expires_in_sec": 900,
    }


@router.post("/upload")
def upload_file(file: UploadFile = File(...), media_type: str = "image"):
    if media_type not in {"image", "video"}:
        raise HTTPException(status_code=400, detail="media_type must be image or video")

    ensure_bucket_exists(settings.s3_bucket)

    object_key = build_object_key(file.filename or "upload.bin", folder=f"daily/{media_type}")
    content_type = file.content_type or guess_content_type(file.filename or "upload.bin")

    client = s3_client()
    client.upload_fileobj(
        file.file,
        settings.s3_bucket,
        object_key,
        ExtraArgs={"ContentType": content_type},
    )

    return {
        "bucket": settings.s3_bucket,
        "object_key": object_key,
        "url": build_public_url(settings.s3_bucket, object_key),
        "content_type": content_type,
        "filename": file.filename,
    }
