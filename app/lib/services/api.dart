import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demo/demo_server.dart';

/// Default backend address. Override at build time:
///   flutter build apk --dart-define=API_URL=https://api.melopet.ir
/// or at runtime from the login screen (long-press the logo).
const kDefaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8090');

/// Build the web/APK in demo mode (in-app fake backend, no server needed):
///   flutter build web --dart-define=DEMO=true
const kDemoBuild = bool.fromEnvironment('DEMO');

const kAuthKey = 'pb_auth';
const kServerKey = 'server_url';
const kDemoKey = 'demo_mode';
const kAuthModeKey = 'auth_mode';

/// Single access point to the PocketBase backend.
class Api {
  Api._();
  static late PocketBase pb;
  static late SharedPreferences prefs;

  /// True while the app talks to the built-in fake backend instead of a real server.
  static bool isDemo = false;

  static Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    isDemo = prefs.getBool(kDemoKey) ?? kDemoBuild;
    // never reuse a sign-in made against the other kind of backend
    final mode = isDemo ? 'demo' : 'real';
    if (prefs.getString(kAuthModeKey) != mode) {
      await prefs.remove(kAuthKey);
      await prefs.setString(kAuthModeKey, mode);
    }
    pb = create(prefs);
  }

  static Future<void> setDemo(bool on) async {
    isDemo = on;
    await prefs.setBool(kDemoKey, on);
    await prefs.setString(kAuthModeKey, on ? 'demo' : 'real');
    await prefs.remove(kAuthKey);
    pb.authStore.clear();
    pb = create(prefs);
  }

  /// Builds a client from stored prefs (also used by the background worker).
  static PocketBase create(SharedPreferences prefs) {
    final store = AsyncAuthStore(
      save: (data) async => prefs.setString(kAuthKey, data),
      initial: prefs.getString(kAuthKey),
      clear: () async => prefs.remove(kAuthKey),
    );
    if (isDemo) {
      return PocketBase(DemoServer.base, authStore: store, lang: 'fa', httpClientFactory: DemoClient.new);
    }
    return PocketBase(serverUrl(prefs), authStore: store, lang: 'fa');
  }

  static String serverUrl(SharedPreferences prefs) {
    final v = prefs.getString(kServerKey);
    return (v == null || v.trim().isEmpty) ? kDefaultApiUrl : v.trim();
  }

  static Future<void> setServer(String url) async {
    await prefs.setString(kServerKey, url.trim());
    pb.authStore.clear();
    pb = create(prefs);
  }

  static RecordModel? get me => pb.authStore.record;
  static bool get isAdmin => me?.getStringValue('role') == 'admin';
  static String get myId => me?.id ?? '';

  static Uri fileUrl(RecordModel r, String field, {String? thumb}) {
    final name = r.getStringValue(field);
    if (name.isEmpty) return Uri();
    return fileUrlByName(r, name, thumb: thumb);
  }

  static Uri fileUrlByName(RecordModel r, String filename, {String? thumb}) {
    if (isDemo) {
      // uploaded files live in memory in demo mode and are served as data: URIs
      return DemoServer.instance.fileUri(r.collectionName, r.id, filename) ?? Uri();
    }
    return pb.files.getURL(r, filename, thumb: thumb);
  }

  static Future<List<int>> download(Uri url) async {
    if (url.scheme == 'data') return UriData.fromUri(url).contentAsBytes();
    final res = await http.get(url);
    if (res.statusCode >= 400) throw Exception('download failed: ${res.statusCode}');
    return res.bodyBytes;
  }

  // ------------------------------------------------------------ SMS-code login

  /// Sends a 4-digit code by SMS. Returns true when the server is in TEST MODE
  /// (fixed code, nothing is actually sent).
  static Future<bool> requestCode(String mobile) async {
    final r = await pb.send<Map<String, dynamic>>('/api/melopet/auth/request-code', method: 'POST', body: {'mobile': mobile});
    return r['test_mode'] == true;
  }

  /// Verifies the code. For an existing clinic the user is signed in and `null`
  /// is returned; for a new number the signup proof token is returned.
  static Future<String?> verifyCode(String mobile, String code) async {
    final r = await pb.send<Map<String, dynamic>>('/api/melopet/auth/verify', method: 'POST', body: {'mobile': mobile, 'code': code});
    // existing clinic → PocketBase auth response {token, record, meta}; new number → {registered:false, proof}
    if (r['token'] != null && r['record'] != null) {
      pb.authStore.save('${r['token']}', RecordModel.fromJson(Map<String, dynamic>.from(r['record'] as Map)));
      return null;
    }
    return '${r['proof']}';
  }

  static Future<void> refreshMe() async {
    if (!pb.authStore.isValid) return;
    await pb.collection('users').authRefresh();
  }

  /// Human readable error message (server messages are already Persian).
  static String error(Object e) {
    if (e is ClientException) {
      if (e.statusCode == 0) return 'ارتباط با سرور برقرار نشد. اتصال اینترنت را بررسی کنید.';
      final data = e.response['data'];
      if (data is Map && data.isNotEmpty) {
        final first = data.values.first;
        if (first is Map && first['message'] != null) {
          return '${data.keys.first}: ${first['message']}';
        }
      }
      final msg = e.response['message']?.toString() ?? '';
      if (e.statusCode == 400 && msg.contains('authenticate')) {
        return 'شماره موبایل یا رمز عبور اشتباه است.';
      }
      return msg.isNotEmpty ? msg : 'خطای سرور (${e.statusCode})';
    }
    return e.toString();
  }
}
