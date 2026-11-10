import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'services/livekit_voice_service.dart';

const tokenEndpoint = String.fromEnvironment('ULTRON_TOKEN_ENDPOINT');

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
  String? error;

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
      voice ??= UltronLiveKitVoiceService(tokenEndpoint: Uri.parse(tokenEndpoint));
      await voice!.connect();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ULTRON // MOBILE'),
        actions: [IconButton(
          tooltip: 'Sign out',
          onPressed: () async {
            await voice?.disconnect();
            await FirebaseAuth.instance.signOut();
          },
          icon: const Icon(Icons.logout),
        )],
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
              Icon(
                connected ? Icons.graphic_eq : Icons.mic_none,
                size: 92,
                color: connected ? Colors.greenAccent : const Color(0xFFEF233C),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: connecting ? null : toggleVoice,
                icon: Icon(connected ? Icons.call_end : Icons.mic),
                label: Text(connecting ? 'CONNECTING…' : connected ? 'END VOICE SESSION' : 'START VOICE SESSION'),
              ),
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
