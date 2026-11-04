import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
// the SDK's own multipart request type (it is not part of the public exports)
// ignore: implementation_imports
import 'package:pocketbase/src/multipart_request.dart' show MultipartRequest;

import 'demo_seed.dart';

/// An in-memory imitation of the Melopet backend (PocketBase + custom routes).
///
/// It is plugged into the PocketBase client as its HTTP layer, so the whole app
/// runs unchanged without any server — used for the review/demo build.
/// Data lives in memory only: reloading the page resets everything.
class DemoServer {
  DemoServer._();
  static final DemoServer instance = DemoServer._().._seed();

  static const base = 'http://demo.local';
  static const testCode = '1111';

  final Map<String, List<Map<String, dynamic>>> db = {};
  final Map<String, Uint8List> blobs = {};
  final Map<String, _SseClient> _sse = {};
  final _rnd = Random();

  // ------------------------------------------------------------------ schema

  static const _collectionIds = {
    'users': '_pb_users_auth_',
    'clinic_tiers': 'pbc_clinic_tiers',
    'tests': 'pbc_tests',
    'orders': 'pbc_orders',
    'promotions': 'pbc_promotions',
    'notifications': 'pbc_notifications',
    'conversations': 'pbc_conversations',
    'messages': 'pbc_messages',
    'settings': 'pbc_settings',
  };

  static const _relations = {
    'orders': {'clinic': 'users'},
    'conversations': {'clinic': 'users'},
    'messages': {'conversation': 'conversations', 'sender': 'users', 'reply_to': 'messages'},
    'notifications': {'user': 'users'},
    'clinic_tiers': {'clinic': 'users'},
  };

  static const _statusTitles = {
    'requested': 'درخواست پیک ثبت شد',
    'courier_assigned': 'پیک برای شما اعزام شد',
    'picked_up': 'نمونه توسط پیک تحویل گرفته شد',
    'received': 'نمونه در آزمایشگاه دریافت شد',
    'in_progress': 'آزمایش در حال انجام است',
    'ready': 'جواب آزمایش آماده شد',
    'cancelled': 'درخواست لغو شد',
  };

  // ------------------------------------------------------------------ helpers

  String _id() {
    const a = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(15, (_) => a[_rnd.nextInt(a.length)]).join();
  }

  String ts([DateTime? d]) {
    final iso = (d ?? DateTime.now()).toUtc().toIso8601String();
    final dot = iso.indexOf('.');
    // PocketBase format: 2026-11-04 12:00:00.123Z
    return (dot < 0 ? iso.replaceFirst('Z', '.000Z') : '${iso.substring(0, dot + 4)}Z').replaceFirst('T', ' ');
  }

  Map<String, dynamic> newRecord(String col, Map<String, dynamic> data, {String? id, DateTime? created}) {
    final now = ts(created);
    final r = <String, dynamic>{
      'id': id ?? _id(),
      'collectionId': _collectionIds[col],
      'collectionName': col,
      'created': now,
      'updated': now,
      ...data,
    };
    db.putIfAbsent(col, () => []).add(r);
    return r;
  }

  List<Map<String, dynamic>> col(String c) => db.putIfAbsent(c, () => []);

  Map<String, dynamic>? find(String c, String id) {
    for (final r in col(c)) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  Map<String, dynamic>? _findBy(String c, String field, dynamic value) {
    for (final r in col(c)) {
      if (r[field] == value) return r;
    }
    return null;
  }

  String _s(Map<String, dynamic>? r, String f) => (r?[f] ?? '').toString();

  Map<String, dynamic> _clone(Map<String, dynamic> r) => jsonDecode(jsonEncode(r)) as Map<String, dynamic>;

  // ------------------------------------------------------------------ seed

  void _seed() => seedDemoData(this);

  /// Back to the initial sample data (used by tests).
  void reset() {
    for (final c in _sse.values) {
      c.ctrl.close();
    }
    _sse.clear();
    db.clear();
    blobs.clear();
    _seed();
  }

  /// Used by [seedDemoData].
  void setBlob(String c, String id, String name, Uint8List bytes) => blobs['$c/$id/$name'] = bytes;

  // ------------------------------------------------------------------ files

  String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.m4a') || n.endsWith('.mp4')) return 'audio/mp4';
    if (n.endsWith('.mp3')) return 'audio/mpeg';
    if (n.endsWith('.wav')) return 'audio/wav';
    if (n.endsWith('.ogg')) return 'audio/ogg';
    return 'application/octet-stream';
  }

  /// Uploaded files are served back as data: URIs (there is no real file server).
  Uri? fileUri(String c, String id, String name) {
    final b = blobs['$c/$id/$name'];
    if (b == null) return null;
    return Uri.parse('data:${_mime(name)};base64,${base64Encode(b)}');
  }

  // ------------------------------------------------------------------ auth

