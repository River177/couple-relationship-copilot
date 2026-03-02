import os


class Settings:
    app_env: str = os.getenv("APP_ENV", "dev")
    app_port: int = int(os.getenv("APP_PORT", "8000"))

    database_url: str = os.getenv(
        "DATABASE_URL",
        "postgresql+psycopg://couple_app:couple_app_2026@localhost:5432/couple_copilot",
    )

    memos_base_url: str = os.getenv("MEMOS_BASE_URL", "")
    memos_api_key: str = os.getenv("MEMOS_API_KEY", "")
    memos_user_id_prefix: str = os.getenv("MEMOS_USER_ID_PREFIX", "couple-copilot")

    s3_endpoint: str = os.getenv("S3_ENDPOINT", "http://localhost:9000")
    s3_access_key: str = os.getenv("S3_ACCESS_KEY", "minioadmin")
    s3_secret_key: str = os.getenv("S3_SECRET_KEY", "minioadmin123")
    s3_bucket: str = os.getenv("S3_BUCKET", "couple-media")
    s3_region: str = os.getenv("S3_REGION", "us-east-1")
    s3_use_ssl: bool = os.getenv("S3_USE_SSL", "false").lower() == "true"
    s3_public_base_url: str = os.getenv("S3_PUBLIC_BASE_URL", "http://localhost:9000")


settings = Settings()
