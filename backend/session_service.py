"""Authenticated ULTRON session sync and one-time desktop pairing.

AI provider credentials and privileged desktop actions deliberately remain outside
this service. Firebase users own sessions; paired desktop devices receive a
narrow, revocable bearer credential scoped to that Firebase user's sessions.
"""
from __future__ import annotations

import hashlib
import json
import os
import secrets
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field

DB_PATH = Path(os.getenv("ULTRON_SESSION_DB", str(Path(__file__).with_name("ultron_sessions.sqlite3"))))
EVENT_TYPES = {
    "session.started", "session.ended", "message.user", "message.assistant",
    "assistant.state", "tool.started", "tool.completed", "tool.failed",
    "audio.state", "system.status", "error",
}
SOURCES = {"desktop", "mobile", "backend", "agent"}


def _db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys=ON")
    db.executescript("""
      CREATE TABLE IF NOT EXISTS sessions(
        id TEXT PRIMARY KEY, owner_uid TEXT NOT NULL, title TEXT NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_sessions_owner ON sessions(owner_uid, updated_at);
      CREATE TABLE IF NOT EXISTS events(
        event_id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
        owner_uid TEXT NOT NULL, event_type TEXT NOT NULL, source TEXT NOT NULL,
        occurred_at TEXT NOT NULL, payload_json TEXT NOT NULL,
        FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id, occurred_at);
      CREATE TABLE IF NOT EXISTS pairing_codes(
        code_hash TEXT PRIMARY KEY, owner_uid TEXT NOT NULL,
        expires_at TEXT NOT NULL, created_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS devices(
        token_hash TEXT PRIMARY KEY, owner_uid TEXT NOT NULL,
        name TEXT NOT NULL, created_at TEXT NOT NULL,
        last_used_at TEXT, revoked INTEGER NOT NULL DEFAULT 0
      );
    """)
    return db


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


class PairCodeRequest(BaseModel):
    device_label: str = Field(default="ULTRON Desktop", min_length=1, max_length=80)


class PairExchangeRequest(BaseModel):
    code: str = Field(min_length=6, max_length=12)
    device_label: str = Field(default="ULTRON Desktop", min_length=1, max_length=80)


class SessionCreate(BaseModel):
    session_id: str | None = None
    title: str = Field(default="ULTRON session", max_length=120)


class EventCreate(BaseModel):
    protocol_version: str = Field(default="1.0")
    event_id: str
    session_id: str
    event_type: str
    occurred_at: str
    source: str
    payload: dict[str, Any] = Field(default_factory=dict)


