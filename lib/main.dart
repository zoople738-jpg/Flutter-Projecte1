import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LocalMindApp());
}

class MemoryCard {
  MemoryCard({required this.title, required this.content, this.isBuiltIn = false});
  final String title;
  final String content;
  final bool isBuiltIn;
  Map<String, dynamic> toJson() => {'title': title, 'content': content};
  factory MemoryCard.fromJson(Map<String, dynamic> json) => MemoryCard(title: json['title'] as String? ?? 'Untitled memory', content: json['content'] as String? ?? '');
}

class ChatMessage {
  ChatMessage(this.text, {this.fromUser = false});
  final String text;
  final bool fromUser;
}

class LocalMindApp extends StatelessWidget {
  const LocalMindApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LocalMind',
        theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFF7F8FC), colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6657F5)), textTheme: const TextTheme(headlineMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF172033), letterSpacing: -1), titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF172033)), bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: Color(0xFF5E6575)))),
        home: const LocalMindHome(),
      );
}

class LocalMindHome extends StatefulWidget {
  const LocalMindHome({super.key});
  @override
  State<LocalMindHome> createState() => _LocalMindHomeState();
}

class _LocalMindHomeState extends State<LocalMindHome> {
  static const _storageKey = 'localmind.memory.v1';
  int _page = 0;
  bool _loading = true;
  final _input = TextEditingController();
  final _title = TextEditingController();
  final _content = TextEditingController();
  final List<ChatMessage> _messages = [ChatMessage('Hi, I’m LocalMind. I work entirely on this device. Ask me anything from my local knowledge, or teach me something new.')];
  List<MemoryCard> _memories = [];
  final _starterMemories = <MemoryCard>[
    MemoryCard(title: 'About LocalMind', content: 'LocalMind is a private, offline-first personal assistant. It uses local notes and memories to find relevant answers. It does not connect to an API or send data anywhere.', isBuiltIn: true),
    MemoryCard(title: 'How learning works', content: 'Add a memory with a short title and useful content. LocalMind stores it on this device and uses matching words to retrieve it in future conversations.', isBuiltIn: true),
    MemoryCard(title: 'Privacy promise', content: 'Your conversations and memories stay on this device. You can export a JSON backup at any time and restore it later.', isBuiltIn: true),
  ];

  @override
  void initState() { super.initState(); _loadMemories(); }
  @override
  void dispose() { _input.dispose(); _title.dispose(); _content.dispose(); super.dispose(); }

