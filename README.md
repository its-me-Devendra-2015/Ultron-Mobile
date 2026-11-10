# ULTRON Mobile — LiveKit foundation

This repository contains the LiveKit token service and Flutter voice-connection module for ULTRON Mobile.

## Architecture

1. The user signs in through Firebase Authentication in the Flutter app.
2. The app sends its Firebase ID token to `POST /api/token`.
3. The Python service verifies that ID token with Firebase Admin, derives the room name from the verified UID, and mints a short-lived (10-minute), room-scoped LiveKit JWT.
4. The Flutter app connects to LiveKit and publishes microphone audio.
5. Your deployed LiveKit Agents worker joins the same room and runs ULTRON's voice/AI pipeline.

The LiveKit API key and secret exist only in the Python service environment. Never put them in Flutter, Git, or a public CI variable. Set `LIVEKIT_AGENT_NAME` in the backend only if you want explicit dispatch to a named worker; it must match the worker's registered agent name. Leave it empty if your worker uses automatic dispatch.

## Backend setup

Python 3.12+ is recommended.

```bash
cd backend
python -m venv .venv
# Windows PowerShell: .venv\\Scripts\\Activate.ps1
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
```

Copy `.env.example` to `.env`, set the LiveKit project URL/key/secret, and set `GOOGLE_APPLICATION_CREDENTIALS` to a Firebase Admin service-account JSON file. Keep that JSON outside the repository. Then run:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

Deploy behind HTTPS. Configure Firebase Authentication in the mobile app and enable the same Firebase project in the backend. The backend must have access to the Firebase service account via a secret mount or workload identity.

### Endpoint

`POST /api/token`

Headers: `Authorization: Bearer <Firebase ID token>`

Body:

```json
{ "session_id": "a UUID generated for this voice session" }
```

Response (201):

```json
{ "server_url": "wss://your-project.livekit.cloud", "participant_token": "<short-lived JWT>" }
```

The client cannot choose its identity, room name, or permissions. Each token is restricted to one room and expires after 10 minutes. The service also checks Firebase token revocation.

## Flutter integration

The LiveKit connection helper is in `mobile/lib/services/livekit_voice_service.dart`. Add the dependencies in `mobile/pubspec.yaml` to your Flutter app, initialize Firebase using your platform Firebase configuration, then instantiate:

```dart
final voice = UltronLiveKitVoiceService(
  tokenEndpoint: Uri.parse('https://YOUR_API_HOST/api/token'),
);
final room = await voice.connect();
```

Call `await voice.disconnect()` when the user ends the voice session, and `voice.dispose()` when the service is no longer needed.

## Agent dispatch

Deploy the ULTRON LiveKit Agents worker separately with its own server-side credentials and the same LiveKit project. Configure the worker's dispatch policy so it accepts rooms created for ULTRON sessions. Do not place agent credentials or provider API keys in the mobile app.

## Production checklist

- Use HTTPS for the token endpoint.
- Store LiveKit secrets and Firebase service-account credentials in your hosting provider's secret manager.
- Restrict CORS to known web origins if web clients are enabled.
- Add per-user rate limiting and abuse monitoring at the gateway before public launch.
- Configure Firebase App Check / device attestation if appropriate for your threat model.
- Keep the LiveKit agent worker private and deploy it independently of the token API.
- Never commit `.env`, service-account JSON, certificates, or signing keys.
