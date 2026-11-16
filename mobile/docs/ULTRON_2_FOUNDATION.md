# ULTRON Mobile — shared protocol

The Flutter mirror of the canonical contract is `lib/core/ultron_protocol.dart`.

Keep its field names, supported event names, sources, assistant states, and version aligned with the desktop repository's `shared/ultron_protocol.json`.

Run the contract tests with:

```sh
cd mobile
flutter test test/core/ultron_protocol_test.dart
```

This module only defines and validates event data. It does not grant permissions or authorize computer/device actions.
