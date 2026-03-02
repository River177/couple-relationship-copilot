from fastapi import FastAPI
from app.routers import health, daily, conflict, weekly, media

app = FastAPI(title="Couple Relationship Copilot API", version="0.1.0")

app.include_router(health.router)
app.include_router(daily.router, prefix="/daily", tags=["daily"])
app.include_router(conflict.router, prefix="/conflict", tags=["conflict"])
app.include_router(weekly.router, prefix="/weekly", tags=["weekly"])
app.include_router(media.router, prefix="/media", tags=["media"])
