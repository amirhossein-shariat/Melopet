import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';

import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/glass.dart';
import '../chat/chat_screen.dart';
import 'order_detail_screen.dart';
import 'promotions_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<RecordModel>? _items;
  String? _error;
  late final String _seen = Api.prefs.getString('notif_seen') ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.pb.collection('notifications').getList(perPage: 100, sort: '-created');
      if (!mounted) return;
      setState(() => _items = r.items);
      context.read<AppState>().markNotificationsSeen();
    } catch (e) {
      if (mounted) setState(() => _error = Api.error(e));
    }
  }

  (IconData, Color) _style(String type) => switch (type) {
    'result' => (Icons.verified_rounded, MP.success),
    'order' => (Icons.delivery_dining_rounded, MP.peachDeep),
    'promo' => (Icons.local_offer_rounded, MP.pinkDeep),
    'chat' => (Icons.chat_rounded, MP.lavenderDeep),
    _ => (Icons.notifications_rounded, MP.mintDeep),
  };

  void _open(RecordModel n) {
    final ref = n.getStringValue('ref');
    switch (n.getStringValue('type')) {
      case 'order':
      case 'result':
        if (ref.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: ref)));
      case 'chat':
        if (Api.isAdmin) {
          Api.pb.collection('conversations').getOne(ref).then((c) {
            if (mounted) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(clinicId: c.getStringValue('clinic'))));
            }
          });
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen()));
        }
      case 'promo':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const MPScaffold(title: 'پیشنهادها', body: PromotionsScreen()),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MPScaffold(
      title: 'اعلان‌ها',
      body: _error != null
          ? ErrorView(_error!, onRetry: _load)
          : _items == null
          ? const Loading()
          : _items!.isEmpty
          ? const EmptyState(icon: Icons.notifications_none_rounded, title: 'اعلانی ندارید')
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _items!.length,
                itemBuilder: (_, i) {
                  final n = _items![i];
                  final (icon, color) = _style(n.getStringValue('type'));
                  final isNew = n.getStringValue('created').compareTo(_seen) > 0;
                  return Glass(
                    margin: const EdgeInsets.only(bottom: 10),
                    tint: isNew ? color.withValues(alpha: .12) : null,
                    onTap: () => _open(n),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GlassIcon(icon, color: color, size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n.getStringValue('title'), style: const TextStyle(fontWeight: FontWeight.w800)),
                              if (n.getStringValue('body').isNotEmpty)
                                Text(n.getStringValue('body'), style: const TextStyle(fontSize: 12.5, height: 1.6)),
                              const SizedBox(height: 4),
                              Text(jDateTime(parseDate(n.getStringValue('created'))), style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                        if (isNew)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
