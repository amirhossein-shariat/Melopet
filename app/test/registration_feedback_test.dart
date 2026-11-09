// A form that can't continue must SAY why: a message naming the first problem and a scroll to it
// (it used to just not move on, with the red field somewhere off-screen).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/screens/auth/register_screen.dart';
import 'package:melopet/services/api.dart';
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
    SharedPreferences.setMockInitialValues({kDemoKey: true});
    await Api.init();
  });

  Future<void> pumpRegister(WidgetTester t) async {
    t.view.physicalSize = const Size(393, 520); // short screen: the invalid fields are off-screen
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
          home: const RegisterScreen(mobile: '09125550000', proof: 'demo-proof-09125550000'),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('step 1: empty required fields → a message names the first one and how many remain', (t) async {
    await pumpRegister(t);
    await t.tap(find.text('ادامه'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('نام کلینیک / بیمارستان را وارد کنید'), findsWidgets);
    expect(find.textContaining('مورد دیگر'), findsOneWidget, reason: 'the toast says there are more problems');
    // still on step 1
    expect(find.textContaining('مرحله ۱ از ۳'), findsOneWidget);
  });

  testWidgets('step 2: the first missing field (off-screen) is scrolled into view', (t) async {
    await pumpRegister(t);
    // fill step 1
    Future<void> type(String label, String v) async => t.enterText(find.widgetWithText(TextFormField, label).first, v);
    await type('نام کلینیک / بیمارستان *', 'کلینیک تست');
    await type('نام دکتر مسئول مجموعه *', 'دکتر تست');
    await t.ensureVisible(find.widgetWithText(TextFormField, 'تلفن ثابت مجموعه *'));
    await type('تلفن ثابت مجموعه *', '02188000000');
    await t.tap(find.text('ادامه'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('مرحله ۲ از ۳'), findsOneWidget);

    await t.tap(find.text('ادامه'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('را وارد کنید'), findsWidgets);
    // the first invalid field is now on screen (not hidden below the fold)
    final address = find.widgetWithText(TextFormField, 'آدرس کامل (برای مراجعه پیک) *');
    final rect = t.getRect(address);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(520), reason: 'scrolled into view');
  });
}
