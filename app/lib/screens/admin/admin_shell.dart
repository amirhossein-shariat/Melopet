import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api.dart';
import '../../services/notifications.dart';
import '../../state/app_state.dart';
import '../../widgets/exit_guard.dart';
import '../../widgets/glass.dart';
import '../../widgets/glass_nav.dart';
import '../chat/chat_screen.dart';
import '../shared/order_detail_screen.dart';
import '../shared/orders_screen.dart';
import 'admin_dashboard.dart';
import 'admin_more_screen.dart';
import 'clinics_screen.dart';
import 'conversations_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  StreamSubscription<String>? _taps;

  @override
  void initState() {
    super.initState();
    _taps = Notifications.instance.taps.listen((payload) async {
      final parts = payload.split(':');
      final ref = parts.length > 1 ? parts[1] : '';
      if (!mounted) return;
      if ((parts.first == 'order' || parts.first == 'result') && ref.isNotEmpty) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: ref)));
      } else if (parts.first == 'chat' && ref.isNotEmpty) {
        final c = await Api.pb.collection('conversations').getOne(ref);
        if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(clinicId: c.getStringValue('clinic'))));
      }
    });
  }

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pages = [
      AdminDashboard(onNavigate: (i) => setState(() => _index = i)),
      const OrdersScreen(),
      const ConversationsScreen(),
      const ClinicsScreen(),
      const AdminMoreScreen(),
    ];
    return ExitGuard(
      // Back from another tab goes to the home tab first; from home it asks before leaving
      onBackFirst: () {
        if (_index != 0) {
          setState(() => _index = 0);
          return true;
        }
        return false;
      },
      child: BlobBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: IndexedStack(index: _index, children: pages),
          bottomNavigationBar: GlassNavBar(
            index: _index,
            onTap: (i) {
              setState(() => _index = i);
              state.refreshCounters();
            },
            items: [
              const NavItem(Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'داشبورد'),
              const NavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'سفارش‌ها'),
              NavItem(Icons.forum_outlined, Icons.forum_rounded, 'چت‌ها', badge: state.unreadChat),
              const NavItem(Icons.local_hospital_outlined, Icons.local_hospital_rounded, 'همکاران'),
              const NavItem(Icons.grid_view_outlined, Icons.grid_view_rounded, 'بیشتر'),
            ],
          ),
        ),
      ),
    );
  }
}
