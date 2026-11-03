import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default backend address. Override at build time:
///   flutter build apk --dart-define=API_URL=https://api.melopet.ir
/// or at runtime from the login screen (long-press the logo).
const kDefaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8090');

const kAuthKey = 'pb_auth';
const kServerKey = 'server_url';

/// Single access point to the PocketBase backend.
class Api {
  Api._();
  static late PocketBase pb;
  static late SharedPreferences prefs;

  static Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    pb = create(prefs);
  }

  /// Builds a client from stored prefs (also used by the background worker).
  static PocketBase create(SharedPreferences prefs) {
    final store = AsyncAuthStore(
      save: (data) async => prefs.setString(kAuthKey, data),
      initial: prefs.getString(kAuthKey),
      clear: () async => prefs.remove(kAuthKey),
    );
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
    return pb.files.getURL(r, name, thumb: thumb);
  }

  static Uri fileUrlByName(RecordModel r, String filename, {String? thumb}) => pb.files.getURL(r, filename, thumb: thumb);

  static Future<List<int>> download(Uri url) async {
    final res = await http.get(url);
    if (res.statusCode >= 400) throw Exception('download failed: ${res.statusCode}');
    return res.bodyBytes;
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
