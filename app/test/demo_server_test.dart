import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:melopet/services/demo/demo_server.dart';
import 'package:pocketbase/pocketbase.dart';

PocketBase client() => PocketBase(DemoServer.base, httpClientFactory: DemoClient.new);

Future<PocketBase> login(String id, String pw) async {
  final pb = client();
  await pb.collection('users').authWithPassword(id, pw);
  return pb;
}

void main() {
  setUp(() => DemoServer.instance.reset());

  group('auth', () {
    test('password login: admin by ID, clinic by mobile, wrong password fails', () async {
      final admin = await login('melopet', 'melopet-admin-1234');
      expect(admin.authStore.isValid, true);
      expect(admin.authStore.record!.getStringValue('role'), 'admin');
      final clinic = await login('09121111111', 'demo1234');
      expect(clinic.authStore.record!.getStringValue('clinic_name'), 'کلینیک دامپزشکی مهر');
      expect(() => login('melopet', 'nope'), throwsA(isA<ClientException>()));
    });

    test('SMS code: only 1111 works; new numbers get a proof and can register; admin cannot use codes', () async {
      final pb = client();
      final sent = await pb.send('/api/melopet/auth/request-code', method: 'POST', body: {'mobile': '09125550000'});
      expect(sent['test_mode'], true);
      expect(
        () => pb.send('/api/melopet/auth/verify', method: 'POST', body: {'mobile': '09125550000', 'code': '2222'}),
        throwsA(isA<ClientException>()),
      );
      final v = await pb.send('/api/melopet/auth/verify', method: 'POST', body: {'mobile': '09125550000', 'code': '1111'});
      expect(v['registered'], false);

      // registration needs the proof…
      expect(
        () => pb.collection('users').create(body: {'mobile': '09125550000', 'password': 'abcdefgh', 'passwordConfirm': 'abcdefgh'}),
        throwsA(isA<ClientException>()),
      );
      // …and can't forge a role
      final rec = await pb
          .collection('users')
          .create(
            body: {
              'mobile': '09125550000',
              'otp_proof': v['proof'],
              'password': 'abcdefgh',
              'passwordConfirm': 'abcdefgh',
              'clinic_name': 'کلینیک نو',
              'role': 'admin',
            },
          );
      expect(rec.getStringValue('role'), 'clinic');
      expect(rec.getBoolValue('approved'), false);

      // existing clinic signs in with the code
      final again = await pb.send('/api/melopet/auth/verify', method: 'POST', body: {'mobile': '09121111111', 'code': '1111'});
      expect(again['meta']['registered'], true);
      expect(again['token'], isNotEmpty);

      // admin must use ID + password
      expect(
        () => pb.send('/api/melopet/auth/verify', method: 'POST', body: {'mobile': '09000000000', 'code': '1111'}),
        throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', 403)),
      );
    });
  });

  group('data access', () {
    test('clinic sees only its own orders; admin sees all; filters, sort and expand work', () async {
      final clinic = await login('09121111111', 'demo1234');
      final mine = await clinic.collection('orders').getFullList(sort: '-created', expand: 'clinic');
      expect(mine, isNotEmpty);
      expect(mine.every((o) => o.getStringValue('clinic') == 'democlinic0001'), true);
      expect(mine.first.get<RecordModel?>('expand.clinic')?.getStringValue('clinic_name'), 'کلینیک دامپزشکی مهر');
      final dates = mine.map((o) => o.getStringValue('created')).toList();
      expect([...dates]..sort((a, b) => b.compareTo(a)), dates);

      final admin = await login('melopet', 'melopet-admin-1234');
      final all = await admin.collection('orders').getFullList();
      expect(all.length, greaterThan(mine.length));
      final urgentOpen = await admin
          .collection('orders')
          .getFullList(filter: 'urgent = true && status != "ready" && status != "cancelled"');
      expect(urgentOpen.every((o) => o.getBoolValue('urgent')), true);
      final byClinicName = await admin.collection('orders').getFullList(filter: '(code ~ "zzz" || clinic.clinic_name ~ "سپید")');
      expect(byClinicName.every((o) => o.getStringValue('clinic') == 'democlinic0002'), true);
      expect(byClinicName, isNotEmpty);
      final paged = await admin.collection('orders').getList(page: 1, perPage: 2);
      expect(paged.items.length, 2);
      expect(paged.totalItems, all.length);
    });

    test('one price for everyone: clinics cannot read the tests table, the catalog has the same price for all, no tier routes', () async {
      final a = await login('09121111111', 'demo1234');
      final b = await login('09122222222', 'demo1234');
      expect((await a.collection('tests').getList()).items, isEmpty);

      Future<num> cbcPrice(PocketBase pb) async {
        final cat = await pb.send<List<dynamic>>('/api/melopet/catalog');
        return (cat.firstWhere((c) => c['code'] == 'CBC')['price'] as num);
      }

      expect(await cbcPrice(a), 400000);
      expect(await cbcPrice(b), 400000);
      final admin = await login('melopet', 'melopet-admin-1234');
      expect(() => admin.send('/api/melopet/admin/tiers'), throwsA(isA<ClientException>()));
      expect(DemoServer.instance.db.containsKey('clinic_tiers'), false);
    });
  });

  group('courier request & order flow', () {
    test('history is required; total is computed on the server; admin is notified', () async {
      final pb = await login('09121111111', 'demo1234');
      final cat = await pb.send<List<dynamic>>('/api/melopet/catalog');
      final alt = cat.firstWhere((c) => c['code'] == 'ALT');
      final base = {
        'tests': [alt['id']],
        'pet_name': 'تست',
        'owner_name': 'صاحب',
        'species': 'dog',
        'total': 1,
      };

      expect(() => pb.send('/api/melopet/orders', method: 'POST', body: base), throwsA(isA<ClientException>()));
      expect(
        () => pb.send('/api/melopet/orders', method: 'POST', body: {...base, 'species': '', 'clinical_notes': 'x'}),
        throwsA(isA<ClientException>()),
      );

      final o = await pb.send<Map<String, dynamic>>(
        '/api/melopet/orders',
        method: 'POST',
        body: {...base, 'clinical_notes': 'استفراغ', 'lat': 35.7, 'lon': 51.4},
      );
      expect(o['status'], 'requested');
      expect(o['total'], alt['price']); // not the client's "1"
      expect(o['location'], {'lat': 35.7, 'lon': 51.4});

      // voice-only history is accepted too
      final voice = http.MultipartFile.fromBytes('history_voice', [1, 2, 3], filename: 'h.m4a');
      final o2 = await pb.send<Map<String, dynamic>>('/api/melopet/orders', method: 'POST', body: base, files: [voice]);
      expect((o2['history_voice'] as String), startsWith('h_'));

      final admin = await login('melopet', 'melopet-admin-1234');
      final notifs = await admin.collection('notifications').getFullList(sort: '-created');
      expect(notifs.first.getStringValue('title'), contains('درخواست پیک جدید'));
      expect(notifs.first.getStringValue('body'), contains('تست'));
    });

    test('admin moves an order along; the clinic gets a notification; clinic cannot edit orders', () async {
      final admin = await login('melopet', 'melopet-admin-1234');
      final clinic = await login('09121111111', 'demo1234');
      final order = (await clinic.collection('orders').getFullList(filter: 'status = "requested"')).first;

      expect(() => clinic.collection('orders').update(order.id, body: {'total': 1}), throwsA(isA<ClientException>()));
      final before = (await clinic.collection('notifications').getFullList()).length;
      final up = await admin
          .collection('orders')
          .update(order.id, body: {'status': 'courier_assigned', 'courier_name': 'پیک', 'courier_phone': '0935'});
      expect(up.getStringValue('status'), 'courier_assigned');
      expect((up.data['history'] as List).last['status'], 'courier_assigned');
      final after = await clinic.collection('notifications').getFullList(sort: '-created');
      expect(after.length, before + 1);
      expect(after.first.getStringValue('title'), 'پیک برای شما اعزام شد');

      // already dispatched → the clinic can no longer cancel from the app
      await expectLater(
        clinic.send('/api/melopet/orders/${order.id}/cancel', method: 'POST'),
        throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', 400)),
      );
    });
  });

  group('chat', () {
    test('messages update the conversation, notify the other side, and can never be edited or deleted', () async {
      final clinic = await login('09121111111', 'demo1234');
      final admin = await login('melopet', 'melopet-admin-1234');
      final conv = RecordModel.fromJson(await clinic.send('/api/melopet/chat/conversation'));
      final me = clinic.authStore.record!.id;

      // cannot spoof the sender
      expect(
        () => clinic.collection('messages').create(body: {'conversation': conv.id, 'sender': 'demoadmin00001', 'text': 'x'}),
        throwsA(isA<ClientException>()),
      );
      final m = await clinic.collection('messages').create(body: {'conversation': conv.id, 'sender': me, 'text': 'سلام تست'});
      expect(m.getStringValue('kind'), 'text');

      final stats = await admin.send<Map<String, dynamic>>('/api/melopet/admin/stats');
      expect(stats['unread_chats'], greaterThan(0));
      final c = await clinic.collection('conversations').getOne(conv.id);
      expect(c.getStringValue('last_text'), 'سلام تست');

      expect(() => clinic.collection('messages').delete(m.id), throwsA(isA<ClientException>()));
      expect(() => admin.collection('messages').delete(m.id), throwsA(isA<ClientException>()));
      expect(() => admin.collection('messages').update(m.id, body: {'text': 'y'}), throwsA(isA<ClientException>()));

      await clinic.send('/api/melopet/chat/${conv.id}/read', method: 'POST');
      expect((await clinic.collection('conversations').getOne(conv.id)).getIntValue('unread_clinic'), 0);
    });

    test('realtime: a new message is pushed to the other participant', () async {
      final clinic = await login('09121111111', 'demo1234');
      final admin = await login('melopet', 'melopet-admin-1234');
      final conv = RecordModel.fromJson(await clinic.send('/api/melopet/chat/conversation'));

      final got = Completer<RecordModel>();
      final unsub = await clinic.collection('messages').subscribe('*', (e) {
        if (e.action == 'create' && !got.isCompleted) got.complete(e.record!);
      }, filter: 'conversation = "${conv.id}"');

      await admin.collection('messages').create(body: {'conversation': conv.id, 'sender': 'demoadmin00001', 'text': 'پیام زنده'});
      final r = await got.future.timeout(const Duration(seconds: 5));
      expect(r.getStringValue('text'), 'پیام زنده');
      await unsub();
    });
  });

  test('promotions: clinics see only active ones; creating one with notify broadcasts', () async {
    final admin = await login('melopet', 'melopet-admin-1234');
    final clinic = await login('09121111111', 'demo1234');
    await admin.collection('promotions').create(body: {'title': 'مخفی', 'active': false});
    await admin.collection('promotions').create(body: {'title': 'جدید', 'active': true, 'notify': true});
    final titles = (await clinic.collection('promotions').getFullList()).map((p) => p.getStringValue('title')).toList();
    expect(titles, contains('جدید'));
    expect(titles, isNot(contains('مخفی')));
    final n = await clinic.collection('notifications').getFullList(filter: 'created > "2000-01-01 00:00:00"');
    expect(n.any((x) => x.getStringValue('title').contains('جدید')), true);
    expect(() => clinic.collection('promotions').create(body: {'title': 'x'}), throwsA(isA<ClientException>()));
  });
}
