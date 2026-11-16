import sys
import uuid
from pathlib import Path

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import session_service


def test_authenticated_session_event_and_owner_isolation(tmp_path, monkeypatch):
    monkeypatch.setattr(session_service, "DB_PATH", tmp_path / "sessions.sqlite3")
    app = __import__("main").app
    app.dependency_overrides[__import__("main").require_firebase_user] = lambda authorization=None: {"uid": "alice"}
    client = TestClient(app)

    assert client.get("/api/sessions").status_code == 401
    created = client.post("/api/sessions", headers={"Authorization": "Bearer firebase-test"}, json={"title": "Chat"})
    assert created.status_code == 200
    sid = created.json()["session_id"]
    event_id = str(uuid.uuid4())
    event = {
        "protocol_version": "1.0", "event_id": event_id, "session_id": sid,
        "event_type": "message.user", "occurred_at": "2026-11-16T12:00:00Z",
        "source": "mobile", "payload": {"text": "hello"}
    }
    saved = client.post(f"/api/sessions/{sid}/events", headers={"Authorization": "Bearer firebase-test"}, json=event)
    assert saved.status_code == 201
    assert client.get(f"/api/sessions/{sid}/events", headers={"Authorization": "Bearer firebase-test"}).json()["events"][0]["payload"]["text"] == "hello"

    app.dependency_overrides[__import__("main").require_firebase_user] = lambda authorization=None: {"uid": "bob"}
    assert client.get(f"/api/sessions/{sid}/events", headers={"Authorization": "Bearer firebase-test"}).status_code == 404
    app.dependency_overrides.clear()


def test_one_time_pairing_code_and_device_session_access(tmp_path, monkeypatch):
    monkeypatch.setattr(session_service, "DB_PATH", tmp_path / "sessions.sqlite3")
    main = __import__("main")
    main.app.dependency_overrides[main.require_firebase_user] = lambda authorization=None: {"uid": "alice"}
    client = TestClient(main.app)

    code_response = client.post("/api/devices/pairing-code", headers={"Authorization": "Bearer firebase-test"}, json={"device_label": "Desktop"})
    assert code_response.status_code == 200
    code = code_response.json()["code"]
    paired = client.post("/api/devices/pair", json={"code": code, "device_label": "Desktop"})
    assert paired.status_code == 200
    token = paired.json()["device_token"]
    assert token.startswith("udv_")
    assert client.post("/api/devices/pair", json={"code": code}).status_code == 401

    headers = {"Authorization": f"Bearer {token}"}
    session = client.post("/api/sessions", headers=headers, json={"title": "From desktop"})
    assert session.status_code == 200
    assert client.get("/api/sessions", headers=headers).json()["sessions"][0]["title"] == "From desktop"
    main.app.dependency_overrides.clear()
