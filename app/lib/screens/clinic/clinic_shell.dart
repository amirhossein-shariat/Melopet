import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/notifications.dart';
import '../../state/app_state.dart';
import '../../widgets/exit_guard.dart';
import '../../widgets/glass.dart';
import '../../widgets/glass_nav.dart';
import '../chat/chat_screen.dart';
import '../shared/orders_screen.dart';
import '../shared/order_detail_screen.dart';
import '../shared/promotions_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class ClinicShell extends StatefulWidget {
  const ClinicShell({super.key});
  @override
  State<ClinicShell> createState() => _ClinicShellState();
}

class _ClinicShellState extends State<ClinicShell> {
  int _index = 0;
  StreamSubscription<String>? _taps;

  @override
  void initState() {
    super.initState();
    _taps = Notifications.instance.taps.listen(_openPayload);
  }

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  void _openPayload(String payload) {
    final parts = payload.split(':');
    final type = parts.first;
    final ref = parts.length > 1 ? parts[1] : '';
    if ((type == 'order' || type == 'result') && ref.isNotEmpty) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: ref)));
    } else if (type == 'chat') {
      setState(() => _index = 2);
    } else if (type == 'promo') {
      setState(() => _index = 3);
    }
  }

  void go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pages = [
      HomeScreen(onNavigate: go),
      const OrdersScreen(),
      // built only while visible so incoming messages aren't auto-marked as read
      _index == 2 ? const ChatScreen() : const SizedBox(),
      const PromotionsScreen(),
      const ProfileScreen(),
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
          // hide the floating nav while the keyboard is open so it doesn't sit on top of the input
          bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
              ? null
              : GlassNavBar(
                  index: _index,
                  onTap: (i) {
                    go(i);
                    if (i == 2) state.refreshCounters();
                  },
                  items: [
                    const NavItem(Icons.home_outlined, Icons.home_rounded, 'خانه'),
                    const NavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'سفارش‌ها'),
                    NavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'چت', badge: state.unreadChat),
                    const NavItem(Icons.local_offer_outlined, Icons.local_offer_rounded, 'پیشنهادها'),
                    const NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'پروفایل'),
                  ],
                ),
        ),
      ),
    );
  }
}