  String _token(String userId) {
    String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'id': userId, 'exp': exp, 'type': 'auth'})}.demo';
  }

  Map<String, dynamic>? _userFromToken(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map;
      return find('users', '${payload['id']}');
    } catch (_) {
      return null;
    }
  }

  bool _isAdmin(Map<String, dynamic>? u) => u != null && u['role'] == 'admin';

  /// Fields that are never sent to clients.
  Map<String, dynamic> _public(Map<String, dynamic> r) {
    final c = _clone(r);
    c.remove('password');
    return c;
  }

  // ------------------------------------------------------------------ rules

  bool _visible(String c, Map<String, dynamic> r, Map<String, dynamic>? me) {
    if (c == 'settings') return true;
    if (me == null) return false;
    final admin = _isAdmin(me);
    switch (c) {
      case 'users':
        return admin || r['id'] == me['id'];
      case 'tests':
      case 'clinic_tiers':
        return admin;
      case 'orders':
      case 'conversations':
        return admin || r['clinic'] == me['id'];
      case 'messages':
        final conv = find('conversations', _s(r, 'conversation'));
        return admin || (conv != null && conv['clinic'] == me['id']);
      case 'notifications':
        if (r['user'] == me['id']) return true;
        if (_s(r, 'user').isEmpty) {
          if (r['audience'] == 'clinics' && !admin) return true;
          if (r['audience'] == 'admins' && admin) return true;
        }
        return false;
      case 'promotions':
        return admin || r['active'] == true;
    }
    return admin;
  }

  bool _canWrite(String c, String method, Map<String, dynamic>? me, Map<String, dynamic>? rec) {
    final admin = _isAdmin(me);
    switch (c) {
      case 'users':
        if (method == 'POST') return true;
        if (method == 'DELETE') return false;
        return admin || (me != null && rec != null && rec['id'] == me['id']);
      case 'messages':
        return method == 'POST' && me != null;
      case 'conversations':
        return false;
      case 'orders':
        return admin && method != 'DELETE';
      case 'notifications':
        return admin || (method == 'PATCH' && me != null);
    }
    return admin;
  }

  // ------------------------------------------------------------------ filter

  List<_Tok> _lex(String s) {
    final re = RegExp(
      r'''\s*(?:(&&|\|\||!=|!~|>=|<=|=|~|>|<|\(|\))|"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|(-?\d+(?:\.\d+)?)|([A-Za-z_@][\w.@:]*))''',
    );
    final out = <_Tok>[];
    var pos = 0;
    while (pos < s.length) {
      final m = re.matchAsPrefix(s, pos);
      if (m == null || m.end == pos) break;
      pos = m.end;
      if (m.group(1) != null) {
        out.add(_Tok(_T.op, m.group(1)!));
      } else if (m.group(2) != null) {
        out.add(_Tok(_T.str, m.group(2)!.replaceAll(r'\"', '"')));
      } else if (m.group(3) != null) {
        out.add(_Tok(_T.str, m.group(3)!.replaceAll(r"\'", "'")));
      } else if (m.group(4) != null) {
        out.add(_Tok(_T.num, m.group(4)!));
      } else if (m.group(5) != null) {
        out.add(_Tok(_T.id, m.group(5)!));
      }
    }
    return out;
  }

  dynamic _resolve(Map<String, dynamic> rec, String c, String path) {
    final parts = path.split('.');
    Map<String, dynamic>? cur = rec;
    var curCol = c;
    for (var i = 0; i < parts.length; i++) {
      if (cur == null) return null;
      final v = cur[parts[i]];
      if (i == parts.length - 1) return v;
      final rel = _relations[curCol]?[parts[i]];
      if (rel == null || v is! String) return null;
      cur = find(rel, v);
      curCol = rel;
    }
    return null;
  }

  bool Function(Map<String, dynamic>) _compile(String filter, String c) {
    final toks = _lex(filter);
    if (toks.isEmpty) return (_) => true;
    return _FilterParser(this, c, toks).parseOr();
  }

  bool _cmp(String op, dynamic a, dynamic b) {
    dynamic norm(dynamic v) => v ?? '';
    a = norm(a);
    b = norm(b);
    if (op == '~') return a.toString().toLowerCase().contains(b.toString().toLowerCase());
    if (op == '!~') return !a.toString().toLowerCase().contains(b.toString().toLowerCase());
    int c;
    if (a is bool || b is bool) {
      final x = a == true || a == 'true', y = b == true || b == 'true';
      c = x == y ? 0 : 1;
      if (op == '=') return c == 0;
      if (op == '!=') return c != 0;
      return false;
    }
    final na = a is num ? a : num.tryParse('$a');
    final nb = b is num ? b : num.tryParse('$b');
    if (na != null && nb != null && (a is num || b is num)) {
      c = na.compareTo(nb);
    } else {
      c = '$a'.compareTo('$b');
    }
    switch (op) {
      case '=':
        return c == 0;
      case '!=':
        return c != 0;
      case '>':
        return c > 0;
      case '<':
        return c < 0;
      case '>=':
        return c >= 0;
      case '<=':
        return c <= 0;
    }
    return false;
  }

  void _sort(List<Map<String, dynamic>> list, String sort) {
    final keys = sort.split(',').where((e) => e.trim().isNotEmpty).toList();
    if (keys.isEmpty) return;
    int cmpVals(dynamic a, dynamic b) {
      a ??= '';
      b ??= '';
      if (a is bool) a = a ? 1 : 0;
      if (b is bool) b = b ? 1 : 0;
      if (a is num && b is num) return a.compareTo(b);
      return '$a'.compareTo('$b');
    }

    list.sort((x, y) {
      for (final k in keys) {
        final desc = k.startsWith('-');
        final f = k.replaceFirst(RegExp(r'^[-+]'), '');
        final c = cmpVals(x[f], y[f]);
        if (c != 0) return desc ? -c : c;
      }
      return 0;
    });
  }

  Map<String, dynamic> _expand(String c, Map<String, dynamic> r, String expand) {
    final out = _public(r);
    final ex = <String, dynamic>{};
    for (final f in expand.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      final rel = _relations[c]?[f];
      final id = r[f];
      if (rel != null && id is String && id.isNotEmpty) {
        final target = find(rel, id);
        if (target != null) ex[f] = _public(target);
      }
    }
    if (ex.isNotEmpty) out['expand'] = ex;
    return out;
  }

  // ------------------------------------------------------------------ notifications / realtime

  void notify({
    String user = '',
    String audience = 'user',
    String type = 'general',
    required String title,
    String body = '',
    String ref = '',
  }) {
    final r = newRecord('notifications', {
      'user': user,
      'audience': audience,
      'type': type,
      'title': title,
      'body': body,
      'ref': ref,
      'read': false,
    });
    _emit('notifications', 'create', r);
  }

  void _emit(String c, String action, Map<String, dynamic> rec) {
    scheduleMicrotask(() {
      for (final cl in _sse.values) {
        for (final key in cl.topics) {
          final topic = key.split('?').first;
          if (topic != '$c/*' && topic != '$c/${rec['id']}') continue;
          if (!_visible(c, rec, cl.user)) continue;
          final data = jsonEncode({'action': action, 'record': _public(rec)});
          cl.add('event: $key\ndata: $data\n\n');
        }
      }
    });
  }

  String _preview(Map<String, dynamic> m) {
    final text = _s(m, 'text');
    String p;
    switch (_s(m, 'kind')) {
      case 'image':
        p = 'تصویر $text'.trim();
      case 'file':
        p = 'فایل: ${_s(m, 'file_name')}';
      case 'voice':
        p = 'پیام صوتی';
      default:
        p = text;
    }
    return p.length > 120 ? '${p.substring(0, 120)}…' : p;
  }

  // ------------------------------------------------------------------ HTTP entry point

  Future<http.StreamedResponse> handle(http.BaseRequest request) async {
    final url = request.url;
    final method = request.method.toUpperCase();
    final auth = request.headers['Authorization'];
    final segs = url.pathSegments;

    // realtime (SSE)
    if (segs.length == 2 && segs[0] == 'api' && segs[1] == 'realtime') {
      if (method == 'GET') return _openSse();
      final body = await _readBody(request);
      final cl = _sse[body.json['clientId']];
      if (cl == null) return _resp(404, {'status': 404, 'message': 'Missing or invalid client id.', 'data': {}});
      cl.topics = List<String>.from(body.json['subscriptions'] as List? ?? []);
      cl.user = _userFromToken(auth);
      return http.StreamedResponse(const Stream.empty(), 204);
    }

    final body = await _readBody(request);
    try {
      final res = _route(method, url, segs, auth, body);
      return _resp(res.status, res.data);
    } on _Err catch (e) {
      return _resp(e.status, {'status': e.status, 'message': e.message, 'data': e.data});
    }
  }

  http.StreamedResponse _openSse() {
    final id = _id();
    late final StreamController<List<int>> ctrl;
    ctrl = StreamController<List<int>>(onCancel: () => _sse.remove(id));
    final cl = _SseClient(ctrl);
    _sse[id] = cl;
    cl.add('id: $id\nevent: PB_CONNECT\ndata: ${jsonEncode({'clientId': id})}\n\n');
    return http.StreamedResponse(ctrl.stream, 200, headers: {'content-type': 'text/event-stream'});
  }

  Future<_Body> _readBody(http.BaseRequest request) async {
    if (request is MultipartRequest) {
      Map<String, dynamic> json = {};
      final payload = request.fields['@jsonPayload'];
      if (payload != null && payload.isNotEmpty) json = jsonDecode(payload.first) as Map<String, dynamic>;
      final files = <_Upload>[];
      for (final f in request.files) {
        files.add(_Upload(f.field, f.filename ?? 'file', Uint8List.fromList(await f.finalize().expand((e) => e).toList())));
      }
      return _Body(json, files);
    }
    if (request is http.Request && request.body.isNotEmpty) {
      try {
        final d = jsonDecode(request.body);
        if (d is Map<String, dynamic>) return _Body(d, const []);
      } catch (_) {}
    }
    return _Body({}, const []);
  }

  http.StreamedResponse _resp(int status, Object? data) {
    final bytes = data == null ? <int>[] : utf8.encode(jsonEncode(data));
    return http.StreamedResponse(Stream.value(bytes), status, contentLength: bytes.length, headers: {'content-type': 'application/json'});
  }

  // ------------------------------------------------------------------ routing

  _Res _ok(Object? data) => _Res(200, data);

  _Res _route(String method, Uri url, List<String> segs, String? auth, _Body body) {
    final me = _userFromToken(auth);
    final q = url.queryParameters;

    if (segs.length >= 2 && segs[0] == 'api' && segs[1] == 'health') return _ok({'code': 200, 'message': 'demo'});

    // ---- custom routes
    if (segs.length >= 3 && segs[0] == 'api' && segs[1] == 'melopet') {
      return _custom(method, segs.sublist(2), me, body, q);
    }

    // ---- collections
    if (segs.length >= 4 && segs[0] == 'api' && segs[1] == 'collections') {
      final c = segs[2];
      if (!_collectionIds.containsKey(c)) throw _Err(404, 'Missing collection context.');
      if (segs[3] == 'auth-with-password' && method == 'POST') return _authWithPassword(body.json);
      if (segs[3] == 'auth-refresh' && method == 'POST') {
        if (me == null) throw _Err(401, 'The request requires valid record authorization token.');
        return _ok({'token': _token(me['id']), 'record': _public(me)});
      }
      if (segs[3] == 'records') {
        if (segs.length == 4) {
          if (method == 'GET') return _list(c, q, me);
          if (method == 'POST') return _create(c, body, me);
        } else if (segs.length == 5) {
          if (method == 'GET') return _view(c, segs[4], q, me);
          if (method == 'PATCH') return _update(c, segs[4], body, me);
          if (method == 'DELETE') return _delete(c, segs[4], me);
        }
      }
    }
    throw _Err(404, 'The requested resource wasn\'t found.');
  }

  _Res _authWithPassword(Map<String, dynamic> b) {
    final id = '${b['identity']}'.trim();
    final pw = '${b['password']}';
    final u = col('users')
        .where((r) => r['mobile'] == id || (r['username'] != null && r['username'] == id) || (r['email'] != null && r['email'] == id))
        .firstOrNull;
    if (u == null || u['password'] != pw) {
      throw _Err(400, 'Failed to authenticate.');
    }
    return _ok({'token': _token(u['id']), 'record': _public(u)});
  }

  _Res _list(String c, Map<String, String> q, Map<String, dynamic>? me) {
    final pred = _compile(q['filter'] ?? '', c);
    var items = col(c).where((r) => _visible(c, r, me) && pred(r)).toList();
    _sort(items, q['sort'] ?? '');
    final perPage = int.tryParse(q['perPage'] ?? '') ?? 30;
    final page = int.tryParse(q['page'] ?? '') ?? 1;
    final total = items.length;
    final slice = items.skip((page - 1) * perPage).take(perPage);
    final skipTotal = q['skipTotal'] == '1' || q['skipTotal'] == 'true';
    final expand = q['expand'] ?? '';
    return _ok({
      'page': page,
      'perPage': perPage,
      'totalItems': skipTotal ? -1 : total,
      'totalPages': skipTotal ? -1 : max(1, (total / perPage).ceil()),
      'items': slice.map((r) => _expand(c, r, expand)).toList(),
    });
  }

  _Res _view(String c, String id, Map<String, String> q, Map<String, dynamic>? me) {
    final r = find(c, id);
    if (r == null || !_visible(c, r, me)) throw _Err(404, 'The requested resource wasn\'t found.');
    return _ok(_expand(c, r, q['expand'] ?? ''));
  }

  // ---- create

  _Res _create(String c, _Body b, Map<String, dynamic>? me) {
    if (!_canWrite(c, 'POST', me, null)) throw _Err(403, 'Only superusers can perform this action.');
    final data = Map<String, dynamic>.from(b.json);

    if (c == 'users') {
      final admin = _isAdmin(me);
      final mobile = _s(data, 'mobile');
      if (!RegExp(r'^09\d{9}$').hasMatch(mobile)) {
        throw _Err(400, 'Failed to create record.', {
          'mobile': {'message': 'شماره موبایل معتبر نیست'},
        });
      }
      if (!admin && data['otp_proof'] != 'demo-proof-$mobile') {
        throw _Err(400, 'ابتدا شماره موبایل را با کد پیامکی تایید کنید.');
      }
      if (_findBy('users', 'mobile', mobile) != null) {
        throw _Err(400, 'Failed to create record.', {
          'mobile': {'message': 'این شماره قبلا ثبت شده است.'},
        });
      }
      data.remove('otp_proof');
      data.remove('passwordConfirm');
      if (!admin) {
        data['role'] = 'clinic';
        data['approved'] = false;
        data.remove('username');
      }
      data.putIfAbsent('role', () => 'clinic');
    }
    if (c == 'messages') {
      final conv = find('conversations', _s(data, 'conversation'));
      if (conv == null || !_visible('messages', {'conversation': conv['id']}, me)) {
        throw _Err(403, 'Only superusers can perform this action.');
      }
      if (data['sender'] != me!['id']) {
        throw _Err(400, 'Failed to create record.', {
          'sender': {'message': 'Invalid sender.'},
        });
      }
      if (_s(data, 'text').isEmpty && b.files.isEmpty) throw _Err(400, 'Failed to create record.');
      if (_s(data, 'kind').isEmpty) data['kind'] = b.files.isEmpty ? 'text' : 'file';
    }

    final rec = newRecord(c, {..._defaults(c), ...data});
    _applyFiles(rec, b.files);
    _afterCreate(c, rec, me);
    _emit(c, 'create', rec);
    return _ok(_expand(c, rec, ''));
  }

  Map<String, dynamic> _defaults(String c) {
    switch (c) {
      case 'users':
        return {'approved': false, 'profile_completed': false};
      case 'tests':
      case 'promotions':
        return {'active': true};
    }
    return {};
  }

  void _afterCreate(String c, Map<String, dynamic> rec, Map<String, dynamic>? me) {
    switch (c) {
      case 'users':
        if (rec['role'] == 'clinic') {
          newRecord('clinic_tiers', {'clinic': rec['id'], 'tier': 'bronze', 'note': ''});
          notify(
            audience: 'admins',
            title: 'همکار جدید ثبت‌نام کرد',
            body: _s(rec, 'clinic_name').isEmpty ? _s(rec, 'mobile') : _s(rec, 'clinic_name'),
            ref: rec['id'],
          );
        }
      case 'messages':
        final conv = find('conversations', _s(rec, 'conversation'))!;
        final sender = find('users', _s(rec, 'sender'));
        final fromAdmin = _isAdmin(sender);
        final preview = _preview(rec);
        conv['last_text'] = preview;
        conv['last_at'] = rec['created'];
        conv['last_sender'] = rec['sender'];
        conv[fromAdmin ? 'unread_clinic' : 'unread_admin'] = ((conv[fromAdmin ? 'unread_clinic' : 'unread_admin'] ?? 0) as num) + 1;
        conv['updated'] = ts();
        _emit('conversations', 'update', conv);
        if (fromAdmin) {
          notify(user: conv['clinic'], title: 'پیام جدید از آزمایشگاه ملوپت', body: preview, type: 'chat', ref: conv['id']);
        } else {
          notify(audience: 'admins', title: 'پیام از ${_s(sender, 'clinic_name')}', body: preview, type: 'chat', ref: conv['id']);
        }
      case 'promotions':
        if (rec['active'] == true && rec['notify'] == true) {
          notify(audience: 'clinics', title: _s(rec, 'title'), body: _s(rec, 'body'), type: 'promo', ref: rec['id']);
        }
    }
  }

  // ---- update / delete

  _Res _update(String c, String id, _Body b, Map<String, dynamic>? me) {
    final rec = find(c, id);
    if (rec == null || !_visible(c, rec, me)) throw _Err(404, 'The requested resource wasn\'t found.');
    if (!_canWrite(c, 'PATCH', me, rec)) throw _Err(c == 'messages' ? 403 : 404, 'Only superusers can perform this action.');
    final admin = _isAdmin(me);
    final data = Map<String, dynamic>.from(b.json);
    final oldStatus = _s(rec, 'status');
    final oldApproved = rec['approved'] == true;

    if (c == 'users') {
      if (!admin) {
        for (final k in ['role', 'approved', 'username']) {
          if (data.containsKey(k)) throw _Err(404, 'The requested resource wasn\'t found.');
        }
      }
      if (data.containsKey('password')) {
        if (!admin && rec['password'] != data['oldPassword']) {
          throw _Err(400, 'Failed to update record.', {
            'oldPassword': {'message': 'رمز فعلی اشتباه است.'},
          });
        }
        if (data['password'] != data['passwordConfirm']) {
          throw _Err(400, 'Failed to update record.', {
            'passwordConfirm': {'message': 'رمزها یکسان نیستند.'},
          });
        }
      }
      data.remove('oldPassword');
      data.remove('passwordConfirm');
    }

    data.forEach((k, v) => rec[k] = v ?? (k.endsWith('_voice') || k == 'letterhead' || k == 'logo' || k == 'image' ? '' : v));
    _applyFiles(rec, b.files);
    rec['updated'] = ts();

    if (c == 'orders') {
      final status = _s(rec, 'status');
      if (status != oldStatus) {
        (rec['history'] as List? ?? (rec['history'] = [])).add({'status': status, 'at': ts().replaceFirst(' ', 'T'), 'note': ''});
        if (status == 'ready' && _s(rec, 'ready_at').isEmpty) rec['ready_at'] = ts();
        var text = 'سفارش ${_s(rec, 'code')}';
        if (_s(rec, 'pet_name').isNotEmpty) text += ' — ${_s(rec, 'pet_name')}';
        var type = 'order';
        if (status == 'ready') {
          type = 'result';
          text += ' | برای مشاهده و دریافت PDF وارد شوید.';
        }
        if (status == 'courier_assigned' && _s(rec, 'courier_name').isNotEmpty) {
          text += ' | پیک: ${_s(rec, 'courier_name')} ${_s(rec, 'courier_phone')}';
        }
        notify(user: rec['clinic'], title: _statusTitles[status] ?? status, body: text, type: type, ref: rec['id']);
      }
    }
    if (c == 'users' && !oldApproved && rec['approved'] == true && rec['role'] == 'clinic') {
      notify(user: rec['id'], title: 'حساب شما تایید شد', body: 'اکنون می‌توانید درخواست پیک ثبت کنید.');
    }
    _emit(c, 'update', rec);
    return _ok(_expand(c, rec, ''));
  }

  _Res _delete(String c, String id, Map<String, dynamic>? me) {
    final rec = find(c, id);
    if (rec == null || !_visible(c, rec, me)) throw _Err(404, 'The requested resource wasn\'t found.');
    if (!_canWrite(c, 'DELETE', me, rec)) throw _Err(403, 'Only superusers can perform this action.');
    col(c).remove(rec);
    _emit(c, 'delete', rec);
    return _Res(204, null);
  }

  void _applyFiles(Map<String, dynamic> rec, List<_Upload> files) {
    for (final f in files) {
      final append = f.field.endsWith('+');
      final field = append ? f.field.substring(0, f.field.length - 1) : f.field;
      final dot = f.name.lastIndexOf('.');
      final name = dot > 0
          ? '${f.name.substring(0, dot)}_${_id().substring(0, 8)}${f.name.substring(dot)}'
          : '${f.name}_${_id().substring(0, 8)}';
      blobs['${rec['collectionName']}/${rec['id']}/$name'] = f.bytes;
      if (append || rec[field] is List) {
        final list = rec[field] is List ? List<dynamic>.from(rec[field]) : (_s(rec, field).isEmpty ? [] : [rec[field]]);
        rec[field] = [...list, name];
      } else {
        rec[field] = name;
      }
    }
  }

  // ------------------------------------------------------------------ custom routes

  _Res _custom(String method, List<String> s, Map<String, dynamic>? me, _Body body, Map<String, String> q) {
    final route = s.join('/');

    // ---- SMS-code login (public)
    if (route == 'auth/request-code' && method == 'POST') {
      final m = '${body.json['mobile']}'.trim();
      if (!RegExp(r'^09\d{9}$').hasMatch(m)) throw _Err(400, 'شماره موبایل معتبر نیست.');
      return _ok({'sent': true, 'test_mode': true, 'ttl': 300});
    }
    if (route == 'auth/verify' && method == 'POST') {
      final m = '${body.json['mobile']}'.trim();
      if ('${body.json['code']}'.trim() != testCode) throw _Err(400, 'کد وارد شده اشتباه یا منقضی شده است.');
      final u = _findBy('users', 'mobile', m);
      if (u == null) return _ok({'registered': false, 'proof': 'demo-proof-$m'});
      if (u['role'] == 'admin') throw _Err(403, 'این حساب با شناسه ادمین و رمز عبور وارد می‌شود.');
      return _ok({
        'token': _token(u['id']),
        'record': _public(u),
        'meta': {'registered': true},
      });
    }

    if (me == null) throw _Err(401, 'The request requires valid record authorization token.');
    final admin = _isAdmin(me);

    if (route == 'catalog' && method == 'GET') {
      final clinicId = admin && (q['clinic'] ?? '').isNotEmpty ? q['clinic']! : me['id'] as String;
      return _ok(_catalog(clinicId));
    }

    if (route == 'orders' && method == 'POST') return _createOrder(body, me);

    if (s.length == 3 && s[0] == 'orders' && s[2] == 'cancel' && method == 'POST') {
      final o = find('orders', s[1]);
      if (o == null) throw _Err(404, 'Not found.');
      if (!admin) {
        if (o['clinic'] != me['id']) throw _Err(403, 'Forbidden.');
        if (o['status'] != 'requested') throw _Err(400, 'پیک اعزام شده و امکان لغو از طریق اپ وجود ندارد؛ لطفا در چت پیام دهید.');
      }
      return _update('orders', s[1], _Body({'status': 'cancelled'}, const []), {...me, 'role': 'admin'});
    }

    if (route == 'chat/conversation' && method == 'GET') {
      final clinicId = admin ? (q['clinic'] ?? '') : me['id'] as String;
      if (clinicId.isEmpty) throw _Err(400, 'clinic is required');
      var conv = _findBy('conversations', 'clinic', clinicId);
      conv ??= newRecord('conversations', {
        'clinic': clinicId,
        'last_text': '',
        'last_at': '',
        'last_sender': '',
        'unread_clinic': 0,
        'unread_admin': 0,
        'clinic_read_at': '',
        'admin_read_at': '',
      });
      return _ok(_public(conv));
    }

    if (s.length == 3 && s[0] == 'chat' && s[2] == 'read' && method == 'POST') {
      final conv = find('conversations', s[1]);
      if (conv == null) throw _Err(404, 'Not found.');
      if (admin) {
        conv['admin_read_at'] = ts();
        conv['unread_admin'] = 0;
      } else if (conv['clinic'] == me['id']) {
        conv['clinic_read_at'] = ts();
        conv['unread_clinic'] = 0;
      } else {
        throw _Err(403, 'Forbidden.');
      }
      _emit('conversations', 'update', conv);
      return _ok(_public(conv));
    }

    if (admin) {
      if (route == 'admin/stats' && method == 'GET') {
        final orders = col('orders');
        final clinics = col('users').where((u) => u['role'] == 'clinic');
        return _ok({
          'orders_open': orders.where((o) => o['status'] != 'ready' && o['status'] != 'cancelled').length,
          'orders_new': orders.where((o) => o['status'] == 'requested').length,
          'orders_ready': orders.where((o) => o['status'] == 'ready').length,
          'orders_total': orders.length,
          'clinics': clinics.length,
          'clinics_pending': clinics.where((u) => u['approved'] != true).length,
          'revenue': orders.where((o) => o['status'] != 'cancelled').fold<num>(0, (a, o) => a + ((o['total'] ?? 0) as num)),
          'unread_chats': col('conversations').fold<num>(0, (a, c) => a + ((c['unread_admin'] ?? 0) as num)),
        });
      }
      if (route == 'admin/tiers' && method == 'GET') {
        return _ok({for (final t in col('clinic_tiers')) t['clinic'] as String: t['tier']});
      }
      if (s.length == 3 && s[0] == 'admin' && s[1] == 'tiers' && method == 'POST') {
        final tier = '${body.json['tier']}';
        if (!['gold', 'silver', 'bronze'].contains(tier)) throw _Err(400, 'invalid tier');
        final row = _findBy('clinic_tiers', 'clinic', s[2]) ?? newRecord('clinic_tiers', {'clinic': s[2], 'note': ''});
        row['tier'] = tier;
        return _ok({'clinic': s[2], 'tier': tier});
      }
    } else if (route.startsWith('admin/')) {
      throw _Err(403, 'Forbidden.');
    }
    throw _Err(404, 'The requested resource wasn\'t found.');
  }

  String _tierOf(String clinicId) =>
      _s(_findBy('clinic_tiers', 'clinic', clinicId), 'tier').isEmpty ? 'bronze' : _s(_findBy('clinic_tiers', 'clinic', clinicId), 'tier');

  List<Map<String, dynamic>> _catalog(String clinicId) {
    final tier = _tierOf(clinicId);
    final tests = col('tests').where((t) => t['active'] == true).toList();
    _sort(tests, 'sort,name');
    return [
      for (final t in tests)
        if ((t['visible_tiers'] as List? ?? []).isEmpty || (t['visible_tiers'] as List).contains(tier))
          {
            'id': t['id'],
            'name': t['name'],
            'code': t['code'],
            'category': t['category'],
            'sample_type': t['sample_type'],
            'turnaround_hours': t['turnaround_hours'],
            'price': t['price_$tier'],
            'description': t['description'],
          },
    ];
  }

  _Res _createOrder(_Body b, Map<String, dynamic> me) {
    final d = b.json;
    final admin = _isAdmin(me);
    Map<String, dynamic> clinic = me;
    if (admin) {
      final c = find('users', _s(d, 'clinic'));
      if (c == null) throw _Err(400, 'کلینیک را انتخاب کنید');
      clinic = c;
    } else if (me['approved'] != true) {
      throw _Err(403, 'حساب شما هنوز توسط آزمایشگاه تایید نشده است');
    }
    final hasVoice = b.files.any((f) => f.field == 'history_voice');
    if (_s(d, 'clinical_notes').trim().isEmpty && !hasVoice) throw _Err(400, 'تاریخچه کیس (متن یا ویس) الزامی است.');
    if (_s(d, 'pet_name').trim().isEmpty || _s(d, 'owner_name').trim().isEmpty || _s(d, 'species').isEmpty) {
      throw _Err(400, 'نام حیوان، نام صاحب و نوع حیوان الزامی است.');
    }

    final catalog = {for (final c in _catalog(clinic['id'])) c['id'] as String: c};
    final items = <Map<String, dynamic>>[];
    num total = 0;
    for (final id in List<String>.from(d['tests'] ?? const [])) {
      final c = catalog[id];
      if (c == null) throw _Err(400, 'آزمایش انتخاب‌شده معتبر نیست.');
      items.add({'test': id, 'name': c['name'], 'code': c['code'], 'category': c['category'], 'price': c['price']});
      total += (c['price'] ?? 0) as num;
    }

    final addr = _s(d, 'pickup_address').trim();
    final lat = (d['lat'] as num?)?.toDouble(), lon = (d['lon'] as num?)?.toDouble();
    final status = 'requested';
    final rec = newRecord('orders', {
      'code': 'MP-${10001 + col('orders').length}',
      'clinic': clinic['id'],
      'status': status,
      for (final k in [
        'pet_name',
        'species',
        'breed',
        'age',
        'sex',
        'weight',
        'owner_name',
        'file_no',
        'sample_type',
        'sample_count',
        'urgent',
        'fasting',
        'pickup_time',
        'clinical_notes',
      ])
        k: d[k] ?? (k == 'urgent' || k == 'fasting' ? false : ''),
      'pickup_address': addr.isEmpty ? _s(clinic, 'address') : addr,
      'history_voice_seconds': d['history_voice_seconds'] ?? 0,
      'location': (lat != null && lon != null && (lat != 0 || lon != 0)) ? {'lat': lat, 'lon': lon} : clinic['location'],
      'items': items,
      'total': total,
      'discount': 0,
      'courier_name': '',
      'courier_phone': '',
      'results': null,
      'lab_comment': '',
      'result_files': <String>[],
      'history': [
        {'status': status, 'at': ts().replaceFirst(' ', 'T'), 'note': ''},
      ],
      'ready_at': '',
      'paid': false,
    });
    _applyFiles(rec, b.files);
    const species = {
      'dog': 'سگ',
      'cat': 'گربه',
      'bird': 'پرنده',
      'rabbit': 'خرگوش',
      'rodent': 'جونده',
      'reptile': 'خزنده',
      'horse': 'اسب',
      'ruminant': 'نشخوارکننده',
      'other': 'سایر',
    };
    notify(
      audience: 'admins',
      type: 'order',
      title: 'درخواست پیک جدید${rec['urgent'] == true ? ' (فوری)' : ''}',
      body:
          '${_s(clinic, 'clinic_name')} | ${_s(rec, 'pet_name')} (${species[_s(rec, 'species')] ?? ''}) | ${items.length} آزمایش | ${rec['code']}',
      ref: rec['id'],
    );
    _emit('orders', 'create', rec);
    return _ok(_public(rec));
  }
}

