// Delivery choice at checkout: free (next courier round, ≤ 4 h) vs urgent (quoted fee added to the total).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/services/delivery.dart';
import 'package:melopet/services/demo/demo_server.dart';
import 'package:melopet/theme.dart';
import 'package:melopet/utils/accounting.dart';
import 'package:melopet/widgets/delivery_options.dart';
import 'package:pocketbase/pocketbase.dart';

PocketBase client() => PocketBase(DemoServer.base, httpClientFactory: DemoClient.new);

Future<PocketBase> login(String id, String pw) async {
  final pb = client();
  await pb.collection('users').authWithPassword(id, pw);
  return pb;
}

void main() {
  setUp(() => DemoServer.instance.reset());

  group('quote + order (demo server mirrors the backend rules)', () {
    late PocketBase clinic;
    late Map<String, dynamic> base;

    setUp(() async {
      clinic = await login('09121111111', 'demo1234');
      final cat = await clinic.send<List<dynamic>>('/api/melopet/catalog');
      base = {
        'tests': [cat.firstWhere((c) => c['code'] == 'ALT')['id']],
        'pet_name': 'ملو',
        'owner_name': 'صاحب',
        'species': 'dog',
        'clinical_notes': 'تست',
      };
    });

    Future<Map<String, dynamic>> quote({Map<String, dynamic>? body}) =>
        clinic.send<Map<String, dynamic>>('/api/melopet/delivery/quote', method: 'POST', body: body ?? {});

    test('free option is always 0 and states the lab round length; urgent has a price, distance and a signed quote', () async {
      final q = await quote();
      expect(q['standard']['fee'], 0);
      expect(q['standard']['window_hours'], 4);
      final u = q['urgent'] as Map;
      expect(u['available'], true);
      expect(u['fee'], greaterThanOrEqualTo(80000)); // minimum fee of the lab settings
      expect(u['fee'] % 1000, 0);
      expect(u['source'], 'estimate');
      expect(u['distance_km'], greaterThan(0));
      expect((u['quote'] as String), isNotEmpty);
    });

    test('free delivery adds nothing and the order says "within 4 hours"', () async {
      final o = await clinic.send<Map<String, dynamic>>('/api/melopet/orders', method: 'POST', body: {...base, 'delivery': 'standard'});
      final alt = (await clinic.send<List<dynamic>>('/api/melopet/catalog')).firstWhere((c) => c['code'] == 'ALT')['price'];
      expect(o['total'], alt);
      expect(o['delivery_type'], 'standard');
      expect(o['delivery_fee'], 0);
      expect(o['urgent'], false);
      expect(o['pickup_time'], 'تا ۴ ساعت آینده');
    });

    test('urgent: the quoted fee is added to the total and stored on the order', () async {
      final q = await quote();
      final fee = q['urgent']['fee'] as num;
      final o = await clinic.send<Map<String, dynamic>>(
        '/api/melopet/orders',
        method: 'POST',
        body: {...base, 'delivery': 'urgent', 'delivery_quote': q['urgent']['quote'], 'total': 1, 'delivery_fee': 1},
      );
      final alt = (await clinic.send<List<dynamic>>('/api/melopet/catalog')).firstWhere((c) => c['code'] == 'ALT')['price'] as num;
      expect(o['delivery_fee'], fee); // not the client's "1"
      expect(o['total'], alt + fee);
      expect(o['urgent'], true);
      expect(o['delivery_source'], 'estimate');

      // it flows into the clinic's account: charge = tests + courier fee
      final orders = await clinic.collection('orders').getFullList();
      final st = Statement.build(period: const StatementPeriod('all', 'همه', null, null), orders: orders, payments: []);
      expect(st.charges.map((c) => c.order.id), contains(o['id']));
      expect(
        st.chargesTotal,
        orders.where((x) => x.getStringValue('status') != 'cancelled').fold<double>(0, (a, x) => a + x.getDoubleValue('total')),
      );
    });

    test('urgent without a valid quote is refused: missing, forged, for another pin, or expired', () async {
      Future<void> refused(Map<String, dynamic> extra) => expectLater(
        clinic.send('/api/melopet/orders', method: 'POST', body: {...base, 'delivery': 'urgent', ...extra}),
        throwsA(isA<ClientException>().having((e) => e.statusCode, 'status', 400)),
      );
      await refused({});
      await refused({'delivery_quote': 'forged'});
      final q = await quote();
      await refused({'delivery_quote': q['urgent']['quote'], 'lat': 35.9, 'lon': 51.0}); // quote was for the saved pin
      // expired: re-sign the same quote 20 minutes in the past
      final parts = (q['urgent']['quote'] as String).split('|');
      parts[6] = '${DateTime.now().subtract(const Duration(minutes: 20)).millisecondsSinceEpoch}';
      await refused({'delivery_quote': parts.join('|')});
      // another clinic can't use it either
      final other = await login('09122222222', 'demo1234');
      await expectLater(
        other.send('/api/melopet/orders', method: 'POST', body: {...base, 'delivery': 'urgent', 'delivery_quote': q['urgent']['quote']}),
        throwsA(isA<ClientException>()),
      );
      await expectLater(
        clinic.send('/api/melopet/orders', method: 'POST', body: {...base, 'delivery': 'teleport'}),
        throwsA(isA<ClientException>()),
      );
    });

    test('a quote for a pin far away costs more than one near the lab', () async {
      final near = await quote(body: {'lat': 35.7580, 'lon': 51.4110});
      final far = await quote(body: {'lat': 35.95, 'lon': 50.7});
      expect(far['urgent']['fee'], greaterThan(near['urgent']['fee']));
      expect(near['urgent']['fee'], 80000); // clamped to the minimum
    });

    test('no pin → urgent cannot be priced (free option still works)', () async {
      final u = DemoServer.instance.col('users').firstWhere((x) => x['id'] == 'democlinic0001');
      u['location'] = null;
      final q = await quote();
      expect(q['urgent']['available'], false);
      expect(q['urgent']['reason'], 'location');
      expect(q['standard']['fee'], 0);
    });

    test('the lab registering on behalf of a clinic gets the urgent price without a token', () async {
      final admin = await login('melopet', 'melopet-admin-1234');
      final o = await admin.send<Map<String, dynamic>>(
        '/api/melopet/orders',
        method: 'POST',
        body: {...base, 'clinic': 'democlinic0001', 'delivery': 'urgent'},
      );
      expect(o['delivery_fee'], greaterThanOrEqualTo(80000));
    });
  });

  group('DeliveryOptions widget', () {
    Widget host(DeliveryOptionsData? d, {bool loading = false, String value = 'standard', required ValueChanged<String> onChanged}) =>
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: DeliveryOptions(data: d, loading: loading, value: value, onChanged: onChanged, onRetry: () {}),
          ),
        );

    testWidgets('shows free + urgent with price; choosing urgent reports it', (t) async {
      String? picked;
      await t.pumpWidget(
        host(
          DeliveryOptionsData(windowHours: 4, urgentAvailable: true, urgentFee: 153000, source: 'estimate', distanceKm: 10.3, quote: 'q'),
          onChanged: (v) => picked = v,
        ),
      );
      expect(find.text('رایگان'), findsOneWidget);
      expect(find.textContaining('۴ ساعت'), findsWidgets);
      expect(find.byKey(const Key('urgent-fee')), findsOneWidget);
      expect(find.text('۱۵۳٬۰۰۰'), findsOneWidget);
      expect(find.text('قیمت تقریبی'), findsOneWidget);
      await t.tap(find.byKey(const Key('delivery-urgent')));
      expect(picked, 'urgent');
    });

    testWidgets('urgent without a price is disabled and says why', (t) async {
      String? picked;
      await t.pumpWidget(
        host(DeliveryOptionsData(windowHours: 4, urgentAvailable: false, urgentReason: 'location'), onChanged: (v) => picked = v),
      );
      expect(find.textContaining('محل دریافت نمونه را روی نقشه ثبت کنید'), findsOneWidget);
      await t.tap(find.byKey(const Key('delivery-urgent')));
      expect(picked, isNull);
    });
  });
}
