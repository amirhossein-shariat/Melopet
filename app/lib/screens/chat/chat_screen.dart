import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/form_bits.dart';
import '../../widgets/glass.dart';
import '../../widgets/logo.dart';
import '../../widgets/voice.dart';

/// Telegram-like chat between a clinic and the lab.
/// Messages are permanent: the backend rejects edits and deletes.
class ChatScreen extends StatefulWidget {
  /// Admin: which clinic to talk to. Clinic: null (own conversation).
  final String? clinicId;
  final String? draft;
  final double bottomInset;
  const ChatScreen({super.key, this.clinicId, this.draft, this.bottomInset = 0});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  RecordModel? _conv;
  RecordModel? _peer; // clinic (for admins)
  final List<RecordModel> _msgs = []; // newest first
  final _input = TextEditingController();
  final _scroll = ScrollController();
  UnsubscribeFunc? _unsubMsgs;
  UnsubscribeFunc? _unsubConv;
  RecordModel? _replyTo;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasOlder = true;
  bool _sending = false;
  String? _error;
  double? _uploadProgress;

  bool get _admin => Api.isAdmin;

  @override
  void initState() {
    super.initState();
    if (widget.draft != null) _input.text = widget.draft!;
    _input.addListener(() => setState(() {}));
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _loadOlder();
    });
    _init();
  }

  @override
  void dispose() {
    _unsubMsgs?.call();
    _unsubConv?.call();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conv = RecordModel.fromJson(
        Map<String, dynamic>.from(
          await Api.pb.send('/api/melopet/chat/conversation', query: {if (_admin) 'clinic': widget.clinicId}) as Map,
        ),
      );
      _conv = conv;
      if (_admin) _peer = await Api.pb.collection('users').getOne(widget.clinicId!);
      final page = await Api.pb
          .collection('messages')
          .getList(perPage: 40, sort: '-created', filter: 'conversation = "${conv.id}"', expand: 'reply_to');
      _msgs
        ..clear()
        ..addAll(page.items);
      _hasOlder = page.totalPages > 1;
      _unsubMsgs = await Api.pb.collection('messages').subscribe('*', (e) {
        final r = e.record;
        if (r == null || r.getStringValue('conversation') != conv.id || e.action != 'create') return;
        if (_msgs.any((m) => m.id == r.id)) return;
        _attachReply(r);
        setState(() => _msgs.insert(0, r));
        _markRead();
      }, filter: 'conversation = "${conv.id}"');
      _unsubConv = await Api.pb.collection('conversations').subscribe(conv.id, (e) {
        if (e.record != null && mounted) setState(() => _conv = e.record);
      });
      setState(() => _loading = false);
      _markRead();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = Api.error(e);
        });
      }
    }
  }

  /// Realtime events don't carry expand — resolve replied message locally.
  void _attachReply(RecordModel r) {
    final rid = r.getStringValue('reply_to');
    if (rid.isEmpty) return;
    final target = _msgs.where((m) => m.id == rid).firstOrNull;
    if (target != null) {
      r.data['expand'] = {'reply_to': target.toJson()};
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder || _msgs.isEmpty || _conv == null) return;
    _loadingOlder = true;
    try {
      final oldest = _msgs.last.getStringValue('created');
      final page = await Api.pb
          .collection('messages')
          .getList(perPage: 40, sort: '-created', filter: 'conversation = "${_conv!.id}" && created < "$oldest"', expand: 'reply_to');
      _hasOlder = page.totalPages > 1;
      if (mounted) setState(() => _msgs.addAll(page.items));
    } catch (_) {
    } finally {
      _loadingOlder = false;
    }
  }

  Future<void> _markRead() async {
    if (_conv == null) return;
    try {
      await Api.pb.send('/api/melopet/chat/${_conv!.id}/read', method: 'POST');
      if (mounted) context.read<AppState>().refreshCounters();
    } catch (_) {}
  }

  Future<void> _send({PickedBytes? file, String? kind}) async {
    final text = _input.text.trim();
    if (_conv == null || (text.isEmpty && file == null)) return;
    setState(() {
      _sending = true;
      if (file != null) _uploadProgress = 0.3;
    });
    try {
      final r = await Api.pb
          .collection('messages')
          .create(
            body: {
              'conversation': _conv!.id,
              'sender': Api.myId,
              'text': text,
              'kind': kind ?? (file == null ? 'text' : 'file'),
              if (file != null) 'file_name': file.name,
              if (file != null) 'file_size': file.bytes.length,
              if (_replyTo != null) 'reply_to': _replyTo!.id,
            },
            files: file != null ? [file.toMultipart('file')] : [],
            expand: 'reply_to',
          );
      _input.clear();
      setState(() {
        _replyTo = null;
        if (!_msgs.any((m) => m.id == r.id)) _msgs.insert(0, r);
      });
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadProgress = null;
        });
      }
    }
  }

  /// Voice message: record (or pick an audio file), preview, then send.
  Future<void> _recordVoice() async {
    VoiceClip? clip;
    final send = await showGlassSheet<bool>(
      context,
      (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('پیام صوتی', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 12),
              VoiceRecorderField(value: clip, onChanged: (v) => setSheet(() => clip = v)),
              const SizedBox(height: 12),
              GradientButton(label: 'ارسال', icon: Icons.send_rounded, onPressed: clip == null ? null : () => Navigator.pop(c, true)),
            ],
          ),
        ),
      ),
    );
    if (send == true && clip != null) await _send(file: clip!.file, kind: 'voice');
  }

  Future<void> _attach() async {
    final choice = await showGlassSheet<String>(
      context,
      (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (!kIsWeb) _AttachOption(Icons.photo_camera_rounded, 'دوربین', MP.pinkDeep, () => Navigator.pop(c, 'camera')),
            _AttachOption(Icons.photo_library_rounded, 'گالری', MP.lavenderDeep, () => Navigator.pop(c, 'gallery')),
            _AttachOption(Icons.insert_drive_file_rounded, 'فایل', MP.mintDeep, () => Navigator.pop(c, 'file')),
          ],
        ),
      ),
    );
    if (choice == null) return;
    PickedBytes? f;
    String kind = 'file';
    if (choice == 'file') {
      f = await pickOne();
      if (f != null && f.isImage) kind = 'image';
    } else {
      final x = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 2200,
      );
      if (x != null) {
        f = PickedBytes(x.name, await x.readAsBytes());
        kind = 'image';
      }
    }
    if (f == null) return;
    if (f.bytes.length > 25 * 1024 * 1024) {
      if (mounted) toast(context, 'حداکثر حجم فایل ۲۵ مگابایت است', error: true);
      return;
    }
    await _send(file: f, kind: kind);
  }

  bool _isMine(RecordModel m) =>
      m.getStringValue('sender') == Api.myId || (_admin && m.getStringValue('sender') != _conv?.getStringValue('clinic'));

  bool _isRead(RecordModel m) {
    final readAt = parseDate(_conv?.getStringValue(_admin ? 'clinic_read_at' : 'admin_read_at'));
    final created = parseDate(m.getStringValue('created'));
    return readAt != null && created != null && !created.isAfter(readAt);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final peerName = _admin ? (_peer?.getStringValue('clinic_name') ?? '...') : 'آزمایشگاه ملوپت';
    final peerSub = _admin
        ? 'دکتر ${_peer?.getStringValue('doctor_name') ?? ''}'
        : (context.watch<AppState>().settings?.getStringValue('working_hours') ?? 'پشتیبانی همکاران');

    return Stack(
      children: [
        Positioned.fill(child: _ChatBackground()),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            titleSpacing: 0,
            centerTitle: false,
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: .6)),
              ),
            ),
            title: Row(
              children: [
                if (_admin && _peer != null && _peer!.getStringValue('logo').isNotEmpty)
                  CircleAvatar(backgroundImage: NetworkImage(Api.fileUrl(_peer!, 'logo', thumb: '200x200').toString()))
                else if (_admin)
                  CircleAvatar(backgroundColor: MP.lavender, child: Text(peerName.isNotEmpty ? peerName.characters.first : '?'))
                else
                  const MelopetLogo(size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(peerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      Text(peerSub, style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: .6))),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (_admin && _peer != null)
                IconButton(
                  icon: const Icon(Icons.call_rounded),
                  onPressed: () => launchUrl(Uri.parse('tel:${_peer!.getStringValue('mobile')}')),
                ),
            ],
          ),
          body: _loading
              ? const Loading()
              : _error != null
              ? ErrorView(_error!, onRetry: _init)
              : Column(
                  children: [
                    if (_uploadProgress != null) const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child: _msgs.isEmpty
                          ? const EmptyState(
                              icon: Icons.forum_rounded,
                              title: 'گفتگو را شروع کنید',
                              subtitle: 'پیام، عکس و فایل بفرستید. تاریخچه پیام‌ها همیشه محفوظ می‌ماند.',
                            )
                          : ListView.builder(
                              controller: _scroll,
                              reverse: true,
                              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                              itemCount: _msgs.length,
                              itemBuilder: (_, i) {
                                final m = _msgs[i];
                                final d = parseDate(m.getStringValue('created'));
                                final older = i + 1 < _msgs.length ? parseDate(_msgs[i + 1].getStringValue('created')) : null;
                                final newDay =
                                    d != null && (older == null || older.day != d.day || older.month != d.month || older.year != d.year);
                                final mine = _isMine(m);
                                final nextSame = i > 0 && _isMine(_msgs[i - 1]) == mine;
                                return Column(
                                  children: [
                                    if (newDay) _DayChip(relativeDay(d)),
                                    _SwipeToReply(
                                      onReply: () => setState(() => _replyTo = m),
                                      child: _Bubble(
                                        msg: m,
                                        mine: mine,
                                        read: mine && _isRead(m),
                                        tail: !nextSame,
                                        onLongPress: () => _menu(m),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                    _composer(cs),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _menu(RecordModel m) async {
    HapticFeedback.selectionClick();
    await showGlassSheet(
      context,
      (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.reply_rounded),
            title: const Text('پاسخ'),
            onTap: () {
              Navigator.pop(c);
              setState(() => _replyTo = m);
            },
          ),
          if (m.getStringValue('text').isNotEmpty)
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('کپی متن'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: m.getStringValue('text')));
                Navigator.pop(c);
                toast(context, 'کپی شد');
              },
            ),
          if (m.getStringValue('file').isNotEmpty)
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('دانلود / باز کردن فایل'),
              onTap: () {
                Navigator.pop(c);
                launchUrl(Api.fileUrl(m, 'file'), mode: LaunchMode.externalApplication);
              },
            ),
          ListTile(
            leading: const Icon(Icons.lock_rounded),
            title: const Text('پیام‌ها قابل حذف یا ویرایش نیستند'),
            subtitle: Text(jDateTime(parseDate(m.getStringValue('created')))),
            enabled: false,
          ),
        ],
      ),
    );
  }

  Widget _composer(ColorScheme cs) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: .7),
          padding: EdgeInsets.only(bottom: widget.bottomInset),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyTo != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                    decoration: BoxDecoration(
                      border: BorderDirectional(start: BorderSide(color: cs.primary, width: 3)),
                      color: cs.primary.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.reply_rounded, color: cs.primary, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _preview(_replyTo!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _replyTo = null),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: _sending ? null : _attach,
                        icon: Icon(Icons.attach_file_rounded, color: cs.primary),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 6,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: 'پیام...',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedScale(
                        scale: 1,
                        duration: const Duration(milliseconds: 150),
                        child: InkWell(
                          onTap: _sending ? null : (_input.text.trim().isEmpty ? _recordVoice : () => _send()),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: MP.brandGradient),
                            child: _sending
                                ? const Padding(
                                    padding: EdgeInsets.all(13),
                                    child: CircularProgressIndicator(strokeWidth: 2, color: MP.plum),
                                  )
                                : Icon(
                                    _input.text.trim().isEmpty ? Icons.mic_rounded : Icons.send_rounded,
                                    color: MP.plum,
                                    textDirection: TextDirection.rtl,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _preview(RecordModel m) {
  switch (m.getStringValue('kind')) {
    case 'image':
      return '🖼 تصویر ${m.getStringValue('text')}';
    case 'file':
      return '📎 ${m.getStringValue('file_name')}';
    case 'voice':
      return '🎤 پیام صوتی';
  }
  return m.getStringValue('text');
}

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AttachOption(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          GlassIcon(icon, color: color, size: 60),
          const SizedBox(height: 8),
          Text(label),
        ],
      ),
    ),
  );
}

