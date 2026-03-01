from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()

class ConflictInputIn(BaseModel):
    session_id: str
    user_id: str
    facts: str
    feelings: str
    needs: str
    expectation: str | None = None
    emotion_score: int

@router.post("/session")
def create_conflict_session(couple_id: str):
    # TODO: create conflict session record
    return {"session_id": "TODO-generated", "couple_id": couple_id}

@router.post("/input")
def submit_conflict_input(payload: ConflictInputIn):
    # TODO: store each side input
    return {"message": "conflict input received", "data": payload.model_dump()}

@router.post("/mediate")
def mediate_conflict(session_id: str):
    # TODO: call LLM + MemOS retrieval and return structured mediation output
    return {
        "session_id": session_id,
        "consensus_facts": [],
        "differences": [],
        "needs_translation": [],
        "tonight_action": None,
        "repair_plan_72h": []
    }
