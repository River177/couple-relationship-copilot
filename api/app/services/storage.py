import mimetypes
import uuid
from datetime import timedelta

import boto3
from botocore.client import Config

from app.core.config import settings


def s3_client():
    return boto3.client(
        "s3",
        endpoint_url=settings.s3_endpoint,
        aws_access_key_id=settings.s3_access_key,
        aws_secret_access_key=settings.s3_secret_key,
        region_name=settings.s3_region,
        use_ssl=settings.s3_use_ssl,
        config=Config(signature_version="s3v4"),
    )


def ensure_bucket_exists(bucket: str):
    client = s3_client()
    buckets = [b["Name"] for b in client.list_buckets().get("Buckets", [])]
    if bucket not in buckets:
        client.create_bucket(Bucket=bucket)


def build_object_key(filename: str, folder: str = "daily") -> str:
    ext = ""
    if "." in filename:
        ext = "." + filename.rsplit(".", 1)[1].lower()
    return f"{folder}/{uuid.uuid4().hex}{ext}"


def build_public_url(bucket: str, object_key: str) -> str:
    return f"{settings.s3_public_base_url.rstrip('/')}/{bucket}/{object_key}"


def presign_put_url(bucket: str, object_key: str, content_type: str | None = None, expires_sec: int = 900) -> str:
    client = s3_client()
    params = {"Bucket": bucket, "Key": object_key}
    if content_type:
        params["ContentType"] = content_type
    return client.generate_presigned_url(
        "put_object", Params=params, ExpiresIn=expires_sec
    )


def guess_content_type(filename: str) -> str:
    ctype, _ = mimetypes.guess_type(filename)
    return ctype or "application/octet-stream"