class _DayChip extends StatelessWidget {
  final String label;
  const _DayChip(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Glass(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
    ),
  );
}

/// Swipe a bubble to reply (like Telegram).
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  const _SwipeToReply({required this.child, required this.onReply});
  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  double _dx = 0;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) => setState(() => _dx = (_dx + d.delta.dx).clamp(-70, 0)),
      onHorizontalDragEnd: (_) {
        if (_dx <= -55) {
          HapticFeedback.lightImpact();
          widget.onReply();
        }
        setState(() => _dx = 0);
      },
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          if (_dx < -10)
            Positioned(
              right: 8,
              child: Opacity(opacity: (-_dx / 55).clamp(0, 1), child: const Icon(Icons.reply_rounded)),
            ),
          AnimatedContainer(
            duration: Duration(milliseconds: _dx == 0 ? 200 : 0),
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final RecordModel msg;
  final bool mine;
  final bool read;
  final bool tail;
  final VoidCallback onLongPress;
  const _Bubble({required this.msg, required this.mine, required this.read, required this.tail, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final cs = Theme.of(context).colorScheme;
    final kind = msg.getStringValue('kind');
    final text = msg.getStringValue('text');
    final time = hm(parseDate(msg.getStringValue('created')));
    final reply = msg.get<RecordModel?>('expand.reply_to');

    final bg = mine
        ? (dark ? const Color(0xFF6A2D4E) : const Color(0xFFFAD3E1))
        : (dark ? Colors.white.withValues(alpha: .09) : Colors.white.withValues(alpha: .92));
    const r = Radius.circular(18);
    const s = Radius.circular(5);
    // own messages on the right, like Telegram
    final radius = BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: mine ? r : (tail ? s : r),
      bottomRight: mine ? (tail ? s : r) : r,
    );

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(time, style: TextStyle(fontSize: 10.5, color: cs.onSurface.withValues(alpha: .55))),
        if (mine) ...[
          const SizedBox(width: 3),
          Icon(
            read ? Icons.done_all_rounded : Icons.done_rounded,
            size: 15,
            color: read ? MP.mintDeep : cs.onSurface.withValues(alpha: .5),
          ),
        ],
      ],
    );

    Widget content;
    if (kind == 'voice' && msg.getStringValue('file').isNotEmpty) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 230, child: VoicePlayer.url(Api.fileUrl(msg, 'file').toString())),
          Padding(padding: const EdgeInsets.only(top: 2), child: meta),
        ],
      );
    } else if (kind == 'image' && msg.getStringValue('file').isNotEmpty) {
      final thumb = Api.fileUrl(msg, 'file', thumb: '400x0').toString();
      final full = Api.fileUrl(msg, 'file').toString();
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ImageViewer(full))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300, minWidth: 160),
                child: Hero(
                  tag: full,
                  child: Image.network(
                    thumb,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(height: 120, child: Icon(Icons.broken_image)),
                  ),
                ),
              ),
            ),
          ),
          if (text.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(6, 6, 6, 0), child: SelectableText(text)),
          Padding(padding: const EdgeInsets.fromLTRB(6, 4, 6, 0), child: meta),
        ],
      );
    } else if (msg.getStringValue('file').isNotEmpty) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => launchUrl(Api.fileUrl(msg, 'file'), mode: LaunchMode.externalApplication),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: MP.brandGradient),
                  child: const Icon(Icons.insert_drive_file_rounded, color: MP.plum),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg.getStringValue('file_name').isEmpty ? 'فایل' : msg.getStringValue('file_name'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(fileSize(msg.getIntValue('file_size')), style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(text)),
          Padding(padding: const EdgeInsets.only(top: 4), child: meta),
        ],
      );
    } else {
      content = Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 8,
        children: [
          SelectableText(text, style: const TextStyle(fontSize: 14.5, height: 1.5), onTap: null),
          Padding(padding: const EdgeInsets.only(top: 4), child: meta),
        ],
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.only(top: 2, bottom: tail ? 6 : 2, left: mine ? 48 : 0, right: mine ? 0 : 48),
          padding: EdgeInsets.all(kind == 'image' ? 4 : 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reply != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(8),
                    border: BorderDirectional(start: BorderSide(color: cs.primary, width: 3)),
                  ),
                  child: Text(_preview(reply), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ),
              content,
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final String url;
  const _ImageViewer(this.url);
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          icon: const Icon(Icons.download_rounded),
          onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        ),
      ],
    ),
    body: Center(
      child: InteractiveViewer(
        maxScale: 5,
        child: Hero(tag: url, child: Image.network(url)),
      ),
    ),
  );
}

