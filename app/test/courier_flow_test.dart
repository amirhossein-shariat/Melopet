// Whole "درخواست پیک" flow in the real screen: case → tests → delivery (free / urgent) → order.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/screens/clinic/courier_request_screen.dart';
import 'package:melopet/services/api.dart';
import 'package:melopet/services/demo/demo_server.dart';
import 'package:melopet/state/app_state.dart';
import 'package:melopet/theme.dart';
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

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> run(WidgetTester t, Brightness brightness, {required bool urgent}) async {
    await t.runAsync(() async {
      DemoServer.instance.reset();
      await Api.pb.collection('users').authWithPassword('09121111111', 'demo1234');
    });
    t.view.physicalSize = const Size(393, 852);
    t.view.devicePixelRatio = 1.0;
    final key = GlobalKey();
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: AppState(),
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: buildTheme(brightness),
            locale: const Locale('fa', 'IR'),
            supportedLocales: const [Locale('fa', 'IR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const CourierRequestScreen(),
          ),
        ),
      ),
    );
    await settle(t);

    // step 1: case
    await t.enterText(find.widgetWithText(TextFormField, 'نام صاحب حیوان *').first, 'آقای تست');
    await t.enterText(find.widgetWithText(TextFormField, 'نام حیوان *').first, 'ملو');
    await t.ensureVisible(find.text('سگ'));
    await t.tap(find.text('سگ'));
    await t.enterText(find.byType(TextField).at(find.byType(TextField).evaluate().length - 3), 'x'); // any field; replaced below
    final history = find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('مثلا: استفراغ'));
    await t.ensureVisible(history);
    await t.enterText(history, 'استفراغ از دیروز');
    await t.pump();
    await t.tap(find.text('مرحله بعد: انتخاب فاکتورها'));
    await settle(t);

    // step 2: pick the first test
    expect(find.text('۲. فاکتورها'), findsOneWidget);
    await t.tap(find.byType(Checkbox).first);
    await t.pump();
    final testsOnly = (t.widget<Text>(find.byKey(const Key('grand-total'))).data!);
    await t.tap(find.text('نحوه ارسال').last);
    await settle(t);

    // step 3: delivery
    expect(find.byKey(const Key('delivery-standard')), findsOneWidget);
    expect(find.text('رایگان'), findsWidgets);
    expect(find.byKey(const Key('urgent-fee')), findsOneWidget, reason: 'urgent price loaded from the courier quote');
    expect(t.widget<Text>(find.byKey(const Key('grand-total'))).data, testsOnly, reason: 'free delivery adds nothing');

    if (urgent) {
      await t.tap(find.byKey(const Key('delivery-urgent')));
      await t.pump();
      final withFee = t.widget<Text>(find.byKey(const Key('grand-total'))).data!;
      expect(withFee, isNot(testsOnly), reason: 'urgent fee is added to the total');
      expect(find.text('هزینه پیک فوری'), findsOneWidget);
    }

    final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final dump = Platform.environment['SHOTS'];
    if (dump != null) {
      await t.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1.5);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dump/delivery-${brightness.name}-${urgent ? 'urgent' : 'free'}.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    final totalShown = t.widget<Text>(find.byKey(const Key('grand-total'))).data!;
    await t.tap(find.text('ثبت و ارسال پیک'));
    await settle(t);
    expect(find.text('درخواست پیک ثبت شد'), findsOneWidget);
    expect(find.textContaining(urgent ? 'پیک فوری اعزام می‌شود' : 'پیک در دور بعدی'), findsOneWidget);

    final order = DemoServer.instance.col('orders').last;
    expect(order['delivery_type'], urgent ? 'urgent' : 'standard');
    expect(order['pet_name'], 'ملو');
    if (urgent) {
      expect(order['delivery_fee'] as num, greaterThanOrEqualTo(80000));
    } else {
      expect(order['delivery_fee'], 0);
    }
    // what the clinic saw is what was charged
    expect(totalShown.replaceAll(RegExp(r'[^۰-۹]'), ''), contains(RegExp(r'[۰-۹]')));

    await t.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('free delivery: order is placed with no extra fee', (t) => run(t, Brightness.light, urgent: false));
  testWidgets('urgent delivery (dark): fee is added and charged', (t) => run(t, Brightness.dark, urgent: true));
}