// ---------------------------------------------------------------------- filter parser

/// Recursive-descent parser for the PocketBase filter syntax subset the app uses:
/// `field = "x" && (a != 1 || b ~ "y")`, with dotted relation paths.
class _FilterParser {
  final DemoServer server;
  final String collection;
  final List<_Tok> toks;
  var _i = 0;
  _FilterParser(this.server, this.collection, this.toks);

  bool _isOp(String o) => _i < toks.length && toks[_i].type == _T.op && toks[_i].text == o;

  bool Function(Map<String, dynamic>) parseOr() {
    var l = parseAnd();
    while (_isOp('||')) {
      _i++;
      final a = l, b = parseAnd();
      l = (r) => a(r) || b(r);
    }
    return l;
  }

  bool Function(Map<String, dynamic>) parseAnd() {
    var l = _primary();
    while (_isOp('&&')) {
      _i++;
      final a = l, b = _primary();
      l = (r) => a(r) && b(r);
    }
    return l;
  }

  bool Function(Map<String, dynamic>) _primary() {
    if (_isOp('(')) {
      _i++;
      final p = parseOr();
      if (_isOp(')')) _i++;
      return p;
    }
    final left = _operand();
    final op = toks[_i++].text;
    final right = _operand();
    return (r) => server._cmp(op, left(r), right(r));
  }

