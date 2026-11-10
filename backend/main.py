import os
import re
import uuid
from datetime import timedelta
from typing import Optional

import firebase_admin
from firebase_admin import auth as firebase_auth
from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from livekit import api
from pydantic import BaseModel, Field

app = FastAPI(title="ULTRON LiveKit Token Service", version="1.0.0")

# Explicit origins only. Set CORS_ALLOWED_ORIGINS to a comma-separated allowlist.
origins = [item.strip() for item in os.getenv("CORS_ALLOWED_ORIGINS", "").split(",") if item.strip()]
if origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=False,
        allow_methods=["POST", "GET"],
        allow_headers=["Authorization", "Content-Type"],
    )

_firebase_app = None


def firebase_app():
    global _firebase_app
    if _firebase_app is None:
        try:
            _firebase_app = firebase_admin.get_app()
        except ValueError:
            _firebase_app = firebase_admin.initialize_app()
    return _firebase_app


def require_firebase_user(authorization: Optional[str] = Header(default=None)) -> dict:
    """Require a Firebase ID token; never trust a UID supplied by the client."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing Firebase bearer token")
    raw_token = authorization.removeprefix("Bearer ").strip()
    if not raw_token:
        raise HTTPException(status_code=401, detail="Missing Firebase bearer token")
    try:
        firebase_app()
        return firebase_auth.verify_id_token(raw_token, check_revoked=True)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired Firebase ID token")


class TokenRequest(BaseModel):
    # A client-generated UUID gives each voice session its own room.
    session_id: str = Field(default_factory=lambda: str(uuid.uuid4()), min_length=36, max_length=36)


class TokenResponse(BaseModel):
    server_url: str
    participant_token: str


def required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise HTTPException(status_code=503, detail=f"Server is missing {name} configuration")
    return value


@app.get("/health")
def health():
    return {"status": "ok", "service": "ultron-livekit-token-service"}


@app.post("/api/token", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def create_livekit_token(
    request: TokenRequest,
    user: dict = Depends(require_firebase_user),
):
    """Mint a short-lived, room-scoped token for the authenticated Firebase user."""
    uid = str(user.get("uid", ""))
    if not uid:
        raise HTTPException(status_code=401, detail="Authenticated user has no UID")

    try:
        session_uuid = uuid.UUID(request.session_id)
    except (ValueError, TypeError):
        raise HTTPException(status_code=422, detail="session_id must be a UUID")

    # The room is derived from the verified UID, not a client-supplied room name.
    safe_uid = re.sub(r"[^A-Za-z0-9_-]", "", uid)[:48]
    room_name = f"ultron-{safe_uid}-{session_uuid.hex[:16]}"
    participant_name = str(user.get("name") or user.get("email") or "ULTRON user")[:80]

    try:
        access_token = (
            api.AccessToken(
                required_env("LIVEKIT_API_KEY"),
                required_env("LIVEKIT_API_SECRET"),
            )
            .with_identity(uid)
            .with_name(participant_name)
            .with_ttl(timedelta(minutes=10))
            .with_grants(
                api.VideoGrants(
                    room_join=True,
                    room=room_name,
                    can_publish=True,
                    can_subscribe=True,
                    can_publish_data=True,
                )
            )
        )

        # Explicit dispatch is optional. Leave unset if the worker uses
        # automatic dispatch; set it to the registered LiveKit agent name
        # when this app should always start a particular ULTRON agent.
        agent_name = os.getenv("LIVEKIT_AGENT_NAME", "").strip()
        if agent_name:
            access_token = access_token.with_room_config(
                api.RoomConfiguration(
                    agents=[api.RoomAgentDispatch(agent_name=agent_name)]
                )
            )

        return TokenResponse(
            server_url=required_env("LIVEKIT_URL"),
            participant_token=access_token.to_jwt(),
        )
    except HTTPException:
        raise
    except Exception:
        # Do not leak secrets, tokens, or provider internals into API responses.
        raise HTTPException(status_code=503, detail="Unable to create LiveKit credentials")
