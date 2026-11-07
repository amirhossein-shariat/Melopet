import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/services/demo/demo_server.dart';
import 'package:melopet/services/export.dart';
import 'package:melopet/utils/accounting.dart';
import 'package:pocketbase/pocketbase.dart';

RecordModel order(String id, double total, DateTime d, {String status = 'ready', double discount = 0}) => RecordModel({
  'id': id,
  'clinic': 'c1',
  'code': 'MP-$id',
  'status': status,
  'total': total,
  'discount': discount,
  'created': d.toUtc().toIso8601String(),
  'items': [],
});

RecordModel pay(String id, double amount, DateTime d, {String status = 'confirmed'}) => RecordModel({
  'id': id,
  'clinic': 'c1',
  'amount': amount,
  'status': status,
  'method': 'card',
  'paid_at': d.toUtc().toIso8601String(),
  'created': d.toUtc().toIso8601String(),
});

void main() {
  final now = DateTime(2026, 11, 7, 12);
  final presets = StatementPeriod.presets(now);
  StatementPeriod preset(String k) => presets.firstWhere((p) => p.key == k);

  group('Statement maths', () {
    test('balance = non-cancelled orders (minus discount) − confirmed payments; pending is shown, not deducted', () {
      final orders = [
        order('1', 100000, now.subtract(const Duration(days: 2))),
        order('2', 50000, now.subtract(const Duration(days: 1)), discount: 10000),
        order('3', 900000, now, status: 'cancelled'),
      ];
      final pays = [
        pay('p1', 30000, now.subtract(const Duration(days: 1))),
        pay('p2', 20000, now, status: 'pending'),
        pay('p3', 99999, now, status: 'rejected'),
      ];
      final st = Statement.build(period: preset('all'), orders: orders, payments: pays);
      expect(st.chargesTotal, 140000);
      expect(st.confirmedTotal, 30000);
      expect(st.pendingTotal, 20000);
      expect(st.closing, 110000);
      expect(st.charges.length, 2);
      expect(st.payments.length, 2); // rejected is hidden
      expect(Statement.balance(orders, pays), 110000);
    });

    test('older activity becomes the opening balance of a later period', () {
      final lastYear = DateTime(2025, 1, 10);
      final orders = [order('old', 500000, lastYear), order('new', 40000, now)];
      final pays = [pay('old-p', 200000, lastYear)];
      final st = Statement.build(period: preset('month'), orders: orders, payments: pays);
      expect(st.opening, 300000);
      expect(st.chargesTotal, 40000);
      expect(st.closing, 340000);
      // same overall balance whichever period you look at
      expect(st.closing, Statement.balance(orders, pays));
    });

    test('overpaying shows a credit, not a debt', () {
      final st = Statement.build(period: preset('all'), orders: [order('1', 1000, now)], payments: [pay('p', 5000, now)]);
      expect(st.closing, -4000);
      expect(balanceLabel(st.closing), 'بستانکار');
      expect(balanceText(0), 'تسویه شده');
    });

    test('Jalali month presets are contiguous and cover "now"', () {
      final m = preset('month'), prev = preset('prev');
      expect(m.contains(now), true);
      expect(prev.contains(now), false);
      expect(prev.to, m.from);
    });

    test('card number is grouped 4-4-4-4', () {
      expect(cardGroups('6037997012345678'), '6037 9970 1234 5678');
      expect(cardGroups('۶۰۳۷۹۹۷۰۱۲۳۴۵۶۷۸'), '6037 9970 1234 5678');
    });
  });

  group('payments on the demo server', () {
    setUp(() => DemoServer.instance.reset());
    PocketBase client() => PocketBase(DemoServer.base, httpClientFactory: DemoClient.new);

    test('clinic files a pending payment; only the lab confirms it', () async {
      final clinic = client();
      await clinic.collection('users').authWithPassword('09121111111', 'demo1234');
      final created = await clinic
          .collection('payments')
          .create(body: {'clinic': 'democlinic0002', 'amount': 123000, 'status': 'confirmed', 'tracking_no': '1234'});
      // forced to the caller's own account and to "pending", whatever the body says
      expect(created.getStringValue('clinic'), 'democlinic0001');
      expect(created.getStringValue('status'), 'pending');
      expect(() => clinic.collection('payments').update(created.id, body: {'status': 'confirmed'}), throwsA(isA<ClientException>()));

      // another clinic can't see it
      final other = client();
      await other.collection('users').authWithPassword('09122222222', 'demo1234');
      expect((await other.collection('payments').getFullList()).where((p) => p.id == created.id), isEmpty);

      final admin = client();
      await admin.collection('users').authWithPassword('melopet', 'melopet-admin-1234');
      await admin.collection('payments').update(created.id, body: {'status': 'confirmed'});
      final mine = await clinic.collection('payments').getOne(created.id);
      expect(mine.getStringValue('status'), 'confirmed');
      final notes = await clinic.collection('notifications').getFullList();
      expect(notes.any((n) => n.getStringValue('title') == 'پرداخت شما تایید شد'), true);
    });

    test('the lab is told about a new pending payment; zero amounts are rejected', () async {
      final clinic = client();
      await clinic.collection('users').authWithPassword('09121111111', 'demo1234');
      await clinic.collection('payments').create(body: {'amount': 5000});
      expect(() => clinic.collection('payments').create(body: {'amount': 0}), throwsA(isA<ClientException>()));
      final admin = client();
      await admin.collection('users').authWithPassword('melopet', 'melopet-admin-1234');
      final notes = await admin.collection('notifications').getFullList();
      expect(notes.any((n) => n.getStringValue('title') == 'پرداخت جدید ثبت شد'), true);
    });

    test('seeded account: the demo clinic owes the orders minus the confirmed payment', () async {
      final clinic = client();
      await clinic.collection('users').authWithPassword('09121111111', 'demo1234');
      final orders = await clinic.collection('orders').getFullList();
      final pays = await clinic.collection('payments').getFullList();
      final owed = Statement.balance(orders, pays);
      final charges = orders.where((o) => o.getStringValue('status') != 'cancelled').fold(0.0, (a, o) => a + o.getDoubleValue('total'));
      expect(owed, charges - 400000); // 250000 is still pending
      expect(owed, greaterThan(0));
    });
  });

  group('PDF', () {
    setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());
    tearDownAll(() {});

    test('statement and receivables PDFs are real, non-empty PDFs', () async {
      DemoServer.instance.reset();
      final srv = DemoServer.instance;
      RecordModel rec(Map<String, dynamic> m) => RecordModel.fromJson(m);
      final clinic = rec(srv.col('users').firstWhere((u) => u['id'] == 'democlinic0001'));
      final orders = srv.col('orders').where((o) => o['clinic'] == 'democlinic0001').map(rec).toList();
      final pays = srv.col('payments').where((p) => p['clinic'] == 'democlinic0001').map(rec).toList();
      final settings = rec(srv.col('settings').first);
      final st = Statement.build(period: preset('all'), orders: orders, payments: pays);
      final bytes = await Export.statementPdf(statement: st, clinic: clinic, settings: settings);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(5000));

      final debts = await Export.debtsPdf(period: preset('all'), rows: [(clinic, st)], settings: settings);
      expect(String.fromCharCodes(debts.take(5)), '%PDF-');
      final dump = Platform.environment['PDF_DUMP'];
      if (dump != null) {
        File('$dump/statement.pdf').writeAsBytesSync(bytes);
        File('$dump/debts.pdf').writeAsBytesSync(debts);
      }
    });
  });
}