  dynamic Function(Map<String, dynamic>) _operand() {
    final t = toks[_i++];
    switch (t.type) {
      case _T.str:
        return (_) => t.text;
      case _T.num:
        return (_) => num.parse(t.text);
      case _T.id:
        if (t.text == 'true') return (_) => true;
        if (t.text == 'false') return (_) => false;
        if (t.text == 'null') return (_) => null;
        return (r) => server._resolve(r, collection, t.text);
      case _T.op:
        throw FormatException('unexpected ${t.text}');
    }
  }
}

// ---------------------------------------------------------------------- types

class _Body {
  final Map<String, dynamic> json;
  final List<_Upload> files;
  _Body(this.json, this.files);
}

class _Upload {
  final String field;
  final String name;
  final Uint8List bytes;
  _Upload(this.field, this.name, this.bytes);
}

class _Res {
  final int status;
  final Object? data;
  _Res(this.status, this.data);
}

class _Err implements Exception {
  final int status;
  final String message;
  final Map<String, dynamic> data;
  _Err(this.status, this.message, [this.data = const {}]);
}

class _SseClient {
  final StreamController<List<int>> ctrl;
  List<String> topics = [];
  Map<String, dynamic>? user;
  _SseClient(this.ctrl);

  void add(String s) {
    if (!ctrl.isClosed) ctrl.add(utf8.encode(s));
  }
}

enum _T { op, str, num, id }

class _Tok {
  final _T type;
  final String text;
  _Tok(this.type, this.text);
}

/// HTTP client that answers every request from the in-memory [DemoServer].
class DemoClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => DemoServer.instance.handle(request);

  // the SDK closes clients after each request; the demo server is shared
  @override
  void close() {}
}