  Future<void> _loadMemories() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);
    if (!mounted) return;
    setState(() { _memories = saved == null ? List.of(_starterMemories) : (jsonDecode(saved) as List).map((item) => MemoryCard.fromJson(item as Map<String, dynamic>)).toList(); _loading = false; });
  }
  Future<void> _saveMemories() async { final prefs = await SharedPreferences.getInstance(); await prefs.setString(_storageKey, jsonEncode(_memories.map((memory) => memory.toJson()).toList())); }

  String _answer(String question) {
    final words = question.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((word) => word.length > 2).toSet();
    final matches = _memories.map((memory) { final haystack = '${memory.title} ${memory.content}'.toLowerCase(); return (memory: memory, score: words.where(haystack.contains).length); }).where((match) => match.score > 0).toList()..sort((a, b) => b.score.compareTo(a.score));
    if (matches.isEmpty) return 'I don’t have a local memory that answers that yet. Teach me using the Knowledge tab, and I’ll be able to use it next time.';
    return matches.take(2).map((match) => 'From “${match.memory.title}”:\n${match.memory.content}').join('\n\n');
  }
  void _sendMessage([String? preset]) { final text = (preset ?? _input.text).trim(); if (text.isEmpty) return; setState(() { _messages.add(ChatMessage(text, fromUser: true)); _messages.add(ChatMessage(_answer(text))); _input.clear(); }); }
  Future<void> _addMemory() async {
    if (_title.text.trim().isEmpty || _content.text.trim().isEmpty) return;
    setState(() { _memories.add(MemoryCard(title: _title.text.trim(), content: _content.text.trim())); _title.clear(); _content.clear(); });
    await _saveMemories();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Memory saved locally.')));
  }
  String _backupJson() => const JsonEncoder.withIndent('  ').convert(_memories.map((memory) => memory.toJson()).toList());
  Future<void> _restoreBackup() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('Restore a JSON backup'), content: TextField(controller: controller, maxLines: 8, decoration: const InputDecoration(hintText: 'Paste a LocalMind JSON backup here', border: OutlineInputBorder())), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Restore'))]));
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    try { final decoded = (jsonDecode(value) as List).map((item) => MemoryCard.fromJson(item as Map<String, dynamic>)).toList(); setState(() => _memories = decoded); await _saveMemories(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup restored locally.'))); } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That backup format could not be read.'))); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return LayoutBuilder(builder: (context, constraints) { final wide = constraints.maxWidth >= 820; return Scaffold(body: SafeArea(child: Row(children: [if (wide) _sideNav(), Expanded(child: Column(children: [if (!wide) _mobileHeader(), Expanded(child: _page == 0 ? _chatPage() : _page == 1 ? _knowledgePage() : _backupPage())]))])), bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: _page, onDestinationSelected: (index) => setState(() => _page = index), destinations: const [NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'), NavigationDestination(icon: Icon(Icons.auto_awesome_mosaic_outlined), selectedIcon: Icon(Icons.auto_awesome_mosaic), label: 'Knowledge'), NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'Backup')])); });
  }
  Widget _sideNav() => Container(width: 244, padding: const EdgeInsets.fromLTRB(22, 26, 18, 24), decoration: const BoxDecoration(color: Colors.white, border: Border(right: BorderSide(color: Color(0xFFE9EAF0)))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Row(children: [_Logo(), SizedBox(width: 11), Text('LocalMind', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: Color(0xFF172033)))]), const SizedBox(height: 42), _navItem(Icons.chat_bubble_outline, 'Chat', 0), _navItem(Icons.auto_awesome_mosaic_outlined, 'Knowledge', 1), _navItem(Icons.shield_outlined, 'Backup & privacy', 2), const Spacer(), Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFF2F1FF), borderRadius: BorderRadius.circular(16)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.lock_outline, size: 18, color: Color(0xFF6657F5)), SizedBox(height: 10), Text('Private by design', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF172033))), SizedBox(height: 4), Text('No APIs. No tracking. Your data stays here.', style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF65627D)))]))]));
  Widget _navItem(IconData icon, String label, int index) => Padding(padding: const EdgeInsets.only(bottom: 7), child: ListTile(selected: _page == index, selectedTileColor: const Color(0xFFF0EFFF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), leading: Icon(icon, size: 20), title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)), onTap: () => setState(() => _page = index)));
  Widget _mobileHeader() => Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 10), child: Row(children: [const Icon(Icons.auto_awesome, color: Color(0xFF6657F5)), const SizedBox(width: 8), const Text('LocalMind', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)), const Spacer(), const Chip(avatar: Icon(Icons.lock, size: 14), label: Text('Offline', style: TextStyle(fontSize: 12)))]));
  Widget _pageHeading(String title, String subtitle, IconData icon) => Padding(padding: const EdgeInsets.fromLTRB(24, 27, 24, 12), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Flexible(child: Text(title, style: Theme.of(context).textTheme.headlineMedium)), const SizedBox(width: 10), Icon(icon, color: const Color(0xFFE7A04D), size: 23)]), const SizedBox(height: 5), Text(subtitle)]))]));
  Widget _chatPage() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_pageHeading('Good to see you.', 'A calm, private space for your thoughts.', Icons.wb_sunny_outlined), Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), itemCount: _messages.length, itemBuilder: (context, index) => _messageBubble(_messages[index]))), _composer()]);
  Widget _messageBubble(ChatMessage message) => Align(alignment: message.fromUser ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), constraints: const BoxConstraints(maxWidth: 670), decoration: BoxDecoration(color: message.fromUser ? const Color(0xFF6657F5) : Colors.white, borderRadius: BorderRadius.circular(17).copyWith(bottomRight: message.fromUser ? const Radius.circular(4) : null, bottomLeft: message.fromUser ? null : const Radius.circular(4)), boxShadow: message.fromUser ? null : [const BoxShadow(color: Color(0x0D172033), blurRadius: 14, offset: Offset(0, 4))]), child: Text(message.text, style: TextStyle(color: message.fromUser ? Colors.white : const Color(0xFF303748), height: 1.45))));
  Widget _composer() => Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), child: Column(children: [Wrap(spacing: 8, runSpacing: 8, children: ['What can you remember?', 'How do you work?'].map((prompt) => ActionChip(label: Text(prompt), onPressed: () => _sendMessage(prompt))).toList()), const SizedBox(height: 10), TextField(controller: _input, onSubmitted: (_) => _sendMessage(), minLines: 1, maxLines: 4, decoration: InputDecoration(hintText: 'Ask your local assistant...', prefixIcon: const Icon(Icons.edit_outlined), suffixIcon: IconButton(onPressed: _sendMessage, icon: const Icon(Icons.arrow_upward_rounded, color: Color(0xFF6657F5))), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), contentPadding: const EdgeInsets.all(16)))]));

  Widget _knowledgePage() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_pageHeading('Your knowledge', 'Teach LocalMind what matters to you.', Icons.auto_awesome), Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(24, 6, 24, 20), children: [_addMemoryCard(), const SizedBox(height: 24), Row(children: [Text('${_memories.length} memories', style: Theme.of(context).textTheme.titleLarge), const Spacer(), const Icon(Icons.storage_outlined, size: 18, color: Color(0xFF8A91A1)), const SizedBox(width: 5), const Text('stored locally')]), const SizedBox(height: 12), ..._memories.map(_memoryTile)]))]);
  Widget _addMemoryCard() => Card(elevation: 0, color: const Color(0xFFEDEBFF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Add a new memory', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF302A63))), const SizedBox(height: 12), TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. My project goals', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderSide: BorderSide.none))), const SizedBox(height: 9), TextField(controller: _content, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'What should I remember?', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderSide: BorderSide.none))), const SizedBox(height: 12), Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _addMemory, icon: const Icon(Icons.add, size: 18), label: const Text('Save memory')))])));
  Widget _memoryTile(MemoryCard memory) => Card(elevation: 0, margin: const EdgeInsets.only(bottom: 9), color: Colors.white, child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5), leading: CircleAvatar(backgroundColor: memory.isBuiltIn ? const Color(0xFFE8E5FF) : const Color(0xFFE4F5EE), child: Icon(memory.isBuiltIn ? Icons.auto_awesome : Icons.bookmark_outline, size: 19, color: memory.isBuiltIn ? const Color(0xFF6657F5) : const Color(0xFF2D9A68))), title: Text(memory.title, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF202637))), subtitle: Text(memory.content, maxLines: 2, overflow: TextOverflow.ellipsis), trailing: memory.isBuiltIn ? const Chip(label: Text('Built in', style: TextStyle(fontSize: 11))) : null));
  Widget _backupPage() => ListView(padding: const EdgeInsets.fromLTRB(24, 27, 24, 30), children: [Text('Backup & privacy', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 5), const Text('Your assistant is local by default. Manage your data with confidence.'), const SizedBox(height: 24), _privacyCard(), const SizedBox(height: 14), Card(elevation: 0, color: Colors.white, child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Local backup', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF172033))), const SizedBox(height: 6), const Text('Create a portable JSON snapshot or restore one you already have.'), const SizedBox(height: 17), Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _showBackup, icon: const Icon(Icons.copy_outlined), label: const Text('View backup'))), const SizedBox(width: 10), Expanded(child: FilledButton.icon(onPressed: _restoreBackup, icon: const Icon(Icons.restore), label: const Text('Restore')))])]))), const SizedBox(height: 14), _statTile(Icons.auto_awesome_mosaic_outlined, 'Knowledge stored', '${_memories.length} memories'), _statTile(Icons.forum_outlined, 'This session', '${_messages.where((message) => message.fromUser).length} questions')]);
  Widget _privacyCard() => Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF172033), borderRadius: BorderRadius.circular(18)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.verified_user_outlined, color: Color(0xFFB7ADFF), size: 28), SizedBox(width: 15), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Everything stays on this device', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)), SizedBox(height: 6), Text('No network calls, third-party AI, analytics, or account required. LocalMind is a small retrieval assistant trained only by the knowledge you provide.', style: TextStyle(color: Color(0xFFB9C0D0), height: 1.45))]))]));
  Widget _statTile(IconData icon, String label, String value) => Card(elevation: 0, color: Colors.white, child: ListTile(leading: Icon(icon, color: const Color(0xFF6657F5)), title: Text(label), trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF172033)))));
  void _showBackup() => showDialog(context: context, builder: (context) => AlertDialog(title: const Text('Your local backup'), content: SizedBox(width: 500, child: SelectableText(_backupJson(), maxLines: 14)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))]));
}

class _Logo extends StatelessWidget { const _Logo(); @override Widget build(BuildContext context) => Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFF6657F5), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.auto_awesome, color: Colors.white, size: 21)); }
class MyApp extends LocalMindApp { const MyApp({super.key}); }
