import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../services/api.dart';
import '../services/notifications.dart';

class AppState extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;
  RecordModel? settings; // lab contact info
  int unreadNotifications = 0;
  int unreadChat = 0;

  RecordModel? get me => Api.me;
  bool get loggedIn => Api.pb.authStore.isValid && me != null;
  bool get isAdmin => Api.isAdmin;
  bool get approved => me?.getBoolValue('approved') ?? false;

  AppState() {
    final t = Api.prefs.getString('theme');
    themeMode = switch (t) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    Api.pb.authStore.onChange.listen((_) => notifyListeners());
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    Api.prefs.setString('theme', m.name);
    notifyListeners();
  }

  Future<void> bootstrap() async {
    try {
      if (Api.pb.authStore.isValid) await Api.refreshMe();
    } on ClientException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 404) Api.pb.authStore.clear();
    } catch (_) {}
    await loadSettings();
    if (loggedIn) await onLoggedIn();
  }

  Future<void> loadSettings() async {
    try {
      final list = await Api.pb.collection('settings').getList(perPage: 1);
      if (list.items.isNotEmpty) settings = list.items.first;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> onLoggedIn() async {
    await Notifications.instance.startForUser(onNew: (_) => refreshCounters());
    await refreshCounters();
  }

  Future<void> refreshCounters() async {
    if (!loggedIn) return;
    try {
      final since = Api.prefs.getString('notif_seen') ?? '2000-01-01 00:00:00';
      final r = await Api.pb.collection('notifications').getList(perPage: 1, filter: 'created > "$since"');
      unreadNotifications = r.totalItems;
      final convs = await Api.pb.collection('conversations').getFullList();
      unreadChat = convs.fold(0, (s, c) => s + c.getIntValue(isAdmin ? 'unread_admin' : 'unread_clinic'));
      notifyListeners();
    } catch (_) {}
  }

  void markNotificationsSeen() {
    final now = DateTime.now().toUtc().toIso8601String().replaceFirst('T', ' ');
    Api.prefs.setString('notif_seen', now);
    unreadNotifications = 0;
    notifyListeners();
  }

  Future<void> reloadMe() async {
    try {
      await Api.refreshMe();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> logout() async {
    await Notifications.instance.stop();
    Api.pb.authStore.clear();
    unreadChat = 0;
    unreadNotifications = 0;
    notifyListeners();
  }
}
