import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'services/livekit_voice_service.dart';
import 'services/shared_session_api.dart';

const tokenEndpoint = String.fromEnvironment('ULTRON_TOKEN_ENDPOINT');
const sessionEndpoint = String.fromEnvironment('ULTRON_SESSION_ENDPOINT');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const UltronMobileApp());
}

class UltronMobileApp extends StatelessWidget {
  const UltronMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ULTRON Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFEF233C),
          brightness: Brightness.dark,
          surface: const Color(0xFF101014),
        ),
        scaffoldBackgroundColor: const Color(0xFF08080B),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.data == null) return const SignInScreen();
          return const VoiceScreen();
        },
      );
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool creating = false;
  bool busy = false;
  String? error;

  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try {
      if (creating) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.memory, color: Color(0xFFEF233C), size: 64),
                  const SizedBox(height: 12),
                  const Text('ULTRON', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 5)),
                  const SizedBox(height: 8),
                  const Text('SECURE VOICE INTERFACE', textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, letterSpacing: 2)),
                  const SizedBox(height: 32),
                  TextField(controller: email, keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: password, obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy ? 'PLEASE WAIT…' : creating ? 'CREATE ACCOUNT' : 'SIGN IN'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => setState(() { creating = !creating; error = null; }),
                    child: Text(creating ? 'Already registered? Sign in' : 'New user? Create account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  UltronLiveKitVoiceService? voice;
  bool connecting = false;
  bool connected = false;
  bool loadingHistory = false;
  String? error;
  String? pairedSessionId;
  SharedSessionApi? sessionApi;

  @override
  void initState() {
    super.initState();
    if (sessionEndpoint.isNotEmpty) {
      sessionApi = SharedSessionApi(
        baseUri: Uri.parse(sessionEndpoint),
        tokenProvider: () async {
          final user = FirebaseAuth.instance.currentUser;
          return user == null ? null : await user.getIdToken(true);
        },
      );
      _loadLatestSession();
    }
  }

  Future<void> _loadLatestSession() async {
    try {
      final sessions = await sessionApi?.listSessions();
      if (!mounted || sessions == null || sessions.isEmpty) return;
      final id = sessions.first['session_id'];
      if (id is String) setState(() => pairedSessionId = id);
    } catch (_) {
      // The voice screen remains usable if shared-session history is unavailable.
    }
  }

  Future<void> pairDesktop() async {
    final api = sessionApi;
    if (api == null) {
      setState(() => error = 'Missing ULTRON_SESSION_ENDPOINT build setting.');
      return;
    }
    setState(() { error = null; });
    try {
      final data = await api.createPairingCode();
      final code = data['code'];
      final sessionId = data['session_id'];
      if (code is! String || sessionId is! String) {
        throw const FormatException('The session service returned an incomplete pairing response.');
      }
      if (!mounted) return;
      setState(() => pairedSessionId = sessionId);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('PAIR ULTRON DESKTOP'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Enter this one-time code in ULTRON Desktop. It expires in 5 minutes.'),
            const SizedBox(height: 18),
            SelectableText(code,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 5)),
            const SizedBox(height: 12),
            Text('Shared session: ${sessionId.substring(0, 8)}'),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CLOSE'))],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> showSharedHistory() async {
    final api = sessionApi;
    final sessionId = pairedSessionId;
    if (api == null || sessionId == null) {
      setState(() => error = 'Pair ULTRON Desktop or create a voice session first.');
      return;
    }
    setState(() { loadingHistory = true; error = null; });
    try {
      final events = await api.readEvents(sessionId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ULTRON SHARED SESSION'),
          content: SizedBox(
            width: 440,
            height: 420,
            child: events.isEmpty
                ? const Center(child: Text('No shared events yet.'))
                : ListView.separated(
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final event = events[index];
                      final type = event['event_type']?.toString() ?? 'event';
                      final rawPayload = event['payload'];
                      final payload = rawPayload is Map
                          ? Map<String, dynamic>.from(rawPayload)
                          : const <String, dynamic>{};
                      final message = payload['text']?.toString() ??
                          payload.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n');
                      return ListTile(
                        dense: true,
                        title: Text(type.toUpperCase()),
                        subtitle: Text(message.isEmpty ? '—' : message),
                      );
                    },
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CLOSE'))],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loadingHistory = false);
    }
  }

  Future<void> manageDevices() async {
    final api = sessionApi;
    if (api == null) {
      setState(() => error = 'Missing ULTRON_SESSION_ENDPOINT build setting.');
      return;
    }
    setState(() => error = null);
    try {
      final devices = (await api.listDevices())
          .map((device) => Map<String, dynamic>.from(device))
          .toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, updateDialog) => AlertDialog(
            title: const Text('PAIRED DEVICES'),
            content: SizedBox(
              width: 440,
              height: 360,
              child: devices.isEmpty
                  ? const Center(child: Text('No paired desktops yet.'))
                  : ListView.separated(
                      itemCount: devices.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final deviceId = device['device_id']?.toString() ?? '';
                        final revoked = device['revoked'] == true;
                        return ListTile(
                          dense: true,
                          title: Text(device['name']?.toString() ?? 'ULTRON device'),
                          subtitle: Text(
                            revoked
                                ? 'Revoked'
                                : 'Last used: ${device['last_used_at'] ?? 'Not yet used'}',
                          ),
                          trailing: revoked
                              ? const Text('REVOKED')
                              : TextButton(
                                  onPressed: deviceId.isEmpty
                                      ? null
                                      : () async {
                                          try {
                                            await api.revokeDevice(deviceId);
                                            updateDialog(() {
                                              devices[index] = {...device, 'revoked': true};
                                            });
                                          } catch (e) {
                                            if (mounted) {
                                              setState(() => error = e.toString());
                                            }
                                          }
                                        },
                                  child: const Text('REVOKE'),
                                ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CLOSE'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> toggleVoice() async {
    if (connected) {
      await voice?.disconnect();
      if (mounted) setState(() => connected = false);
      return;
    }
    if (tokenEndpoint.isEmpty) {
      setState(() => error = 'Missing ULTRON_TOKEN_ENDPOINT build setting.');
      return;
    }
    setState(() { connecting = true; error = null; });
    try {
      voice ??= UltronLiveKitVoiceService(
        tokenEndpoint: Uri.parse(tokenEndpoint),
        sessionEndpoint: sessionEndpoint.isEmpty ? null : Uri.parse(sessionEndpoint),
      );
      await voice!.connect(sessionId: pairedSessionId);
      if (mounted) setState(() => connected = true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  @override
  void dispose() {
    voice?.disconnect();
    voice?.dispose();
    sessionApi?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ULTRON // MOBILE'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await voice?.disconnect();
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.memory, size: 76, color: Color(0xFFEF233C)),
              const SizedBox(height: 20),
              const Text('VOICE LINK', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 3)),
              const SizedBox(height: 8),
              Text(user?.email ?? 'Authenticated', style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 40),
              Icon(connected ? Icons.graphic_eq : Icons.mic_none, size: 92,
                color: connected ? Colors.greenAccent : const Color(0xFFEF233C)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: connecting ? null : toggleVoice,
                icon: Icon(connected ? Icons.call_end : Icons.mic),
                label: Text(connecting ? 'CONNECTING…' : connected ? 'END VOICE SESSION' : 'START VOICE SESSION'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: connecting ? null : pairDesktop,
                icon: const Icon(Icons.devices),
                label: const Text('PAIR DESKTOP'),
              ),
              if (sessionApi != null)
                OutlinedButton.icon(
                  onPressed: manageDevices,
                  icon: const Icon(Icons.security),
                  label: const Text('MANAGE DEVICES'),
                ),
              if (pairedSessionId != null) ...[
                const SizedBox(height: 12),
                Text(
                  'SHARED SESSION · ${pairedSessionId!.substring(0, 8)}',
                  style: const TextStyle(color: Colors.white54, letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: loadingHistory ? null : showSharedHistory,
                  icon: const Icon(Icons.forum_outlined),
                  label: Text(loadingHistory ? 'LOADING HISTORY…' : 'VIEW SHARED HISTORY'),
                ),
              ],
              const SizedBox(height: 16),
              Text(connected ? 'LIVEKIT CONNECTED' : 'STANDBY',
                style: TextStyle(color: connected ? Colors.greenAccent : Colors.white54, letterSpacing: 2)),
              if (error != null) ...[
                const SizedBox(height: 20),
                Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
