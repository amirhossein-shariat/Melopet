// Renders the real screens (demo data) in both themes and measures the contrast of every
// piece of text against the pixels actually drawn behind it (glass, blur, gradients included).
//
// Background colour = median of the pixels inside the text box (glyphs cover a minority
// of the box, so the median is the surface behind the text).

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/screens/admin/admin_dashboard.dart';
import 'package:melopet/screens/admin/admin_more_screen.dart';
import 'package:melopet/screens/admin/broadcast_screen.dart';
import 'package:melopet/screens/admin/clinics_screen.dart';
import 'package:melopet/screens/admin/conversations_screen.dart';
import 'package:melopet/screens/admin/promotion_edit_screen.dart';
import 'package:melopet/screens/admin/result_entry_screen.dart';
import 'package:melopet/screens/admin/tests_screen.dart';
import 'package:melopet/screens/auth/code_screen.dart';
import 'package:melopet/screens/auth/login_screen.dart';
import 'package:melopet/screens/auth/register_screen.dart';
import 'package:melopet/screens/chat/chat_screen.dart';
import 'package:melopet/screens/clinic/courier_request_screen.dart';
import 'package:melopet/screens/clinic/home_screen.dart';
import 'package:melopet/screens/clinic/price_list_screen.dart';
import 'package:melopet/screens/clinic/profile_screen.dart';
import 'package:melopet/screens/shared/contact_screen.dart';
import 'package:melopet/screens/shared/notifications_screen.dart';
import 'package:melopet/screens/shared/order_detail_screen.dart';
import 'package:melopet/screens/shared/orders_screen.dart';
import 'package:melopet/screens/shared/promotions_screen.dart';
import 'package:melopet/services/api.dart';
import 'package:melopet/services/demo/demo_server.dart';
import 'package:melopet/state/app_state.dart';
import 'package:melopet/theme.dart';
import 'package:melopet/widgets/glass.dart';
import 'package:melopet/widgets/glass_nav.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Finding {
  final String screen, text;
  final double ratio, need;
  final Color fg, bg;
  Finding(this.screen, this.text, this.ratio, this.need, this.fg, this.bg);
  String get hex => '#${fg.toARGB32().toRadixString(16).substring(2)} on #${bg.toARGB32().toRadixString(16).substring(2)}';
}

double _lum(Color c) {
  double ch(double v) => v <= .03928 ? v / 12.92 : pow((v + .055) / 1.055, 2.4).toDouble();
  return .2126 * ch(c.r) + .7152 * ch(c.g) + .0722 * ch(c.b);
}

double _ratio(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (max(la, lb) + .05) / (min(la, lb) + .05);
}

Future<void> _loadFonts() async {
  final f = FontLoader('Vazirmatn');
  for (final w in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
    f.addFont(rootBundle.load('assets/fonts/Vazirmatn-$w.ttf'));
  }
  await f.load();
}

class _Shot {
  final ByteData data;
  final int w, h;
  _Shot(this.data, this.w, this.h);
  Color px(int x, int y) {
    final i = (y * w + x) * 4;
    return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
  }
}

Color _median(_Shot s, Rect r) {
  final rs = <int>[], gs = <int>[], bs = <int>[];
  final x0 = max(0, r.left.floor()), x1 = min(s.w - 1, r.right.ceil() - 1);
  final y0 = max(0, r.top.floor()), y1 = min(s.h - 1, r.bottom.ceil() - 1);
  final stepX = max(1, ((x1 - x0) / 40).floor()), stepY = max(1, ((y1 - y0) / 12).floor());
  for (var y = y0; y <= y1; y += stepY) {
    for (var x = x0; x <= x1; x += stepX) {
      final c = s.px(x, y);
      rs.add((c.r * 255).round());
      gs.add((c.g * 255).round());
      bs.add((c.b * 255).round());
    }
  }
  if (rs.isEmpty) return Colors.transparent;
  int med(List<int> l) => (l..sort())[l.length ~/ 2];
  return Color.fromARGB(255, med(rs), med(gs), med(bs));
}

