import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/screens/clinic/profile_screen.dart';
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
    SharedPreferences.setMockInitialValues({kDemoKey: true});
    await Api.init();
  });

  testWidgets('a clinic without a logo finds "add logo" in the profile (row + tappable avatar)', (t) async {
    final state = AppState();
    await t.runAsync(() async {
      DemoServer.instance.reset();
      await Api.pb.collection('users').authWithPassword('09121111111', 'demo1234');
      await state.reloadMe();
    });
    t.view.physicalSize = const Size(393, 852);
    t.view.devicePixelRatio = 1.0;
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          locale: const Locale('fa', 'IR'),
          supportedLocales: const [Locale('fa', 'IR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: ProfileScreen()),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('افزودن لوگوی مجموعه'), findsOneWidget);
    expect(find.byKey(const Key('profile-logo')), findsOneWidget);

    await t.tap(find.byKey(const Key('profile-logo')));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('انتخاب لوگو از گالری'), findsOneWidget);
    expect(find.text('حذف لوگو'), findsNothing, reason: 'nothing to remove yet');
  });
}
