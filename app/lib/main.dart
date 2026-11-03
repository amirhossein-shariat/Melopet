import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/admin/admin_shell.dart';
import 'screens/auth/login_screen.dart';
import 'screens/clinic/clinic_shell.dart';
import 'screens/splash_screen.dart';
import 'services/api.dart';
import 'services/notifications.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  await Notifications.instance.init();
  runApp(ChangeNotifierProvider(create: (_) => AppState(), child: const MelopetApp()));
}

class MelopetApp extends StatelessWidget {
  const MelopetApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'ملوپت',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: state.themeMode,
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Root(),
    );
  }
}

/// Decides which shell to show based on auth state.
class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final state = context.read<AppState>();
    await Future.wait([state.bootstrap(), Future.delayed(const Duration(milliseconds: 1200))]);
    if (mounted) setState(() => _booted = true);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    Widget child;
    if (!_booted) {
      child = const SplashScreen();
    } else if (!state.loggedIn) {
      child = const LoginScreen();
    } else if (state.isAdmin) {
      child = const AdminShell();
    } else {
      child = const ClinicShell();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: KeyedSubtree(key: ValueKey(child.runtimeType), child: child),
    );
  }
}
