import sys
import sqlite3
import uuid
from pathlib import Path

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import session_service
import main


def _pair(client, owner, label):
    main.app.dependency_overrides[main.require_firebase_user] = lambda authorization=None: {"uid": owner}
    response = client.post(
        "/api/devices/pairing-code",
        headers={"Authorization": "Bearer firebase-test"},
        json={"device_label": label},
    )
    assert response.status_code == 200
    pairing = response.json()
    paired = client.post("/api/devices/pair", json={"code": pairing["code"], "device_label": label})
    assert paired.status_code == 200
    assert paired.json()["session_id"] == pairing["session_id"]
    return paired.json()


def test_authenticated_session_event_and_owner_isolation(tmp_path, monkeypatch):
    monkeypatch.setattr(session_service, "DB_PATH", tmp_path / "sessions.sqlite3")
    # principal() calls the verifier directly for Firebase principals; stub the
    # verifier itself as well as FastAPI's dependency for the route-level checks.
    monkeypatch.setattr(main, "firebase_app", lambda: None)
    monkeypatch.setattr(
        main.firebase_auth,
        "verify_id_token",
        lambda raw_token, check_revoked=True: {"uid": "alice"},
    )
    client = TestClient(main.app)
    assert client.get("/api/sessions").status_code == 401

    alice = _pair(client, "alice", "Alice desktop")
    headers = {"Authorization": f"Bearer {alice['device_token']}"}
    sid = alice["session_id"]
    created = client.post("/api/sessions", headers=headers, json={"session_id": sid, "title": "Chat"})
    assert created.status_code == 200
    assert created.json()["session_id"] == sid
    event_id = str(uuid.uuid4())
    event = {
        "protocol_version": "1.0", "event_id": event_id, "session_id": sid,
        "event_type": "message.user", "occurred_at": "2026-11-16T12:00:00Z",
        "source": "desktop", "request_id": "request-123", "payload": {"text": "hello"}
    }
    saved = client.post(f"/api/sessions/{sid}/events", headers=headers, json=event)
    assert saved.status_code == 201
    saved_events = client.get(f"/api/sessions/{sid}/events", headers=headers).json()["events"]
    assert saved_events[0]["payload"]["text"] == "hello"
    assert saved_events[0]["request_id"] == "request-123"

    main.app.dependency_overrides[main.require_firebase_user] = lambda authorization=None: {"uid": "alice"}
    assert client.get(f"/api/sessions/{sid}/events", headers={"Authorization": "Bearer firebase-test"}).status_code == 200

    bob = _pair(client, "bob", "Bob desktop")
    bob_headers = {"Authorization": f"Bearer {bob['device_token']}"}
    assert client.get(f"/api/sessions/{sid}/events", headers=bob_headers).status_code == 404
    assert client.get(f"/api/sessions/{sid}", headers=bob_headers).status_code == 404
    assert client.post("/api/sessions", headers=bob_headers, json={"session_id": sid}).status_code == 403

    # A paired desktop can only see its paired session, not another session
    # owned by the same Firebase account.
    other = client.post(
        "/api/sessions",
        headers={"Authorization": "Bearer firebase-test"},
        json={"title": "Private mobile session"},
    )
    assert other.status_code == 200
    other_id = other.json()["session_id"]
    assert client.get("/api/sessions", headers=headers).json()["sessions"] == [
        {
            "session_id": sid,
            "title": "ULTRON shared session",
            "created_at": client.get(f"/api/sessions/{sid}", headers=headers).json()["created_at"],
            "updated_at": client.get(f"/api/sessions/{sid}", headers=headers).json()["updated_at"],
        }
    ]
    assert client.get(f"/api/sessions/{other_id}", headers=headers).status_code == 404
    assert client.get(f"/api/sessions/{other_id}/events", headers=headers).status_code == 404
    main.app.dependency_overrides.clear()


def test_pairing_is_one_time_and_device_can_be_revoked(tmp_path, monkeypatch):
    monkeypatch.setattr(session_service, "DB_PATH", tmp_path / "sessions.sqlite3")
    client = TestClient(main.app)
    paired = _pair(client, "alice", "Desktop")
    token = paired["device_token"]
    assert token.startswith("udv_")
    assert client.post("/api/devices/pair", json={"code": "BADCODE1"}).status_code == 401

    headers = {"Authorization": f"Bearer {token}"}
    session = client.post(
        "/api/sessions",
        headers=headers,
        json={"session_id": paired["session_id"], "title": "From desktop"},
    )
    assert session.status_code == 200
    assert client.get("/api/sessions", headers=headers).json()["sessions"][0]["title"] == "From desktop"

    main.app.dependency_overrides[main.require_firebase_user] = lambda authorization=None: {"uid": "alice"}
    revoked = client.delete(f"/api/devices/{paired['device_id']}", headers={"Authorization": "Bearer firebase-test"})
    assert revoked.status_code == 200
    assert client.get("/api/sessions", headers=headers).status_code == 401
    main.app.dependency_overrides.clear()

