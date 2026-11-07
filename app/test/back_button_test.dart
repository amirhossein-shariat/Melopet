// The Android Back button must never throw the user out of the app by accident:
//  - on a tab other than the first it returns to the first tab (home / dashboard),
//  - on the first tab it asks "leave the app?" and only the explicit "خروج" leaves,
//  - on a pushed screen it goes back to where the user came from.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/screens/admin/admin_shell.dart';
import 'package:melopet/screens/clinic/clinic_shell.dart';
import 'package:melopet/screens/shared/statement_screen.dart';
import 'package:melopet/services/api.dart';
import 'package:melopet/services/demo/demo_server.dart';
import 'package:melopet/state/app_state.dart';
import 'package:melopet/theme.dart';
import 'package:melopet/widgets/glass_nav.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  var exited = 0;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final f = FontLoader('Vazirmatn');
    for (final w in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
      f.addFont(rootBundle.load('assets/fonts/Vazirmatn-$w.ttf'));
    }
    await f.load();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('com.llfbandit.record/messages'), (call) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => '/tmp');
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exited++;
      return null;
    });
    SharedPreferences.setMockInitialValues({kDemoKey: true});
    await Api.init();
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> open(WidgetTester t, {required bool admin}) async {
    exited = 0;
    await t.runAsync(() async {
      DemoServer.instance.reset();
      await Api.pb.collection('users').authWithPassword(admin ? 'melopet' : '09121111111', admin ? 'melopet-admin-1234' : 'demo1234');
    });
    t.view.physicalSize = const Size(393, 852);
    t.view.devicePixelRatio = 1.0;
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: AppState(),
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          locale: const Locale('fa', 'IR'),
          supportedLocales: const [Locale('fa', 'IR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: admin ? const AdminShell() : const ClinicShell(),
        ),
      ),
    );
    await settle(t);
  }

  int tab(WidgetTester t) => t.widget<GlassNavBar>(find.byType(GlassNavBar)).index;

  Future<void> back(WidgetTester t) async {
    await t.binding.handlePopRoute();
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> tearDown(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.runAsync(() async {
      try {
        await Api.pb.realtime.unsubscribe().timeout(const Duration(seconds: 2));
      } catch (_) {}
      DemoServer.instance.reset();
    });
  }

  for (final admin in [false, true]) {
    final who = admin ? 'admin' : 'clinic';
    // tab labels in each shell
    final tabs = admin ? ['سفارش‌ها', 'چت‌ها', 'همکاران', 'بیشتر'] : ['سفارش‌ها', 'چت', 'پیشنهادها', 'پروفایل'];

    testWidgets('$who: Back on any other tab returns to the first tab, then asks before leaving', (t) async {
      await open(t, admin: admin);
      for (var i = 0; i < tabs.length; i++) {
        await t.tap(find.text(tabs[i]).last);
        await settle(t);
        expect(tab(t), i + 1, reason: '${tabs[i]} should be selected');
        await back(t);
        expect(tab(t), 0, reason: 'Back from ${tabs[i]} must go to the first tab');
        expect(find.text('خروج از برنامه'), findsNothing);
        expect(exited, 0);
      }
      // first tab → confirmation, stay
      await back(t);
      expect(find.text('خروج از برنامه'), findsOneWidget);
      await t.tap(find.text('ماندن در برنامه'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('خروج از برنامه'), findsNothing);
      expect(exited, 0);
      // first tab → confirmation, leave
      await back(t);
      await t.tap(find.text('خروج').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(exited, 1);
      await tearDown(t);
    });
  }

  testWidgets('a pushed screen goes back to the tab it was opened from', (t) async {
    await open(t, admin: false);
    await t.tap(find.text('سفارش‌ها').last);
    await settle(t);
    final nav = Navigator.of(t.element(find.byType(GlassNavBar)));
    nav.push(MaterialPageRoute(builder: (_) => const StatementScreen()));
    await settle(t);
    expect(find.byType(StatementScreen), findsOneWidget);
    await back(t);
    await settle(t);
    expect(find.byType(StatementScreen), findsNothing);
    expect(tab(t), 1, reason: 'still on the orders tab');
    expect(find.text('خروج از برنامه'), findsNothing);
    expect(exited, 0);
    await tearDown(t);
  });
}
