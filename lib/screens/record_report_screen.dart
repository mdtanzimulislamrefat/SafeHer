import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../data/incident_report.dart';
import '../services/gemini_client.dart';
import '../services/protection_service.dart';
import '../services/report_drafter.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/voice_note_player.dart';
import 'report_edit_screen.dart';

/// Speak (or type) what happened; Gemini drafts the report, she checks it.
class RecordReportScreen extends StatefulWidget {
  const RecordReportScreen({super.key, this.startTyping = false});

  final bool startTyping;

  @override
  State<RecordReportScreen> createState() => _RecordReportScreenState();
}

enum _Stage { ready, recording, recorded, typing, drafting }

class _RecordReportScreenState extends State<RecordReportScreen> {
  static const maxLength = Duration(minutes: 3);

  final _recorder = AudioRecorder();
  final _typed = TextEditingController();
  final _id = DateTime.now().microsecondsSinceEpoch.toString();
  // Looked up in initState: dispose() runs after the context is gone, so a lazy lookup there crashes.
  late final ProtectionService _protection;
  late _Stage _stage = widget.startTyping ? _Stage.typing : _Stage.ready;

  @override
  void initState() {
    super.initState();
    _protection = context.read<ProtectionService>();
  }
  ReportLanguage _language = ReportLanguage.english;
  String? _path;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  Timer? _timer;
  StreamSubscription<Amplitude>? _amp;

  @override
  void dispose() {
    _timer?.cancel();
    _amp?.cancel();
    _recorder.dispose();
    _typed.dispose();
    _protection.micHeld = false;
    // A voice note that was never turned into a report is not kept.
    if (_path != null && _stage != _Stage.drafting) {
      File(_path!).delete().ignore();
    }
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!(await Permission.microphone.request()).isGranted) {
      _snack('SafeHer needs the microphone to record a voice note.');
      return;
    }
    _protection.micHeld = true;
    await _protection.scream.stop();
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/reports');
    await dir.create(recursive: true);
    final path = '${dir.path}/$_id.wav';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
    _amp = _recorder.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((a) {
      setState(() => _level = ((a.current + 50) / 50).clamp(0, 1));
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= maxLength) _stopRecording();
    });
    setState(() {
      _path = path;
      _elapsed = Duration.zero;
      _stage = _Stage.recording;
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    await _amp?.cancel();
    await _recorder.stop();
    _protection.micHeld = false;
    setState(() => _stage = _Stage.recorded);
  }

  Future<void> _recordAgain() async {
    if (_path != null) File(_path!).delete().ignore();
    setState(() {
      _path = null;
      _stage = _Stage.ready;
    });
  }

  Future<void> _draft() async {
    final typed = _typed.text.trim();
    final fromVoice = _stage == _Stage.recorded;
    if (!fromVoice && typed.isEmpty) {
      _snack('Write a few words about what happened first.');
      return;
    }
    setState(() => _stage = _Stage.drafting);
    final drafter = ReportDrafter();
    ReportFields? fields;
    String? problem;
    try {
      fields = fromVoice
          ? await drafter.fromVoice(await File(_path!).readAsBytes(), language: _language)
          : await drafter.fromText(typed, language: _language);
    } on GeminiException catch (e) {
      problem = switch (e.failure) {
        GeminiFailure.noKey => 'AI drafting is not set up in this build.',
        GeminiFailure.busy => 'Gemini is busy right now.',
        GeminiFailure.network => "Couldn't reach Gemini. Check your internet.",
        GeminiFailure.badAnswer => 'Gemini gave an answer SafeHer could not read.',
      };
    }
    if (!mounted) return;
    // Without AI she can still write it herself; her voice note or text is kept either way.
    fields ??= ReportFields(transcript: fromVoice ? '' : typed);
    final report = IncidentReport(
      id: _id,
      createdAt: DateTime.now(),
      fields: fields,
      language: _language,
      audioPath: fromVoice ? _path : null,
      aiDrafted: problem == null,
    );
    if (problem != null) _snack('$problem You can fill in the report yourself.');
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => ReportEditScreen(report: report, isNew: true)),
    );
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('What happened?', style: SafeText.heading(30)),
          const SizedBox(height: 6),
          const Text(
            'Say it in your own words, in Bangla or English. Take your time. '
            'SafeHer will write it up as a report you can check and change.',
            style: SafeText.small,
          ),
          const SizedBox(height: 24),
          ..._body(),
        ],
      ),
    );
  }

  List<Widget> _body() {
    switch (_stage) {
      case _Stage.ready:
        return [
          Center(child: _RecordButton(recording: false, level: 0, onTap: _startRecording)),
          const SizedBox(height: 12),
          const Center(child: Text('Tap to start recording · up to 3 minutes', style: SafeText.small)),
          const SizedBox(height: 28),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _stage = _Stage.typing),
              child: const Text('Type it instead'),
            ),
          ),
        ];
      case _Stage.recording:
        return [
          Center(
            child: _RecordButton(recording: true, level: _level, onTap: _stopRecording),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Recording · ${_elapsed.inMinutes}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')} · tap to stop',
              style: SafeText.bodyStrong,
            ),
          ),
        ];
      case _Stage.recorded:
        return [
          VoiceNotePlayer(path: _path!),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _recordAgain,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Record again'),
            ),
          ),
          ..._draftControls(),
        ];
      case _Stage.typing:
        return [
          TextField(
            controller: _typed,
            minLines: 6,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'What happened, when, where, who was there…'),
          ),
          const SizedBox(height: 8),
          ..._draftControls(),
        ];
      case _Stage.drafting:
        return const [
          SizedBox(height: 40),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 16),
          Center(child: Text('Writing your report…', style: SafeText.bodyStrong)),
          SizedBox(height: 4),
          Center(child: Text('Usually 5–10 seconds', style: SafeText.small)),
        ];
    }
  }

  List<Widget> _draftControls() {
    return [
      const SizedBox(height: 12),
      const Text('Write the report in', style: SafeText.bodyStrong),
      const SizedBox(height: 8),
      SegmentedButton<ReportLanguage>(
        segments: const [
          ButtonSegment(value: ReportLanguage.english, label: Text('English')),
          ButtonSegment(value: ReportLanguage.bangla, label: Text('বাংলা')),
        ],
        selected: {_language},
        onSelectionChanged: (s) => setState(() => _language = s.first),
      ),
      const SizedBox(height: 16),
      const NoteBox(
        icon: Icons.lock,
        text:
            'To write the draft, your note is sent to Google Gemini. On the free plan Google may use it '
            'to improve its products. The report and voice note are saved only on this phone.',
      ),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _draft, icon: const Icon(Icons.edit_note), label: const Text('Write my report')),
    ];
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.recording, required this.level, required this.onTap});

  final bool recording;
  final double level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: recording ? 'Stop recording' : 'Start recording',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 132 + 24 * level,
          height: 132 + 24 * level,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: recording ? SafeColors.redSoft : SafeColors.plumSoft,
          ),
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(shape: BoxShape.circle, color: recording ? SafeColors.red : SafeColors.plum),
            child: Icon(recording ? Icons.stop : Icons.mic, color: Colors.white, size: 40),
          ),
        ),
      ),
    );
  }
}
