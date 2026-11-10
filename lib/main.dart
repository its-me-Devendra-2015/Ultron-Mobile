import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/ultron_api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UltronApp());
}

class UltronApp extends StatelessWidget {
  const UltronApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ULTRON',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF090B10),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF3B45),
            secondary: Color(0xFFFF7043),
            surface: Color(0xFF141821),
          ),
          useMaterial3: true,
          fontFamily: 'Roboto',
        ),
        home: const AssistantScreen(),
      );
}

class ChatMessage {
  const ChatMessage(this.text, this.fromUser);
  final String text;
  final bool fromUser;
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  static const _secure = FlutterSecureStorage();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <ChatMessage>[];
  late SharedPreferences _prefs;
  late UltronApi _api;
  String _endpoint = 'http://10.0.2.2:20128/v1';
  String _model = 'gemma3';
  String _status = 'Not connected';
  bool _sending = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _endpoint = _prefs.getString('endpoint') ?? _endpoint;
    _model = _prefs.getString('model') ?? _model;
    final key = await _secure.read(key: 'api_key') ?? '';
    _api = UltronApi(baseUrl: _endpoint, apiKey: key, model: _model);
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _openSettings() async {
    final endpoint = TextEditingController(text: _endpoint);
    final model = TextEditingController(text: _model);
    final key = TextEditingController(
      text: await _secure.read(key: 'api_key') ?? '',
    );
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171C26),
        title: const Text('Connection settings'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _settingField(endpoint, 'Server URL', 'http://192.168.1.5:20128/v1'),
            const SizedBox(height: 12),
            _settingField(model, 'Model ID', 'gemma3'),
            const SizedBox(height: 12),
            _settingField(key, 'API key (optional)', 'Your API key', obscure: true),
            const SizedBox(height: 8),
            const Text('Use your computer’s LAN IP when connecting from a real phone. The Android emulator can use 10.0.2.2 to reach the host PC.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('SAVE')),
        ],
      ),
    );
    if (saved != true) return;
    final normalized = endpoint.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      _showError('Server URL must start with http:// or https://');
      return;
    }
    await _prefs.setString('endpoint', normalized);
    await _prefs.setString('model', model.text.trim());
    await _secure.write(key: 'api_key', value: key.text.trim());
    _endpoint = normalized;
    _model = model.text.trim().isEmpty ? 'gemma3' : model.text.trim();
    _api = UltronApi(baseUrl: _endpoint, apiKey: key.text.trim(), model: _model);
    setState(() => _status = 'Settings saved · not tested');
  }

  Widget _settingField(TextEditingController controller, String label, String hint,
      {bool obscure = false}) => TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label, hintText: hint,
          filled: true, fillColor: const Color(0xFF0D1119),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
      );

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || !_ready) return;
    _input.clear();
    setState(() {
      _messages.add(ChatMessage(text, true));
      _sending = true;
      _status = 'ULTRON is thinking…';
    });
    _jumpToBottom();
    try {
      final history = _messages.map((m) => {
        'role': m.fromUser ? 'user' : 'assistant', 'content': m.text,
      }).toList();
      final reply = await _api.chat(history);
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(reply, false));
        _status = 'Connected · $_model';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Connection error');
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _jumpToBottom();
      }
    }
  }

  Future<void> _testConnection() async {
    if (!_ready) return;
    setState(() => _status = 'Checking server…');
    try {
      final models = await _api.listModels();
      if (!mounted) return;
      setState(() => _status = 'Online · ${models.isEmpty ? "server reachable" : "${models.length} model(s)"}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Connection failed');
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message), backgroundColor: const Color(0xFF9F2630)));
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: const Color(0xFF0D1119),
      title: Row(children: [
        Container(width: 34, height: 34,
          decoration: BoxDecoration(color: const Color(0x22FF3B45),
            borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0x66FF3B45))),
          child: const Icon(Icons.bolt, color: Color(0xFFFF4B52))),
        const SizedBox(width: 10),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ULTRON', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 17)),
          Text('MOBILE INTERFACE', style: TextStyle(fontSize: 9, color: Colors.white54, letterSpacing: 1.5)),
        ]),
        const Spacer(),
        IconButton(tooltip: 'Test connection', onPressed: _testConnection,
          icon: const Icon(Icons.wifi_tethering, color: Color(0xFFFF555D))),
        IconButton(tooltip: 'Settings', onPressed: _openSettings,
          icon: const Icon(Icons.tune)),
      ]),
    ),
    body: Column(children: [
      Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF21151B), Color(0xFF151922)]),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0x44FF3B45))),
        child: Row(children: [
          Container(width: 9, height: 9,
            decoration: BoxDecoration(color: _status.startsWith('Online') || _status.startsWith('Connected')
              ? const Color(0xFF4ADE80) : const Color(0xFFFF555D), shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('SYSTEM STATUS', style: TextStyle(fontSize: 9, color: Colors.white54, letterSpacing: 1.5)),
            Text(_status, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ])),
          Text('v1.0.0', style: TextStyle(color: Colors.white.withValues(alpha: .35), fontSize: 10)),
        ]),
      ),
      Expanded(child: _messages.isEmpty ? _welcome() : ListView.builder(
        controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        itemCount: _messages.length + (_sending ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _messages.length) {
            return const Padding(padding: EdgeInsets.all(12),
              child: Align(alignment: Alignment.centerLeft,
                child: Text('ULTRON is processing…', style: TextStyle(color: Colors.white54, fontSize: 12))));
          }
          final m = _messages[index];
          return Align(
            alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: m.fromUser ? const Color(0xFF6F202A) : const Color(0xFF171D28),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: m.fromUser ? const Color(0x66FF555D) : const Color(0xFF293140))),
              child: SelectableText(m.text, style: const TextStyle(fontSize: 14, height: 1.45))),
          );
        },
      )),
      SafeArea(top: false, child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: const BoxDecoration(color: Color(0xFF0D1119),
          border: Border(top: BorderSide(color: Color(0xFF222936)))),
        child: Row(children: [
          Expanded(child: TextField(
            controller: _input, minLines: 1, maxLines: 5,
            textInputAction: TextInputAction.send, onSubmitted: (_) => _send(),
            decoration: InputDecoration(hintText: 'Message ULTRON…',
              filled: true, fillColor: const Color(0xFF171D28),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none)),
          )),
          const SizedBox(width: 9),
          SizedBox(width: 48, height: 48, child: FilledButton(
            onPressed: _sending || !_ready ? null : _send,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF3B45),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), padding: EdgeInsets.zero),
            child: const Icon(Icons.arrow_upward, color: Colors.white))),
        ]),
      )),
    ]),
  );

  Widget _welcome() => Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 104, height: 104,
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: const Color(0x22FF3B45), border: Border.all(color: const Color(0x88FF3B45), width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x33FF3B45), blurRadius: 35)]),
        child: const Icon(Icons.bolt, size: 58, color: Color(0xFFFF555D))),
      const SizedBox(height: 26),
      const Text('YOUR ASSISTANT.\nYOUR COMMAND.', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: 1.2, height: 1.35)),
      const SizedBox(height: 12),
      const Text('Connect to your ULTRON server and start a conversation.',
        textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, height: 1.5)),
      const SizedBox(height: 22),
      OutlinedButton.icon(onPressed: _openSettings,
        icon: const Icon(Icons.settings_ethernet), label: const Text('CONFIGURE SERVER'),
        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF6269),
          side: const BorderSide(color: Color(0x88FF3B45)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13))),
      const SizedBox(height: 8),
      TextButton(onPressed: _testConnection, child: const Text('TEST CONNECTION')),
    ]),
  ));
}
