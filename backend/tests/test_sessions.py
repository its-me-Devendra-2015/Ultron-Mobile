import sys
import uuid
import hashlib
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
    paired = client.post("/api/devices/pair", json={"code": response.json()["code"], "device_label": label})
    assert paired.status_code == 200
    return paired.json()


def test_authenticated_session_event_and_owner_isolation(tmp_path, monkeypatch):
    monkeypatch.setattr(session_service, "DB_PATH", tmp_path / "sessions.sqlite3")
    client = TestClient(main.app)
    assert client.get("/api/sessions").status_code == 401

    alice = _pair(client, "alice", "Alice desktop")
    headers = {"Authorization": f"Bearer {alice['device_token']}"}
    created = client.post("/api/sessions", headers=headers, json={"title": "Chat"})
    assert created.status_code == 200
    sid = created.json()["session_id"]
    event_id = str(uuid.uuid4())
    event = {
        "protocol_version": "1.0", "event_id": event_id, "session_id": sid,
        "event_type": "message.user", "occurred_at": "2026-11-16T12:00:00Z",
        "source": "desktop", "payload": {"text": "hello"}
    }
    saved = client.post(f"/api/sessions/{sid}/events", headers=headers, json=event)
    assert saved.status_code == 201
    assert client.get(f"/api/sessions/{sid}/events", headers=headers).json()["events"][0]["payload"]["text"] == "hello"

    bob = _pair(client, "bob", "Bob desktop")
    bob_headers = {"Authorization": f"Bearer {bob['device_token']}"}
    assert client.get(f"/api/sessions/{sid}/events", headers=bob_headers).status_code == 404
    main.app.dependency_overrides.clear()


def test_pairing_is_one_time_and_device_can_be_revoked(tmp_path, monkeypatch):
    monkeypatch.setattr(session_service, "DB_PATH", tmp_path / "sessions.sqlite3")
    client = TestClient(main.app)
    paired = _pair(client, "alice", "Desktop")
    token = paired["device_token"]
    assert token.startswith("udv_")
    assert client.post("/api/devices/pair", json={"code": "BADCODE1"}).status_code == 401

    headers = {"Authorization": f"Bearer {token}"}
    session = client.post("/api/sessions", headers=headers, json={"title": "From desktop"})
    assert session.status_code == 200
    assert client.get("/api/sessions", headers=headers).json()["sessions"][0]["title"] == "From desktop"

    main.app.dependency_overrides[main.require_firebase_user] = lambda authorization=None: {"uid": "alice"}
    revoked = client.delete(f"/api/devices/{paired['device_id']}", headers={"Authorization": "Bearer firebase-test"})
    assert revoked.status_code == 200
    assert client.get("/api/sessions", headers=headers).status_code == 401
    main.app.dependency_overrides.clear()