/// Soft gradient with a faint paw pattern (Telegram-style wallpaper).
class _ChatBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: dark
              ? const [Color(0xFF1E1220), Color(0xFF161021), Color(0xFF0F1A19)]
              : const [Color(0xFFFDE3EC), Color(0xFFF1E9FB), Color(0xFFE2F5F0)],
        ),
      ),
      child: CustomPaint(painter: _PawPattern(dark ? Colors.white.withValues(alpha: .035) : MP.pinkDeep.withValues(alpha: .06))),
    );
  }
}

class _PawPattern extends CustomPainter {
  final Color color;
  _PawPattern(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    const step = 90.0;
    var row = 0;
    for (double y = 20; y < size.height; y += step) {
      for (double x = (row.isEven ? 20 : 65); x < size.width; x += step) {
        canvas.drawOval(Rect.fromCenter(center: Offset(x, y + 8), width: 16, height: 13), p);
        canvas.drawCircle(Offset(x - 9, y - 2), 3.6, p);
        canvas.drawCircle(Offset(x - 3, y - 7), 3.6, p);
        canvas.drawCircle(Offset(x + 3, y - 7), 3.6, p);
        canvas.drawCircle(Offset(x + 9, y - 2), 3.6, p);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant _PawPattern old) => old.color != color;
}
