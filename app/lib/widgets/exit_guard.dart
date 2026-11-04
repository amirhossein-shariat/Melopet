import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass.dart';

/// Back-button behaviour for a root screen:
///  1. if [onBackFirst] handles it (e.g. switches to the home tab) nothing else happens,
///  2. otherwise the user is asked "leave the app?" with two clear choices,
///  3. only "leave" closes the app, so a stray Back press never exits by accident.
class ExitGuard extends StatelessWidget {
  final Widget child;

  /// Return true when the back press was consumed (for example by going to the home tab).
  final bool Function()? onBackFirst;
  const ExitGuard({super.key, required this.child, this.onBackFirst});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (onBackFirst?.call() ?? false) return;
        final leave = await confirm(context, 'خروج از برنامه', 'آیا می‌خواهید از ملوپت خارج شوید؟', ok: 'خروج', cancel: 'ماندن در برنامه');
        if (leave) await SystemNavigator.pop();
      },
      child: child,
    );
  }
}