def build_session_router(require_firebase_user: Callable[..., dict]) -> APIRouter:
    router = APIRouter()

    def principal(authorization: str | None = Header(default=None)) -> dict:
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Missing bearer token")
        token = authorization[7:].strip()
        if not token:
            raise HTTPException(status_code=401, detail="Missing bearer token")
        if token.startswith("udv_"):
            db = _db()
            try:
                row = db.execute(
                    "SELECT owner_uid, revoked FROM devices WHERE token_hash=?",
                    (_digest(token),),
                ).fetchone()
                if not row or row["revoked"]:
                    raise HTTPException(status_code=401, detail="Invalid or revoked device token")
                db.execute(
                    "UPDATE devices SET last_used_at=? WHERE token_hash=?",
                    (_now(), _digest(token)),
                )
                db.commit()
                return {"uid": row["owner_uid"], "principal_type": "device"}
            finally:
                db.close()
        user = require_firebase_user(authorization)
        return {**user, "principal_type": "user"}

    @router.post("/api/devices/pairing-code")
    def create_pairing_code(
        request: PairCodeRequest,
        user: dict = Depends(require_firebase_user),
    ):
        uid = str(user.get("uid", ""))
        if not uid:
            raise HTTPException(status_code=401, detail="Authenticated user has no UID")
        code = secrets.token_urlsafe(6).replace("-", "").replace("_", "")[:8].upper()
        now = datetime.now(timezone.utc)
        db = _db()
        try:
            db.execute("DELETE FROM pairing_codes WHERE expires_at < ?", (now.isoformat(),))
            db.execute(
                "INSERT INTO pairing_codes(code_hash,owner_uid,expires_at,created_at) VALUES(?,?,?,?)",
                (_digest(code), uid, (now + timedelta(minutes=5)).isoformat(), now.isoformat()),
            )
            db.commit()
        finally:
            db.close()
        return {"code": code, "expires_in_seconds": 300, "device_label": request.device_label}

    @router.post("/api/devices/pair")
    def exchange_pairing_code(request: PairExchangeRequest):
        now = _now()
        db = _db()
        try:
            row = db.execute(
                "SELECT owner_uid, expires_at FROM pairing_codes WHERE code_hash=?",
                (_digest(request.code.strip().upper()),),
            ).fetchone()
            if not row or row["expires_at"] < now:
                raise HTTPException(status_code=401, detail="Pairing code is invalid or expired")
            db.execute("DELETE FROM pairing_codes WHERE code_hash=?", (_digest(request.code.strip().upper()),))
            token = "udv_" + secrets.token_urlsafe(32)
            db.execute(
                "INSERT INTO devices(token_hash,owner_uid,name,created_at) VALUES(?,?,?,?)",
                (_digest(token), row["owner_uid"], request.device_label.strip(), now),
            )
            db.commit()
            return {"device_token": token, "owner_uid": row["owner_uid"], "token_type": "Bearer"}
        finally:
            db.close()

    @router.get("/api/devices")
    def list_devices(user: dict = Depends(require_firebase_user)):
        db = _db()
        try:
            rows = db.execute(
                "SELECT name,created_at,last_used_at,revoked FROM devices WHERE owner_uid=? ORDER BY created_at DESC",
                (str(user.get("uid", "")),),
            ).fetchall()
            return {"devices": [dict(row) for row in rows]}
        finally:
            db.close()

    @router.post("/api/sessions")
    def create_session(request: SessionCreate, user: dict = Depends(principal)):
        uid = str(user.get("uid", ""))
        if not uid:
            raise HTTPException(status_code=401, detail="Invalid session principal")
        try:
            session_id = str(uuid.UUID(request.session_id)) if request.session_id else str(uuid.uuid4())
        except ValueError:
            raise HTTPException(status_code=422, detail="session_id must be a UUID")
        now = _now()
        db = _db()
        try:
            db.execute(
                "INSERT INTO sessions(id,owner_uid,title,created_at,updated_at) VALUES(?,?,?,?,?)",
                (session_id, uid, request.title.strip() or "ULTRON session", now, now),
            )
            db.commit()
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="Session already exists")
        finally:
            db.close()
        return {"session_id": session_id, "title": request.title, "created_at": now}

    @router.get("/api/sessions")
    def list_sessions(user: dict = Depends(principal)):
        db = _db()
        try:
            rows = db.execute(
                "SELECT id AS session_id,title,created_at,updated_at FROM sessions WHERE owner_uid=? ORDER BY updated_at DESC LIMIT 100",
                (str(user.get("uid", "")),),
            ).fetchall()
            return {"sessions": [dict(row) for row in rows]}
        finally:
            db.close()

    @router.post("/api/sessions/{session_id}/events", status_code=201)
    def append_event(session_id: str, request: EventCreate, user: dict = Depends(principal)):
        uid = str(user.get("uid", ""))
        try:
            uuid.UUID(session_id)
            uuid.UUID(request.event_id)
            uuid.UUID(request.session_id)
            parsed = datetime.fromisoformat(request.occurred_at.replace("Z", "+00:00"))
        except (ValueError, TypeError):
            raise HTTPException(status_code=422, detail="Invalid session, event ID, or timestamp")
        if request.protocol_version != "1.0":
            raise HTTPException(status_code=422, detail="Unsupported protocol version")
        if request.session_id != session_id:
            raise HTTPException(status_code=422, detail="Event session_id does not match route")
        if request.event_type not in EVENT_TYPES or request.source not in SOURCES:
            raise HTTPException(status_code=422, detail="Unsupported event type or source")
        if len(json.dumps(request.payload, ensure_ascii=False)) > 32768:
            raise HTTPException(status_code=413, detail="Event payload is too large")
        db = _db()
        try:
            owned = db.execute(
                "SELECT id FROM sessions WHERE id=? AND owner_uid=?", (session_id, uid)
            ).fetchone()
            if not owned:
                raise HTTPException(status_code=404, detail="Session not found")
            db.execute(
                "INSERT INTO events(event_id,session_id,owner_uid,event_type,source,occurred_at,payload_json) VALUES(?,?,?,?,?,?,?)",
                (request.event_id, session_id, uid, request.event_type, request.source,
                 parsed.astimezone(timezone.utc).isoformat(), json.dumps(request.payload, ensure_ascii=False)),
            )
            db.execute("UPDATE sessions SET updated_at=? WHERE id=?", (_now(), session_id))
            db.commit()
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="Duplicate event")
        finally:
            db.close()
        return {"accepted": True, "event_id": request.event_id}

    @router.get("/api/sessions/{session_id}/events")
    def read_events(session_id: str, limit: int = 100, user: dict = Depends(principal)):
        if limit < 1 or limit > 500:
            raise HTTPException(status_code=422, detail="limit must be between 1 and 500")
        db = _db()
        try:
            owned = db.execute(
                "SELECT id FROM sessions WHERE id=? AND owner_uid=?",
                (session_id, str(user.get("uid", ""))),
            ).fetchone()
            if not owned:
                raise HTTPException(status_code=404, detail="Session not found")
            rows = db.execute(
                "SELECT event_id,session_id,event_type,source,occurred_at,payload_json FROM events WHERE session_id=? ORDER BY occurred_at,event_id LIMIT ?",
                (session_id, limit),
            ).fetchall()
            return {"events": [
                {"event_id": row["event_id"], "session_id": row["session_id"],
                 "event_type": row["event_type"], "source": row["source"],
                 "occurred_at": row["occurred_at"], "payload": json.loads(row["payload_json"])}
                for row in rows
            ]}
        finally:
            db.close()

    @router.delete("/api/devices/{device_name}")
    def revoke_device(device_name: str, user: dict = Depends(require_firebase_user)):
        # Revocation by display name is intentionally not supported because names
        # are not unique; use the device-management endpoint in the next iteration.
        raise HTTPException(status_code=501, detail="Device revocation by stable ID is not available yet")

    return router
