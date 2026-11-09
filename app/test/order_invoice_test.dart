// The invoice on the order screen: tests + delivery line − discount = amount payable.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/screens/shared/order_detail_screen.dart';
import 'package:melopet/services/api.dart';
import 'package:melopet/services/demo/demo_server.dart';
import 'package:melopet/state/app_state.dart';
import 'package:melopet/theme.dart';
import 'package:melopet/utils/format.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
    SharedPreferences.setMockInitialValues({kDemoKey: true});
    await Api.init();
  });

  testWidgets('urgent delivery fee and discount show on the invoice and the payable amount adds up', (t) async {
    late String id;
    await t.runAsync(() async {
      DemoServer.instance.reset();
      await Api.pb.collection('users').authWithPassword('09121111111', 'demo1234');
      final o = DemoServer.instance.col('orders').firstWhere((o) => o['clinic'] == 'democlinic0001' && o['status'] == 'ready');
      id = o['id'] as String;
      final tests = (o['items'] as List).fold<num>(0, (a, i) => a + (i['price'] as num));
      o['delivery_type'] = 'urgent';
      o['delivery_fee'] = 120000;
      o['total'] = tests + 120000;
      o['discount'] = 50000;
      o['discount_code'] = 'LIVER20';
    });
    t.view.physicalSize = const Size(393, 1400);
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
          home: OrderDetailScreen(orderId: id),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 250));
    }
    await t.scrollUntilVisible(find.byKey(const Key('order-payable')), 300, scrollable: find.byType(Scrollable).first);
    final order = DemoServer.instance.col('orders').firstWhere((o) => o['id'] == id);
    expect(find.text('ارسال فوری (پیک اختصاصی)'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('order-delivery-fee'))).data, money(120000, unit: false));
    expect(t.widget<Text>(find.byKey(const Key('order-discount'))).data, '− ${money(50000, unit: false)}');
    expect(find.textContaining('تخفیف (کد LIVER20)'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('order-payable'))).data, money((order['total'] as num) - 50000));
    await t.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  });
}
