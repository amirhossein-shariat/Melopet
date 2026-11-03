import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../theme.dart';
import '../utils/format.dart';
import 'form_bits.dart';
import 'glass.dart';

/// A recorded or uploaded voice note kept in memory until upload.
class VoiceClip {
  final PickedBytes file;
  final int seconds;
  final String? localPath; // for instant preview playback
  VoiceClip(this.file, this.seconds, {this.localPath});
}

String mmss(int s) => faNum('${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}');

/// Records a voice note in-app (or picks an audio file) with preview playback.
class VoiceRecorderField extends StatefulWidget {
  final VoiceClip? value;
  final ValueChanged<VoiceClip?> onChanged;
  final int maxSeconds;
  const VoiceRecorderField({super.key, required this.value, required this.onChanged, this.maxSeconds = 300});

  @override
  State<VoiceRecorderField> createState() => _VoiceRecorderFieldState();
}

class _VoiceRecorderFieldState extends State<VoiceRecorderField> {
  final _rec = AudioRecorder();
  Timer? _timer;
  int _elapsed = 0;
  bool _recording = false;

  @override
  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (kIsWeb) return _upload();
    if (!await _rec.hasPermission()) {
      if (mounted) toast(context, 'برای ضبط صدا، دسترسی میکروفون را بدهید', error: true);
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/history_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1), path: path);
    setState(() {
      _recording = true;
      _elapsed = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed++);
      if (_elapsed >= widget.maxSeconds) _stop();
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    final path = await _rec.stop();
    setState(() => _recording = false);
    if (path == null || _elapsed < 1) return;
    final bytes = await XFile(path).readAsBytes();
    widget.onChanged(VoiceClip(PickedBytes('history.m4a', bytes), _elapsed, localPath: path));
  }

  Future<void> _upload() async {
    final files = await FilePicker.pickFiles(type: FileType.audio);
    if (files.isEmpty) return;
    final f = files.first;
    final bytes = await f.readAsBytes();
    if (bytes.length > 20 * 1024 * 1024) {
      if (mounted) toast(context, 'حداکثر حجم فایل صوتی ۲۰ مگابایت است', error: true);
      return;
    }
    widget.onChanged(VoiceClip(PickedBytes(f.name, bytes), 0));
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final cs = Theme.of(context).colorScheme;
    if (_recording) {
      return Glass(
        tint: MP.danger.withValues(alpha: .10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const _Pulse(),
            const SizedBox(width: 10),
            Expanded(
              child: Text('در حال ضبط... ${mmss(_elapsed)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: MP.danger, minimumSize: const Size(0, 42)),
              onPressed: _stop,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('پایان'),
            ),
          ],
        ),
      );
    }
    if (v != null) {
      return Glass(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: VoicePlayer(
                source: v.localPath != null ? DeviceFileSource(v.localPath!) : BytesSource(v.file.bytes),
                seconds: v.seconds,
              ),
            ),
            IconButton(
              tooltip: 'حذف و ضبط دوباره',
              onPressed: () => widget.onChanged(null),
              icon: const Icon(Icons.delete_outline_rounded, color: MP.danger),
            ),
          ],
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: Glass(
            onTap: _start,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                GlassIcon(Icons.mic_rounded, color: cs.primary, size: 46),
                const SizedBox(height: 6),
                Text(kIsWeb ? 'آپلود ویس' : 'ضبط ویس', style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Glass(
            onTap: _upload,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: const Column(
              children: [
                GlassIcon(Icons.audio_file_rounded, color: MP.lavenderDeep, size: 46),
                SizedBox(height: 6),
                Text('آپلود فایل صوتی', style: TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse();
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: .3, end: 1.0).animate(_c),
    child: const Icon(Icons.fiber_manual_record_rounded, color: MP.danger),
  );
}

/// Compact play/pause + progress for a voice note (URL, file or bytes).
class VoicePlayer extends StatefulWidget {
  final Source source;
  final int seconds;
  final Color? color;
  const VoicePlayer({super.key, required this.source, this.seconds = 0, this.color});

  factory VoicePlayer.url(String url, {int seconds = 0, Color? color}) =>
      VoicePlayer(source: UrlSource(url), seconds: seconds, color: color);

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  final _p = AudioPlayer();
  Duration _pos = Duration.zero;
  Duration? _dur;
  bool _playing = false;
  bool _loading = false;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _subs.add(_p.onPositionChanged.listen((d) => setState(() => _pos = d)));
    _subs.add(_p.onDurationChanged.listen((d) => setState(() => _dur = d)));
    _subs.add(_p.onPlayerStateChanged.listen((s) => setState(() => _playing = s == PlayerState.playing)));
    _subs.add(_p.onPlayerComplete.listen((_) => setState(() => _pos = Duration.zero)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _p.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _p.pause();
      } else if (_pos > Duration.zero) {
        await _p.resume();
      } else {
        setState(() => _loading = true);
        await _p.play(widget.source);
      }
    } catch (e) {
      if (mounted) toast(context, 'پخش فایل صوتی ممکن نشد', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final total = _dur ?? Duration(seconds: widget.seconds);
    final progress = total.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Row(
      children: [
        InkWell(
          customBorder: const CircleBorder(),
          onTap: _toggle,
          child: Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: MP.brandGradient),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2, color: MP.plum),
                  )
                : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: MP.plum),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: progress,
                    activeColor: color,
                    onChanged: total.inMilliseconds == 0
                        ? null
                        : (v) => _p.seek(Duration(milliseconds: (v * total.inMilliseconds).round())),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _pos > Duration.zero ? mmss(_pos.inSeconds) : (total.inSeconds > 0 ? mmss(total.inSeconds) : 'ویس'),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
