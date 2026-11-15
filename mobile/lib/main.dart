import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'services/livekit_voice_service.dart';

const tokenEndpoint = String.fromEnvironment('ULTRON_TOKEN_ENDPOINT');

const voiceLanguages = <String, String>{
  'auto': 'Automatic detection',
  'en': 'English',
  'hi': 'Hindi',
  'te': 'Telugu',
  'ta': 'Tamil',
  'kn': 'Kannada',
  'ml': 'Malayalam',
  'bn': 'Bengali',
  'mr': 'Marathi',
  'gu': 'Gujarati',
  'pa': 'Punjabi',
  'ur': 'Urdu',
  'ar': 'Arabic',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh': 'Chinese',
  'th': 'Thai',
  'id': 'Indonesian',
  'vi': 'Vietnamese',
  'tr': 'Turkish',
  'it': 'Italian',
  'nl': 'Dutch',
  'pl': 'Polish',
};

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
  String selectedLanguage = 'auto';
  String? error;

  Future<void> changeLanguage(String? code) async {
    if (code == null) return;
    setState(() {
      selectedLanguage = code;
      error = null;
    });
    if (connected && voice != null) {
      try {
        await voice!.setLanguage(code);
      } catch (e) {
        if (mounted) setState(() => error = 'Could not update voice language: $e');
      }
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
    setState(() {
      connecting = true;
      error = null;
    });
    try {
      voice ??= UltronLiveKitVoiceService(tokenEndpoint: Uri.parse(tokenEndpoint));
      await voice!.connect(languageCode: selectedLanguage);
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
    final languageName = voiceLanguages[selectedLanguage] ?? 'Automatic detection';

    return Scaffold(
      appBar: AppBar(
        title: const Text('ULTRON MOBILE'),
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          children: [
            const SizedBox(height: 12),
            const Icon(Icons.memory, size: 76, color: Color(0xFFEF233C)),
            const SizedBox(height: 14),
            const Text(
              'ULTRON',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 5),
            ),
            const SizedBox(height: 6),
            const Text(
              'PERSONAL AI VOICE ASSISTANT',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, letterSpacing: 1.8, fontSize: 11),
            ),
            const SizedBox(height: 12),
            Text(
              user?.email ?? 'Signed in',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111116),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF34343D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.translate, color: Color(0xFFEF233C)),
                      SizedBox(width: 10),
                      Text('VOICE LANGUAGE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: selectedLanguage,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Conversation language',
                      border: OutlineInputBorder(),
                    ),
                    items: voiceLanguages.entries.map((entry) {
                      return DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      );
                    }).toList(),
                    onChanged: connecting ? null : changeLanguage,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Automatic detection lets ULTRON follow the language you speak. Choose a language to request it explicitly.',
                    style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
              decoration: BoxDecoration(
                color: const Color(0xFF111116),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: connected ? Colors.greenAccent.withValues(alpha: 0.5) : const Color(0xFF34343D),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    connected ? Icons.graphic_eq : Icons.mic_none,
                    size: 76,
                    color: connected ? Colors.greenAccent : const Color(0xFFEF233C),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    connected ? 'VOICE SESSION ACTIVE' : 'READY TO CONNECT',
                    style: TextStyle(
                      color: connected ? Colors.greenAccent : Colors.white70,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Language: $languageName',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: connecting ? null : toggleVoice,
                    icon: Icon(connected ? Icons.call_end : Icons.mic),
                    label: Text(
                      connecting ? 'CONNECTING…' : connected ? 'END VOICE SESSION' : 'START VOICE SESSION',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: connected ? const Color(0xFF8E1B2A) : const Color(0xFFEF233C),
                    ),
                  ),
                ],
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 18),
              Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 18),
            const Text(
              'English app interface • Multilingual conversations',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
