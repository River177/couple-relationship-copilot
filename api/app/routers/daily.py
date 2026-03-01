from fastapi import APIRouter
from pydantic import BaseModel, Field

router = APIRouter()

class DailyEntryIn(BaseModel):
    couple_id: str
    author_user_id: str
    event_type: str = Field(description="date|gift|interaction|other")
    mood_score: int = Field(ge=1, le=5)
    content: str

@router.post("")
def create_daily_entry(payload: DailyEntryIn):
    # TODO: persist to PostgreSQL + write to MemOS
    return {"message": "daily entry received", "data": payload.model_dump()}

@router.get("/timeline")
def get_timeline(couple_id: str):
    # TODO: read from PostgreSQL and enrich with MemOS retrieval
    return {"couple_id": couple_id, "items": []}
