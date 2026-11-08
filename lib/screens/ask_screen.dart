import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/help_guide.dart';
import '../services/gemini_client.dart';
import '../services/guide_answerer.dart';
import '../services/sos_controller.dart';
import '../theme.dart';
import 'helplines_screen.dart';
import 'home_screen.dart';

/// Questions answered only from SafeHer's checked guide, with numbered sources.
class AskScreen extends StatefulWidget {
  const AskScreen({super.key});

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  static const suggestions = [
    'রাস্তায় কেউ পিছু নিলে আমি কী করব?',
    'How do I file a GD at the thana?',
    'Someone is blackmailing me with my photos online',
    'Where can I get free legal help?',
  ];

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <ChatTurn>[];
  GuideAnswerer? _answerer;
  bool _thinking = false;
  String? _error;
  String? _lastQuestion;

  @override
  void initState() {
    super.initState();
    HelpGuide.load().then((g) {
      if (mounted) setState(() => _answerer = GuideAnswerer(g));
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    final q = question.trim();
    final answerer = _answerer;
    if (q.isEmpty || answerer == null || _thinking) return;
    final history = List<ChatTurn>.of(_turns);
    setState(() {
      if (_error == null || _lastQuestion != q) _turns.add(ChatTurn(fromUser: true, text: q));
      _thinking = true;
      _error = null;
      _lastQuestion = q;
      _input.clear();
    });
    _scrollToEnd();
    try {
      final a = await answerer.ask(q, history: history);
      if (!mounted) return;
      setState(() => _turns.add(ChatTurn(fromUser: false, text: a.text, answer: a)));
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = switch (e.failure) {
          GeminiFailure.noKey => 'Ask SafeHer is not set up in this build.',
          GeminiFailure.busy => 'Too many questions right now. Try again in a minute.',
          GeminiFailure.network => "Couldn't connect. Check your internet.",
          GeminiFailure.badAnswer => 'Something went wrong with the answer.',
        },
      );
    } finally {
      if (mounted) setState(() => _thinking = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(titleSpacing: 20, title: Text('Ask SafeHer', style: SafeText.heading(20))),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              children: [
                if (_turns.isEmpty) ...[
                  const Text(
                    'Ask what to do or who can help, in Bangla or English. Answers come only from '
                    "SafeHer's checked guide, with sources.",
                    style: SafeText.small,
                  ),
                  const SizedBox(height: 12),
                  for (final s in suggestions) _SuggestionRow(text: s, onTap: () => _ask(s)),
                ],
                for (final t in _turns) t.fromUser ? _Question(t.text) : _Answer(t.answer!),
                if (_thinking) const _Thinking(),
                if (_error != null) _ErrorRow(text: _error!, onRetry: () => _ask(_lastQuestion!)),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _ask,
                      decoration: const InputDecoration(
                        hintText: 'প্রশ্ন লিখুন… / Type a question',
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    style: IconButton.styleFrom(
                      backgroundColor: SafeColors.plum,
                      minimumSize: const Size(50, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _answerer == null || _thinking ? null : () => _ask(_input.text),
                    icon: const Icon(Icons.send, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: const BoxDecoration(
          color: SafeColors.plum,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: Text(text, style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.white)),
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer(this.a);

  final GuideAnswer a;

  @override
  Widget build(BuildContext context) {
    final numbers = {for (final e in a.cited) ...e.numbers};
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (a.urgent) const _UrgentCard(),
          SelectableText(a.text, style: const TextStyle(fontSize: 15, height: 1.6, color: SafeColors.ink)),
          if (numbers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final n in numbers)
                  ActionChip(
                    avatar: const Icon(Icons.phone, size: 16, color: SafeColors.plum),
                    label: Text(n),
                    onPressed: () => callNumber(n),
                  ),
              ],
            ),
          ],
          if (a.cited.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 6),
            for (final (i, e) in a.cited.indexed) _SourceLine(index: i + 1, entry: e),
          ],
          const SizedBox(height: 6),
          Text(
            a.covered
                ? "Answered from SafeHer's checked guide · not legal advice"
                : "Not in SafeHer's checked guide, so no details were guessed",
            style: SafeText.caption,
          ),
        ],
      ),
    );
  }
}

class _SourceLine extends StatelessWidget {
  const _SourceLine({required this.index, required this.entry});

  final int index;
  final GuideEntry entry;

  @override
  Widget build(BuildContext context) {
    final hasLink = entry.url.isNotEmpty;
    return InkWell(
      onTap: hasLink ? () => launchUrl(Uri.parse(entry.url), mode: LaunchMode.externalApplication) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '[$index] ',
                style: const TextStyle(fontWeight: FontWeight.w700, color: SafeColors.plum),
              ),
              TextSpan(text: entry.source),
              if (entry.verify)
                const TextSpan(
                  text: ' · number not yet confirmed officially',
                  style: TextStyle(color: SafeColors.amber, fontWeight: FontWeight.w600),
                ),
              if (hasLink)
                const TextSpan(
                  text: ' ↗',
                  style: TextStyle(color: SafeColors.plum),
                ),
            ],
          ),
          style: SafeText.caption,
        ),
      ),
    );
  }
}

class _UrgentCard extends StatelessWidget {
  const _UrgentCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: SafeColors.redSoft, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'If you are in danger now',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: SafeColors.redDeep),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: SafeColors.red, minimumSize: const Size(0, 48)),
                  onPressed: () => callNumber('999'),
                  icon: const Icon(Icons.phone, size: 18),
                  label: const Text('Call 999'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: SafeColors.redDeep),
                  onPressed: () => startSos(context, SosTrigger.hold),
                  child: const Text('Alert my circle'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: SafeColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 14, color: SafeColors.ink)),
            ),
            const Icon(Icons.chevron_right, color: SafeColors.faint, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Checking the guide…', style: SafeText.small),
        ],
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, color: SafeColors.red)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
