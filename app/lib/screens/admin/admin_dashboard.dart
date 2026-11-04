import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';

import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/glass.dart';
import '../../widgets/logo.dart';
import '../clinic/home_screen.dart';
import '../shared/notifications_screen.dart';
import 'broadcast_screen.dart';
import 'promotion_edit_screen.dart';
import 'tests_screen.dart';

class AdminDashboard extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  const AdminDashboard({super.key, required this.onNavigate});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  Map<String, dynamic>? _stats;
  List<RecordModel> _new = [];
  UnsubscribeFunc? _unsub;

  @override
  void initState() {
    super.initState();
    _load();
    Api.pb.collection('orders').subscribe('*', (_) => _load()).then((u) => _unsub = u).catchError((_) => () async {});
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await Api.pb.send<Map<String, dynamic>>('/api/melopet/admin/stats');
      final n = await Api.pb
          .collection('orders')
          .getList(perPage: 8, sort: '-urgent,-created', filter: 'status != "ready" && status != "cancelled"', expand: 'clinic');
      if (mounted) {
        setState(() {
          _stats = s;
          _new = n.items;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = _stats ?? {};
    int n(String k) => (s[k] as num?)?.toInt() ?? 0;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await state.refreshCounters();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 130),
          children: [
            Row(
              children: [
                const MelopetLogo(size: 48),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('پنل مدیریت ملوپت', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      Text('همه چیز زیر نظر شماست', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                Glass(
                  padding: const EdgeInsets.all(10),
                  radius: 16,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                    state.refreshCounters();
                  },
                  child: Badge(
                    isLabelVisible: state.unreadNotifications > 0,
                    label: Text(faNum(state.unreadNotifications)),
                    child: Icon(Icons.notifications_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.count(
              padding: EdgeInsets.zero,
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                _Stat('درخواست جدید', n('orders_new'), Icons.fiber_new_rounded, MP.pinkDeep, () => widget.onNavigate(1)),
                _Stat('در جریان', n('orders_open'), Icons.pending_actions_rounded, MP.lavenderDeep, () => widget.onNavigate(1)),
                _Stat('پیام خوانده‌نشده', n('unread_chats'), Icons.mark_chat_unread_rounded, MP.mintDeep, () => widget.onNavigate(2)),
                _Stat('همکار در انتظار تایید', n('clinics_pending'), Icons.how_to_reg_rounded, MP.peachDeep, () => widget.onNavigate(3)),
              ],
            ),
            const SizedBox(height: 10),
            Glass(
              child: Row(
                children: [
                  const GlassIcon(Icons.payments_rounded, color: MP.success, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('مجموع مبلغ سفارش‌ها', style: TextStyle(fontSize: 12)),
                        Text(money((s['revenue'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${faNum(n('orders_total'))} سفارش', style: const TextStyle(fontSize: 12)),
                      Text('${faNum(n('clinics'))} همکار', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const SectionTitle('دسترسی سریع'),
            GridView.count(
              padding: EdgeInsets.zero,
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: .8,
              children: [
                GlassTile(
                  icon: Icons.science_rounded,
                  label: 'آزمایش‌ها',
                  color: MP.lavenderDeep,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TestsScreen())),
                ),
                GlassTile(
                  icon: Icons.local_offer_rounded,
                  label: 'تخفیف جدید',
                  color: MP.pinkDeep,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PromotionEditScreen())),
                ),
                GlassTile(
                  icon: Icons.campaign_rounded,
                  label: 'اعلان همگانی',
                  color: MP.peachDeep,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BroadcastScreen())),
                ),
                GlassTile(
                  icon: Icons.forum_rounded,
                  label: 'چت‌ها',
                  color: MP.mintDeep,
                  badge: state.unreadChat,
                  onTap: () => widget.onNavigate(2),
                ),
              ],
            ),
            SectionTitle('سفارش‌های در جریان', action: 'همه', onAction: () => widget.onNavigate(1)),
            if (_stats == null)
              const Padding(padding: EdgeInsets.all(24), child: Loading())
            else if (_new.isEmpty)
              const Glass(child: Text('سفارش بازی وجود ندارد 🎉'))
            else
              for (final o in _new) OrderTile(o, showClinic: true),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _Stat(this.label, this.value, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => Glass(
    onTap: onTap,
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        GlassIcon(icon, color: color, size: 44),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                faNum(value),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: readable(context, color)),
              ),
              Text(label, maxLines: 2, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    ),
  );
}
