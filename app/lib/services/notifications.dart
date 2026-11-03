import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';

const _bgTask = 'melopet.check_notifications';
const _lastKey = 'notif_last_shown';

/// Background entry point (runs even when the app is closed, ~every 15 min).
@pragma('vm:entry-point')
void notificationWorker() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final prefs = await SharedPreferences.getInstance();
      final pb = Api.create(prefs);
      if (!pb.authStore.isValid) return true;
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(settings: Notifications.initSettings);
      await Notifications.pollAndShow(pb, prefs, plugin);
    } catch (_) {}
    return true;
  });
}

/// Notification strategy (works without Google services, i.e. fine in Iran):
///  * app open / recently used → PocketBase realtime → instant local notification
///  * app closed → WorkManager periodic job fetches new rows and shows them
/// For instant push while the app is fully closed, plug FCM / Pushe / Najva
/// into the backend `notify()` function later — the data model stays the same.
class Notifications {
  Notifications._();
  static final instance = Notifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  UnsubscribeFunc? _unsub;
  bool _ready = false;
  final _tapController = StreamController<String>.broadcast();

  /// Emits the payload ("type:ref") when the user taps a notification.
  Stream<String> get taps => _tapController.stream;

  static const initSettings = InitializationSettings(android: AndroidInitializationSettings('ic_stat_melopet'));

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'melopet_main',
      'اعلان‌های ملوپت',
      channelDescription: 'جواب آزمایش، وضعیت پیک، پیام‌ها و تخفیف‌ها',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFFD9668F),
    ),
  );

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (r) {
          if (r.payload != null) _tapController.add(r.payload!);
        },
      );
      await Workmanager().initialize(notificationWorker);
      _ready = true;
    } catch (e) {
      debugPrint('notifications init failed: $e');
    }
  }

  Future<void> startForUser({void Function(RecordModel)? onNew}) async {
    if (kIsWeb) return;
    await init();
    try {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await Workmanager().registerPeriodicTask(
        _bgTask,
        _bgTask,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (e) {
      debugPrint('workmanager: $e');
    }
    // mark "now" so a fresh login doesn't replay old notifications
    Api.prefs.getString(_lastKey) ?? await Api.prefs.setString(_lastKey, _nowPb());
    await _unsub?.call();
    try {
      _unsub = await Api.pb.collection('notifications').subscribe('*', (e) async {
        if (e.action != 'create' || e.record == null) return;
        final r = e.record!;
        await Api.prefs.setString(_lastKey, r.getStringValue('created'));
        await show(r, _plugin);
        onNew?.call(r);
      });
    } catch (e) {
      debugPrint('realtime: $e');
    }
  }

  Future<void> stop() async {
    await _unsub?.call();
    _unsub = null;
    await Api.prefs.remove(_lastKey);
    if (!kIsWeb) {
      try {
        await Workmanager().cancelByUniqueName(_bgTask);
      } catch (_) {}
    }
  }

  static Future<void> show(RecordModel r, FlutterLocalNotificationsPlugin plugin) async {
    if (kIsWeb) return;
    await plugin.show(
      id: r.id.hashCode & 0x7fffffff,
      title: r.getStringValue('title'),
      body: r.getStringValue('body'),
      notificationDetails: _details,
      payload: '${r.getStringValue('type')}:${r.getStringValue('ref')}',
    );
  }

  static Future<void> pollAndShow(PocketBase pb, SharedPreferences prefs, FlutterLocalNotificationsPlugin plugin) async {
    final last = prefs.getString(_lastKey) ?? _nowPb();
    final list = await pb.collection('notifications').getList(perPage: 10, sort: 'created', filter: 'created > "$last"');
    for (final r in list.items) {
      await show(r, plugin);
    }
    if (list.items.isNotEmpty) {
      await prefs.setString(_lastKey, list.items.last.getStringValue('created'));
    }
  }

  static String _nowPb() => DateTime.now().toUtc().toIso8601String().replaceFirst('T', ' ');
}