def test_pairing_code_is_single_use_and_returns_a_shared_session(tmp_path, monkeypatch):
    monkeypatch.setattr(session_service, "DB_PATH", tmp_path / "sessions.sqlite3")
    client = TestClient(main.app)
    main.app.dependency_overrides[main.require_firebase_user] = lambda authorization=None: {"uid": "alice"}
    try:
        pairing = client.post(
            "/api/devices/pairing-code",
            headers={"Authorization": "Bearer firebase-test"},
            json={"device_label": "ULTRON Desktop"},
        )
        assert pairing.status_code == 200
        session_id = pairing.json()["session_id"]

        first = client.post(
            "/api/devices/pair",
            json={"code": pairing.json()["code"], "device_label": "Desktop"},
        )
        assert first.status_code == 200
        assert first.json()["session_id"] == session_id

        second = client.post(
            "/api/devices/pair",
            json={"code": pairing.json()["code"], "device_label": "Desktop"},
        )
        assert second.status_code == 401

        token = first.json()["device_token"]
        sessions = client.get("/api/sessions", headers={"Authorization": f"Bearer {token}"})
        assert sessions.status_code == 200
        assert sessions.json()["sessions"][0]["session_id"] == session_id
    finally:
        main.app.dependency_overrides.clear()


def test_event_timestamps_must_include_a_timezone(tmp_path, monkeypatch):
    monkeypatch.setattr(session_service, "DB_PATH", tmp_path / "sessions.sqlite3")
    client = TestClient(main.app)
    paired = _pair(client, "alice", "Desktop")
    token = paired["device_token"]
    session_id = paired["session_id"]
    event = {
        "protocol_version": "1.0",
        "event_id": str(uuid.uuid4()),
        "session_id": session_id,
        "event_type": "message.user",
        "occurred_at": "2026-11-16T12:00:00",
        "source": "desktop",
        "payload": {"text": "naive timestamp"},
    }
    response = client.post(
        f"/api/sessions/{session_id}/events",
        headers={"Authorization": f"Bearer {token}"},
        json=event,
    )
    assert response.status_code == 422
    main.app.dependency_overrides.clear()

def test_existing_database_schema_is_migrated_in_place(tmp_path, monkeypatch):
    database = tmp_path / "legacy.sqlite3"
    connection = sqlite3.connect(database)
    connection.executescript("""
      CREATE TABLE sessions(
        id TEXT PRIMARY KEY, owner_uid TEXT NOT NULL, title TEXT NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      );
      CREATE TABLE events(
        event_id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
        owner_uid TEXT NOT NULL, event_type TEXT NOT NULL, source TEXT NOT NULL,
        occurred_at TEXT NOT NULL, payload_json TEXT NOT NULL
      );
      CREATE TABLE pairing_codes(
        code_hash TEXT PRIMARY KEY, owner_uid TEXT NOT NULL,
        expires_at TEXT NOT NULL, created_at TEXT NOT NULL
      );
      CREATE TABLE devices(
        device_id TEXT NOT NULL UNIQUE, token_hash TEXT PRIMARY KEY, owner_uid TEXT NOT NULL,
        name TEXT NOT NULL, created_at TEXT NOT NULL,
        last_used_at TEXT, revoked INTEGER NOT NULL DEFAULT 0
      );
    """)
    connection.close()
    monkeypatch.setattr(session_service, "DB_PATH", database)

    migrated = session_service._db()
    try:
        event_columns = {row["name"] for row in migrated.execute("PRAGMA table_info(events)")}
        pairing_columns = {row["name"] for row in migrated.execute("PRAGMA table_info(pairing_codes)")}
        device_columns = {row["name"] for row in migrated.execute("PRAGMA table_info(devices)")}
        assert "request_id" in event_columns
        assert "session_id" in pairing_columns
        assert "session_id" in device_columns
    finally:
        migrated.close()
