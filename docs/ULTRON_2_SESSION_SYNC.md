# ULTRON 2.0 authenticated session sync

## What this adds

- Firebase-authenticated users can create a five-minute, one-time desktop pairing code from ULTRON Mobile.
- ULTRON Desktop exchanges the code for a random, revocable device credential. Only a SHA-256 digest of that credential is stored by the backend.
- Firebase users and paired desktop devices can create sessions and append/read protocol v1.0 events. Every session lookup is scoped to the authenticated Firebase UID.
- Device credentials can be listed and revoked by the owning Firebase account.
- The desktop app stores its device credential in its local ULTRON data directory. It is not an AI-provider key and grants access only to the owner's session/event API.

## Configuration

Mobile build:
- `--dart-define=ULTRON_TOKEN_ENDPOINT=https://YOUR_API_HOST/api/token`
- `--dart-define=ULTRON_SESSION_ENDPOINT=https://YOUR_API_HOST`

Desktop `.env`:
- `ULTRON_SESSION_API_URL=https://YOUR_API_HOST`

Start pairing:
1. Sign in to ULTRON Mobile and tap **PAIR DESKTOP**.
2. In ULTRON Desktop, call its authenticated local endpoint `POST /api/session/pair` with JSON `{"code":"THE_CODE"}` and the existing local `x-ultron: 1` request header.
3. Once paired, desktop chat turns are synced as user/assistant events. Existing local history, AI provider routing, LiveKit token service, and local automation remain in place.

## Security boundaries

- Firebase ID tokens are verified server-side, including revoked-token checks through the existing verifier.
- Pairing codes expire after five minutes and are consumed exactly once.
- Device bearer tokens are random, stored only as hashes on the backend, and can be revoked by the owning Firebase user.
- AI provider keys, LiveKit secrets, and privileged desktop automation are not moved to this service.
- The desktop credential file is stored locally under the ULTRON data directory; protect the Windows user account and device. Do not copy this file into backups or source control.
- Deploy the FastAPI service behind HTTPS. Configure an explicit CORS allowlist for the mobile app's web origins if needed.

## Verification

The backend tests cover unauthenticated rejection, owner isolation, one-time pairing, session event persistence, and device revocation. The desktop tests cover pairing persistence and the unpaired no-op path.


## Shared session continuity (Module 2)

A mobile pairing-code request creates an owner-scoped shared session and returns its session_id. The one-time desktop exchange returns that same ID with the revocable device credential. Desktop chat events and mobile LiveKit voice lifecycle events are appended to this shared session. Mobile can reload the latest owned session and read its event history after signing in again.

Session creation is idempotent for the same owner and ID. Event timestamps must include a timezone; optional request_id correlation values are persisted and returned. Existing SQLite databases are upgraded in place with the new event and pairing columns.

The mobile API client refuses plain HTTP for non-loopback hosts so Firebase ID tokens are not sent to a remote endpoint without TLS. Deploy the FastAPI service behind HTTPS and mount a persistent volume for ULTRON_SESSION_DB; the included SQLite store is intended for a single backend instance, not an ephemeral serverless filesystem.


Desktop device tokens are least-privilege: each token can read and append only to the one session created for its pairing. They cannot enumerate the owner's other sessions, create new sessions, issue pairing codes, or revoke devices. Legacy device tokens without a session scope are rejected and must be re-paired.
