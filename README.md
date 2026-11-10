# ULTRON Mobile

A Flutter companion app for **Android and iOS**. The first milestone provides a native mobile chat interface that connects to an OpenAI-compatible ULTRON API endpoint. It is a separate project from the ULTRON desktop repository.

## Current features

- Dark crimson ULTRON-inspired mobile interface
- Chat interface with selectable assistant responses
- Configurable server URL, model ID, and optional API key
- Connection test through the OpenAI-compatible `/models` endpoint
- Chat requests through `/chat/completions`
- API key stored with the platform secure-storage plugin
- GitHub Actions jobs for analysis, tests, Android APK, and iOS simulator build

## Connect to ULTRON

1. Start your ULTRON server with an OpenAI-compatible API enabled.
2. Ensure your phone and computer are on the same Wi-Fi network.
3. In the app, open **Settings** and enter the server URL, model ID, and API key if required.
4. Tap **Test connection**, then send a message.

Examples:
- Android emulator: `http://10.0.2.2:20128/v1`
- Physical Android/iPhone: `http://YOUR-PC-LAN-IP:20128/v1`

The desktop server must listen on a LAN-reachable interface (not only `127.0.0.1`) for physical devices. Configure firewall access only for the trusted private network. Use HTTPS and an authentication key outside a trusted local development network.

## Compatibility note

The mobile client currently expects the OpenAI-compatible API routes `GET /models` and `POST /chat/completions`. It does not yet remotely control desktop-only features such as screen capture, PC input, Gmail, or local files. Those require dedicated authenticated mobile endpoints in the desktop server; do not expose desktop-control endpoints directly to the public internet.

## Build locally

Install Flutter stable, then:

```bash
flutter create --platforms=android,ios --project-name ultron_mobile .
flutter pub get
flutter analyze
flutter test
flutter run
```

Android APK: `flutter build apk --release`

iOS requires macOS and Xcode for a device build/signing. The GitHub Actions iOS job builds an unsigned simulator app; it does not create a signed App Store IPA.

## CI artifacts

The Android workflow uploads a debug APK artifact. The iOS workflow validates a simulator build. Release signing and distribution are intentionally not configured until signing credentials and distribution targets are provided.