void main() {
  final findings = <String, List<Finding>>{};
  final checked = <String, int>{};
  var readyOrderId = '';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    // plugins that only exist on a real device
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('com.llfbandit.record/messages'), (call) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => '/tmp');
    SharedPreferences.setMockInitialValues({kDemoKey: true});
    await Api.init();
  });

  Future<void> audit(WidgetTester t, String name, Widget Function() screen, {required bool admin, bool tab = false}) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await t.runAsync(() async {
        DemoServer.instance.reset();
        await Api.pb.collection('users').authWithPassword(admin ? 'melopet' : '09121111111', admin ? 'melopet-admin-1234' : 'demo1234');
        readyOrderId = DemoServer.instance.col('orders').firstWhere((o) => o['status'] == 'ready')['id'] as String;
      });
      t.view.physicalSize = const Size(393, 852);
      t.view.devicePixelRatio = 1.0;
      final key = GlobalKey();
      final state = AppState();
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(brightness),
              locale: const Locale('fa', 'IR'),
              supportedLocales: const [Locale('fa', 'IR')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              // tab screens live inside the shell (glass nav bar); everything else is a full-screen route
              home: tab
                  ? BlobBackground(
                      child: Scaffold(
                        backgroundColor: Colors.transparent,
                        extendBody: true,
                        body: screen(),
                        bottomNavigationBar: GlassNavBar(
                          index: 0,
                          onTap: (_) {},
                          items: const [
                            NavItem(Icons.home_outlined, Icons.home_rounded, 'خانه'),
                            NavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'سفارش‌ها'),
                            NavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'چت', badge: 2),
                            NavItem(Icons.local_offer_outlined, Icons.local_offer_rounded, 'پیشنهادها'),
                            NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'پروفایل'),
                          ],
                        ),
                      ),
                    )
                  : screen(),
            ),
          ),
        ),
      );
      // let async data (demo server) arrive and animations settle
      for (var i = 0; i < 8; i++) {
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
        await t.pump(const Duration(milliseconds: 250));
      }

      final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
      late _Shot shot;
      await t.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1.0);
        final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        shot = _Shot(bd!, img.width, img.height);
        final dump = Platform.environment['DUMP'];
        if (dump != null && dump.split(',').any((d) => '$name/${brightness.name}'.contains(d))) {
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('/tmp/claude-0/dump-$name-${brightness.name}.png').writeAsBytesSync(png!.buffer.asUint8List());
        }
      });

      // ignore: avoid_print
      print('  [$name/${brightness.name}] captured');
      final tag = '$name/${brightness.name}';
      for (final el in find.byType(RichText).evaluate()) {
        final ro = el.renderObject;
        if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;
        final span = ro.text;
        if (span is! TextSpan) continue;
        final style = span.style;
        final plain = span.toPlainText().trim();
        if (plain.isEmpty || style?.fontFamily == 'MaterialIcons' || style?.fontFamily == 'CupertinoIcons') continue;
        // ignore pure icon glyphs
        if (plain.runes.every((r) => r >= 0xE000 && r <= 0xF8FF)) continue;
        final topLeft = ro.localToGlobal(Offset.zero);
        final rect = (topLeft & ro.size).intersect(Rect.fromLTWH(0, 0, shot.w.toDouble(), shot.h.toDouble()));
        if (rect.width < 4 || rect.height < 4) continue;
        // mostly outside the screen (clipped by a scroller) → not actually visible
        if (rect.width * rect.height < .9 * ro.size.width * ro.size.height) continue;
        final bg = _median(shot, rect.deflate(1));
        var fg = style?.color ?? Colors.black;
        if (fg.a < 1) fg = Color.alphaBlend(fg, bg);
        final size = style?.fontSize ?? 14;
        final bold = (style?.fontWeight?.value ?? 400) >= 700;
        final need = (size >= 24 || (size >= 18.66 && bold)) ? 3.0 : 4.5;
        final r = _ratio(fg, bg);
        checked[tag] = (checked[tag] ?? 0) + 1;
        if (r < need) findings.putIfAbsent(tag, () => []).add(Finding(tag, plain.replaceAll('\n', ' '), r, need, fg, bg));
      }

      // tear down: stop realtime streams and timers before the next round
      // ignore: avoid_print
      print('  [$name/${brightness.name}] measured, tearing down');
      await t.pumpWidget(const SizedBox());
      // let the fake clock finish disposing (unsubscribe requests are queued on it)
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.runAsync(() async {
        try {
          await Api.pb.realtime.unsubscribe().timeout(const Duration(seconds: 2));
        } catch (_) {}
        DemoServer.instance.reset();
      });
      await t.pump(const Duration(milliseconds: 10));
    }
  }

  const tabScreens = {
    'clinic-home',
    'clinic-orders',
    'clinic-chat',
    'clinic-promos',
    'clinic-profile',
    'admin-dashboard',
    'admin-orders',
    'admin-chats',
    'admin-clinics',
    'admin-more',
  };
  final screens = <String, (Widget Function(), bool)>{
    'clinic-home': (() => HomeScreen(onNavigate: (_) {}), false),
    'clinic-orders': (() => const OrdersScreen(), false),
    'clinic-order-detail': (() => OrderDetailScreen(orderId: readyOrderId), false),
    'clinic-chat': (() => const ChatScreen(), false),
    'clinic-promos': (() => const PromotionsScreen(), false),
    'clinic-profile': (() => const ProfileScreen(), false),
    'clinic-contact': (() => const ContactScreen(), false),
    'clinic-prices': (() => const PriceListScreen(), false),
    'clinic-courier': (() => const CourierRequestScreen(), false),
    'clinic-edit-profile': (() => const EditProfileScreen(), false),
    'clinic-letterhead': (() => const LetterheadScreen(), false),
    'notifications': (() => const NotificationsScreen(), false),
    'register': (() => const RegisterScreen(mobile: '09125550000', proof: 'demo-proof-09125550000'), false),
    'code': (() => const CodeScreen(mobile: '09125550000', testMode: true), false),
    'login': (() => const LoginScreen(), false),
    'admin-dashboard': (() => AdminDashboard(onNavigate: (_) {}), true),
    'admin-orders': (() => const OrdersScreen(), true),
    'admin-chats': (() => const ConversationsScreen(), true),
    'admin-clinics': (() => const ClinicsScreen(), true),
    'admin-tests': (() => const TestsScreen(), true),
    'admin-more': (() => const AdminMoreScreen(), true),
    'admin-lab-settings': (() => const LabSettingsScreen(), true),
    'admin-broadcast': (() => const BroadcastScreen(), true),
    'admin-promo-edit': (() => const PromotionEditScreen(), true),
  };

  for (final e in screens.entries) {
    testWidgets('contrast: ${e.key}', (t) async {
      await audit(t, e.key, e.value.$1, admin: e.value.$2, tab: tabScreens.contains(e.key));
    });
  }

  // admin screens that need a record id
  testWidgets('contrast: admin clinic + result entry', (t) async {
    await audit(t, 'admin-clinic', () {
      final c = DemoServer.instance.col('users').firstWhere((u) => u['id'] == 'democlinic0001');
      return ClinicAdminScreen(clinic: _rec(c), tier: 'gold');
    }, admin: true);
    await audit(t, 'admin-result-entry', () {
      final o = DemoServer.instance.col('orders').firstWhere((o) => o['status'] == 'courier_assigned');
      return ResultEntryScreen(order: _rec(o));
    }, admin: true);
  });

  // runs last (tests execute in declaration order): fails the suite if any text is unreadable
  testWidgets('contrast: every text on every screen meets the threshold', (t) async {
    final all = findings.values.expand((e) => e).toList()..sort((a, b) => a.ratio.compareTo(b.ratio));
    expect(
      all,
      isEmpty,
      reason: all.take(15).map((f) => '${f.ratio.toStringAsFixed(2)} (need ${f.need}) ${f.screen} "${f.text}" ${f.hex}').join('\n'),
    );
  });

  tearDownAll(() {
    final out = StringBuffer();
    final all = findings.values.expand((e) => e).toList()..sort((a, b) => a.ratio.compareTo(b.ratio));
    out.writeln('Checked ${checked.values.fold(0, (a, b) => a + b)} text items on ${checked.length} screen/theme combinations.');
    out.writeln('Below threshold: ${all.length}');
    for (final f in all) {
      out.writeln(
        '${f.ratio.toStringAsFixed(2)} (need ${f.need})  ${f.screen}  "${f.text.length > 50 ? f.text.substring(0, 50) : f.text}"  ${f.hex}',
      );
    }
    File(Platform.environment['CONTRAST_REPORT'] ?? '/tmp/contrast_report.txt').writeAsStringSync(out.toString());
    // ignore: avoid_print
    print(out);
  });
}

RecordModel _rec(Map<String, dynamic> m) => RecordModel.fromJson(m);
