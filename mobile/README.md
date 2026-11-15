# Flutter client setup

This folder is the Flutter app source and LiveKit voice client. The repository intentionally does not contain Firebase configuration files or signing credentials.

## Generate platform projects

From this folder, install Flutter and run:

```powershell
flutter create --platforms=android,ios .
flutter pub get
```

## Configure Firebase Authentication

1. Create or select a Firebase project.
2. Enable **Email/Password** under Authentication → Sign-in method.
3. Install FlutterFire CLI and run `flutterfire configure` from this folder.
4. Add the generated Android and iOS Firebase configuration to the native projects.
5. Ensure the Firebase project used by the app is the same one trusted by the backend's Firebase Admin credentials.

The current sign-in screen supports email/password sign-in and account creation.

## Run against your deployed token API

```powershell
flutter run --dart-define=ULTRON_TOKEN_ENDPOINT=https://YOUR_API_HOST/api/token
```

Android microphone permission and iOS `NSMicrophoneUsageDescription` must be present in the generated native project. Test on a physical phone; iOS Simulator microphone and audio routing do not fully represent a real device.

The app obtains a Firebase ID token at session start, requests a LiveKit participant token from the Python API, joins the room, and enables the microphone. It never receives the LiveKit API secret.


## Multilingual voice settings

The voice screen is in English and offers automatic detection plus 27 language selections. The app sends the selected language to the LiveKit room using a reliable data packet on the `ultron.control` topic. Packet format:

```json
{ "type": "ultron.language.set", "language": "auto" }
```

The LiveKit Agents worker must listen for this topic and apply the selected language to speech recognition, the assistant's response instructions, and text-to-speech. The worker source is not included in this repository, so selecting a language in the mobile UI alone does not guarantee multilingual speech until that server-side handler is deployed. Supported languages also depend on the chosen STT and TTS providers.
