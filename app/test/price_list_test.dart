import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/services/demo/demo_server.dart';
import 'package:melopet/utils/format.dart';
import 'package:pocketbase/pocketbase.dart';

PocketBase client() => PocketBase(DemoServer.base, httpClientFactory: DemoClient.new);

/// The lab's price list (k1.xlsx), thousands of Toman; null = "*" (negotiable).
const sheet = <String, int?>{
  'CBC': 400,
  'AST': 95,
  'ALT': 95,
  'ALP': 95,
  'GGT': 99,
  'UREA': 95,
  'SCR': 95,
  'BIL.T': 95,
  'BIL.D': 95,
  'CHOL': 95,
  'TG': 95,
  'GLU': 95,
  'T.P': 95,
  'ALB': 95,
  'CK': 200,
  'CA': 95,
  'PHOS': 95,
  'NA': 190,
  'K': 190,
  'LIPASE': 300,
  'AMYLASE': 300,
  'F10': 950,
  'FE': 190,
  'CL': 190,
  'CORTISOL': 490,
  'T4': 490,
  'TSH': 500,
  'URINALYSIS': 570,
  'URHIIASIS': 490,
  'FNA': 1300,
  'RIVALTA': 340,
  'CYTOLOGY': 1000,
  'DIRECT SMEAR': 400,
  'INCUBATION': 400,
  'GRAM': null,
  'STOOL EXAM': 600,
  'FLOTATION': null,
  'PATHOLOGY': 2500,
  'VAGINAL SMEAR': 550,
  'PCR': 1400,
  'REAL TIME': null,
  'KNOT': 590,
  'RABBIS IN': 14000,
  'RABBIS EX': null,
  'RETICULOCYTE C.': 375,
  'CROSS MATCH': 900,
  'PBFD': 875,
  'GENDER': 875,
};

void main() {
  setUp(() => DemoServer.instance.reset());

  test('demo catalog has every test of the price list with the right price ', () {
    final tests = DemoServer.instance.col('tests');
    final byCode = {for (final t in tests) (t['code'] as String).toUpperCase(): t};
    for (final e in sheet.entries) {
      final t = byCode[e.key];
      expect(t, isNotNull, reason: 'missing ${e.key}');
      expect(t!['price'], (e.value ?? 0) * 1000, reason: e.key);
    }
  });

  test('the backend migration carries the same list and prices', () {
    final src = File('../backend/migrations/1700000006_lab_price_list.go').readAsStringSync();
    final re = RegExp(r'\{"([^"]+)",\s*"[^"]*",\s*"[^"]*",\s*"[^"]*",\s*[\d.]+,\s*([\d.]+),');
    final go = {for (final m in re.allMatches(src)) m.group(1)!: double.parse(m.group(2)!).round()};
    expect(go.length, sheet.length);
    for (final e in sheet.entries) {
      expect(go[e.key], e.value ?? 0, reason: e.key);
    }
  });

  test('clinics see "توافقی" for unpriced tests and normal prices otherwise', () {
    expect(priceText(0), 'توافقی');
    expect(priceText(95000, unit: false), '۹۵٬۰۰۰');
  });

  test('admin can add, edit, hide and delete a test; clinics cannot', () async {
    final admin = client();
    await admin.collection('users').authWithPassword('melopet', 'melopet-admin-1234');
    final t = await admin
        .collection('tests')
        .create(body: {'name': 'تست نو', 'code': 'NEW1', 'category': 'biochemistry', 'price': 1000, 'active': true, 'parameters': []});
    await admin.collection('tests').update(t.id, body: {'price': 0, 'active': false});
    final got = await admin.collection('tests').getOne(t.id);
    expect(got.getDoubleValue('price'), 0);
    expect(got.getBoolValue('active'), false);

    final clinic = client();
    await clinic.collection('users').authWithPassword('09121111111', 'demo1234');
    expect(() => clinic.collection('tests').delete(t.id), throwsA(isA<ClientException>()));
    await admin.collection('tests').delete(t.id);
    expect((await admin.collection('tests').getFullList()).where((x) => x.id == t.id), isEmpty);
  });
}
