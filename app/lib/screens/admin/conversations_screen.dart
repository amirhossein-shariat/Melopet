import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';

import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/glass.dart';
import '../chat/chat_screen.dart';
import 'clinics_screen.dart';

/// Admin inbox: one conversation per clinic, newest first.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});
  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<RecordModel>? _items;
  String _q = '';
  UnsubscribeFunc? _unsub;

  @override
  void initState() {
    super.initState();
    _load();
    Api.pb.collection('conversations').subscribe('*', (_) => _load()).then((u) => _unsub = u).catchError((_) => () async {});
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.pb.collection('conversations').getFullList(sort: '-last_at', expand: 'clinic');
      if (mounted) setState(() => _items = r);
      if (mounted) context.read<AppState>().refreshCounters();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final items = (_items ?? []).where((c) {
      final clinic = c.get<RecordModel?>('expand.clinic');
      return _q.isEmpty ||
          (clinic?.getStringValue('clinic_name').contains(_q) ?? false) ||
          (clinic?.getStringValue('doctor_name').contains(_q) ?? false);
    }).toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton(
          tooltip: 'گفتگوی جدید',
          onPressed: () async {
            final clinic = await Navigator.push<RecordModel>(
              context,
              MaterialPageRoute(builder: (_) => const ClinicsScreen(pickMode: true)),
            );
            if (clinic != null && context.mounted) {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(clinicId: clinic.id)));
              _load();
            }
          },
          child: const Icon(Icons.edit_rounded),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 12, 18, 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('گفتگوها', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'جستجوی مرکز یا دکتر'),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            Expanded(
              child: _items == null
                  ? const Loading()
                  : items.isEmpty
                  ? const EmptyState(icon: Icons.forum_rounded, title: 'گفتگویی نیست')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final c = items[i];
                          final clinic = c.get<RecordModel?>('expand.clinic');
                          final unread = c.getIntValue('unread_admin');
                          final name = clinic?.getStringValue('clinic_name') ?? '-';
                          return Glass(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => ChatScreen(clinicId: c.getStringValue('clinic'))),
                              );
                              _load();
                            },
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: MP.pink,
                                  backgroundImage: clinic != null && clinic.getStringValue('logo').isNotEmpty
                                      ? NetworkImage(Api.fileUrl(clinic, 'logo', thumb: '200x200').toString())
                                      : null,
                                  child: clinic == null || clinic.getStringValue('logo').isEmpty
                                      ? Text(
                                          name.characters.first,
                                          style: const TextStyle(fontWeight: FontWeight.w900, color: MP.plum),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w800),
                                            ),
                                          ),
                                          Text(
                                            c.getStringValue('last_at').isEmpty ? '' : _when(parseDate(c.getStringValue('last_at'))!),
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              c.getStringValue('last_text').isEmpty ? '—' : c.getStringValue('last_text'),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 12.5),
                                            ),
                                          ),
                                          if (unread > 0)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(color: MP.pinkDeep, borderRadius: BorderRadius.circular(10)),
                                              child: Text(
                                                faNum(unread),
                                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _when(DateTime d) {
    final now = DateTime.now();
    if (now.difference(d).inHours < 24 && now.day == d.day) return hm(d);
    return jDate(d);
  }
}
