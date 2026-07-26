import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/pp.dart';
import '../services/api_service.dart';
import '../services/task_poller.dart';

class AiChatScreen extends StatefulWidget {
  final bool isTab;
  const AiChatScreen({super.key, this.isTab = false});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;

  final _suggestions = ['What should I avoid?', 'Is SLS safe for me?', 'Best for sensitive skin?', 'Explain Retinol'];

  @override
  void initState() {
    super.initState();
    _messages.add({'role': 'bot', 'text': "Hello! I'm your PurePick AI beauty advisor. I've reviewed your profile and I'm ready to help with ingredient questions."});
  }

  @override
  void dispose() { _ctrl.dispose(); _scroll.dispose(); super.dispose(); }

  void _scrollToBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  });

  Future<void> _send([String? text]) async {
    final q = (text ?? _ctrl.text).trim();
    if (q.isEmpty || _loading) return;
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getInt('user_id') ?? 0;
    setState(() { _messages.add({'role': 'user', 'text': q}); _ctrl.clear(); _loading = true; });
    _scrollToBottom();
    try {
      // Send up to last 10 messages as history for context
      final history = _messages.length > 1
          ? _messages.sublist(0, _messages.length - 1)
              .map((m) => {'role': m['role']!, 'text': m['text']!})
              .toList()
          : <Map<String, String>>[];

      final res = await ApiService.chatWithAI(q, uid, history: history);
      final taskId = res['task_id'] as String?;
      String reply = "I'm having trouble connecting. Please try again.";
      if (taskId != null) {
        final result = await TaskPoller.poll(taskId);
        reply = result['response'] as String? ?? reply;
      }
      if (mounted) { setState(() { _messages.add({'role': 'bot', 'text': reply}); _loading = false; }); _scrollToBottom(); }
    } on TaskFailedException catch (e) {
      if (mounted) { setState(() { _messages.add({'role': 'bot', 'text': e.message}); _loading = false; }); }
    } catch (_) {
      if (mounted) { setState(() { _messages.add({'role': 'bot', 'text': "I'm having trouble connecting. Please try again."}); _loading = false; }); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: LuxAppBar(title: 'PurePick AI', showBack: !widget.isTab),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final isUser = _messages[i]['role'] == 'user';
                return _Bubble(text: _messages[i]['text']!, isUser: isUser);
              },
            ),
          ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 24),
              child: Row(children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: PP.rose)),
                const SizedBox(width: 8),
                Text('Thinking...', style: PP.label(12, color: PP.muted)),
              ]),
            ),
          if (_messages.length == 1)
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _send(_suggestions[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF261A1F) : PP.roseTint, 
                      borderRadius: PP.pill,
                      border: Border.all(color: isDark ? const Color(0xFF3D2A30) : PP.roseLt.withOpacity(0.4)),
                    ),
                    child: Text(_suggestions[i], style: PP.label(12, color: PP.rose, weight: FontWeight.w500)),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: isDark ? const Color(0xFF3D2A30) : PP.border, width: 0.8)),
            ),
            child: Row(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A1015) : PP.roseTint, 
                    borderRadius: PP.r28, 
                    border: Border.all(color: isDark ? const Color(0xFF3D2A30) : PP.border),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    enabled: !_loading,
                    maxLines: 3, minLines: 1,
                    style: PP.body(14, color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Ask about any ingredient...',
                      hintStyle: PP.body(14, color: PP.muted.withOpacity(0.7)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _loading ? null : () => _send(),
                child: Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    gradient: _loading ? null : PP.roseGrad,
                    color: _loading ? (isDark ? Colors.white10 : PP.border) : null,
                    shape: BoxShape.circle,
                    boxShadow: _loading ? [] : PP.buttonShadow,
                  ),
                  child: Icon(Icons.send_rounded, color: _loading ? PP.muted : Colors.white, size: 20),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool isUser;
  const _Bubble({required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: isUser ? PP.roseGrad : null,
          color: isUser ? null : (isDark ? const Color(0xFF261A1F) : PP.surface),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: PP.softShadow,
          border: isUser ? null : Border.all(color: isDark ? const Color(0xFF3D2A30) : PP.border, width: 0.8),
        ),
        child: MarkdownBody(
          data: text,
          styleSheet: MarkdownStyleSheet(
            p: PP.body(14, color: isUser ? Colors.white : theme.colorScheme.onSurface),
            strong: PP.heading(14, color: isUser ? Colors.white : theme.colorScheme.onSurface, weight: FontWeight.w700),
            listBullet: PP.body(14, color: isUser ? Colors.white70 : PP.rose),
          ),
        ),
      ),
    );
  }
}
