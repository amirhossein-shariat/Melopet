import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';

import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/glass.dart';
import '../../widgets/logo.dart';
import '../shared/contact_screen.dart';
import '../shared/notifications_screen.dart';
import '../shared/order_detail_screen.dart';
import '../shared/promotions_screen.dart';
import 'courier_request_screen.dart';
import 'price_list_screen.dart';

class HomeScreen extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  const HomeScreen({super.key, required this.onNavigate});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<RecordModel> _active = [];
  List<RecordModel> _promos = [];
  bool _loading = true;
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
      final res = await Future.wait([
        Api.pb.collection('orders').getList(perPage: 10, sort: '-created', filter: 'status != "cancelled"'),
        Api.pb.collection('promotions').getList(perPage: 5, sort: '-created'),
      ]);
      if (!mounted) return;
      setState(() {
        _active = res[0].items;
        _promos = res[1].items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestCourier() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CourierRequestScreen()));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.me;
    final cs = Theme.of(context).colorScheme;
    final logoUrl = me != null && me.getStringValue('logo').isNotEmpty ? Api.fileUrl(me, 'logo', thumb: '200x200').toString() : null;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          await state.reloadMe();
          await state.refreshCounters();
          await _load();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
          children: [
            // header
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: logoUrl != null ? Image.network(logoUrl, width: 50, height: 50, fit: BoxFit.cover) : const MelopetLogo(size: 50),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'سلام، دکتر ${me?.getStringValue('doctor_name') ?? ''} 👋',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      Text(
                        me?.getStringValue('clinic_name') ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cs.onSurface.withValues(alpha: .6), fontSize: 12.5),
                      ),
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
                    child: Icon(Icons.notifications_rounded, color: cs.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            if (!state.approved)
              Glass(
                margin: const EdgeInsets.only(bottom: 14),
                tint: MP.warning.withValues(alpha: .18),
                child: const Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded, color: MP.warning),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'حساب شما در حال بررسی توسط آزمایشگاه است. پس از تایید، امکان درخواست پیک فعال می‌شود. '
                        'در این مدت می‌توانید از چت با ما در ارتباط باشید.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),

            // hero: courier request
            _CourierHero(enabled: state.approved, onTap: _requestCourier),
            const SizedBox(height: 18),

            // quick actions
            GridView.count(
              padding: EdgeInsets.zero,
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: .82,
              children: [
                GlassTile(icon: Icons.receipt_long_rounded, label: 'سفارش‌ها', color: MP.lavenderDeep, onTap: () => widget.onNavigate(1)),
                GlassTile(
                  icon: Icons.price_change_rounded,
                  label: 'تعرفه‌ها',
                  color: MP.mintDeep,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PriceListScreen())),
                ),
                GlassTile(
                  icon: Icons.forum_rounded,
                  label: 'چت',
                  color: MP.pinkDeep,
                  badge: state.unreadChat,
                  onTap: () => widget.onNavigate(2),
                ),
                GlassTile(
                  icon: Icons.support_agent_rounded,
                  label: 'تماس با ما',
                  color: MP.peachDeep,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactScreen())),
                ),
              ],
            ),

            if (_promos.isNotEmpty) ...[
              SectionTitle('پیشنهادهای ویژه', action: 'همه', onAction: () => widget.onNavigate(3)),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _promos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) =>
                      SizedBox(width: MediaQuery.of(context).size.width * .78, child: PromoCard(_promos[i], compact: true)),
                ),
              ),
            ],

            SectionTitle('سفارش‌های اخیر', action: 'مشاهده همه', onAction: () => widget.onNavigate(1)),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Loading())
            else if (_active.isEmpty)
              const Glass(
                child: Row(
                  children: [
                    Icon(Icons.inbox_rounded),
                    SizedBox(width: 10),
                    Expanded(child: Text('هنوز سفارشی ثبت نکرده‌اید. با دکمه «درخواست پیک» اولین نمونه را بفرستید.')),
                  ],
                ),
              )
            else
              for (final o in _active.take(5)) OrderTile(o),
          ],
        ),
      ),
    );
  }
}

class _CourierHero extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _CourierHero({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : .55,
      child: Container(
        decoration: BoxDecoration(
          gradient: MP.brandGradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: MP.pink.withValues(alpha: .5), blurRadius: 28, offset: const Offset(0, 12))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: enabled ? onTap : null,
            child: Stack(
              children: [
                Positioned(
                  left: -20,
                  bottom: -30,
                  child: Icon(Icons.delivery_dining_rounded, size: 150, color: Colors.white.withValues(alpha: .22)),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'درخواست پیک',
                              style: TextStyle(color: MP.plum, fontSize: 22, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'پیک ملوپت نمونه را از مرکز شما تحویل می‌گیرد و جواب را همین‌جا دریافت می‌کنید.',
                              style: TextStyle(color: MP.plum.withValues(alpha: .8), fontSize: 12.5, height: 1.6),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .55),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'ثبت درخواست',
                                    style: TextStyle(color: MP.plum, fontWeight: FontWeight.w800),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.arrow_forward_rounded, color: MP.plum, size: 18),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 90),
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

/// Compact order card used on home & lists.
class OrderTile extends StatelessWidget {
  final RecordModel order;
  final bool showClinic;
  const OrderTile(this.order, {super.key, this.showClinic = false});

  @override
  Widget build(BuildContext context) {
    final status = order.getStringValue('status');
    final s = statusInfo(status);
    final items = (order.data['items'] as List? ?? []).map((e) => (e as Map)['code'] ?? e['name']).join('، ');
    final clinic = order.get<RecordModel?>('expand.clinic');
    final cs = Theme.of(context).colorScheme;
    return Glass(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id))),
      child: Row(
        children: [
          GlassIcon(s.icon, color: s.color, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        showClinic && clinic != null
                            ? clinic.getStringValue('clinic_name')
                            : (order.getStringValue('pet_name').isEmpty
                                  ? 'سفارش ${order.getStringValue('code')}'
                                  : order.getStringValue('pet_name')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (order.getBoolValue('urgent'))
                      Container(
                        margin: const EdgeInsetsDirectional.only(end: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: MP.danger.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)),
                        child: const Text(
                          'فوری',
                          style: TextStyle(color: MP.danger, fontSize: 10.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    StatusChip(status, dense: true),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  items.isEmpty ? '-' : items,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .7)),
                ),
                const SizedBox(height: 2),
                Text(
                  '${faNum(order.getStringValue('code'))} • ${jDateTime(parseDate(order.getStringValue('created')))}'
                  '${showClinic && order.getStringValue('pet_name').isNotEmpty ? ' • ${order.getStringValue('pet_name')}' : ''}',
                  style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: .5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
