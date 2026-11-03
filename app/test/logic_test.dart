import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/utils/format.dart';
import 'package:melopet/utils/results.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:melopet/services/export.dart';

void main() {
  group('format', () {
    test('persian digits round trip', () {
      expect(faNum('09121234567'), '۰۹۱۲۱۲۳۴۵۶۷');
      expect(enNum('۰۹۱۲۱۲۳۴۵۶۷'), '09121234567');
      expect(enNum('٠٩١٢'), '0912');
    });

    test('money grouping', () {
      expect(groupDigits(400000), '400,000');
      expect(groupDigits(95000), '95,000');
      expect(money(1250000, unit: false, persian: false), '1,250,000');
      expect(money(95000), '۹۵٬۰۰۰ $kCurrency');
    });

    test('jalali date', () {
      // 2026-03-21 is 1 Farvardin 1405
      expect(jDate(DateTime(2026, 3, 21), persian: false), '1405/01/01');
    });
  });

  group('results', () {
    test('flags', () {
      expect(flagOf('150', 10, 125), Flag.high);
      expect(flagOf('5', 10, 125), Flag.low);
      expect(flagOf('60', 10, 125), Flag.normal);
      expect(flagOf('Negative', 10, 125), Flag.none);
      expect(flagOf('60', null, null), Flag.none);
    });

    test('species reference ranges with dog fallback', () {
      final p = {
        'ref': {
          'dog': [10, 125],
          'cat': [12, 130],
        },
      };
      expect(refFor(p, 'cat'), (12.0, 130.0));
      expect(refFor(p, 'dog'), (10.0, 125.0));
      expect(refFor(p, 'rabbit'), (10.0, 125.0));
      expect(
        refFor({
          'ref': {
            'dog': [1, 2],
          },
        }, 'cat'),
        (null, null),
      );
    });

    test('encode / parse round trip', () {
      final list = [
        TestResult(
          test: 't1',
          name: 'ALT',
          code: 'ALT',
          category: 'biochemistry',
          params: [ParamResult(key: 'alt', name: 'ALT', unit: 'U/L', low: 10, high: 125, value: '140')],
        ),
        TestResult(test: 't2', name: 'Culture', text: 'E. coli isolated'),
      ];
      final back = parseResults(encodeResults(list));
      expect(back.length, 2);
      expect(back.first.params.first.flag, Flag.high);
      expect(back.first.params.first.range, '10 - 125');
      expect(back.last.text, 'E. coli isolated');
      expect(back.last.hasValues, true);
    });
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  group('export', () {
    final order = RecordModel.fromJson({
      'id': 'o1',
      'code': 'MP-10001',
      'pet_name': 'Melo',
      'species': 'cat',
      'created': '2026-11-01 10:00:00.000Z',
      'results': encodeResults([
        TestResult(
          test: 't1',
          name: 'Glucose',
          code: 'Glu',
          params: [ParamResult(key: 'glu', name: 'Glucose', unit: 'mg/dL', low: 71, high: 159, value: '98')],
        ),
      ]),
    });

    test('excel contains results', () {
      final bytes = Export.resultExcel(order, null);
      expect(bytes.length, greaterThan(1000));
      final book = xl.Excel.decodeBytes(bytes);
      final rows = book['Results'].rows;
      final flat = rows.expand((r) => r).map((c) => c?.value.toString() ?? '').join('|');
      expect(flat, contains('MP-10001'));
      expect(flat, contains('Glucose'));
      expect(flat, contains('71 - 159'));
    });

    test('pdf renders with persian font, with and without letterhead', () async {
      final plain = await Export.resultPdf(order: order);
      expect(String.fromCharCodes(plain.take(5)), '%PDF-');
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAANIAAAEpCAIAAABp2et7AAADCElEQVR4nO3SMQHAIADAMMC/TE4kcMwFPZYo6NF59xnw1qoD+CPbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEbAdAdsRsB0B2xGwHQHbEfgAR84FHoZs5ykAAAAASUVORK5CYII=',
      );
      final withHead = await Export.resultPdf(order: order, letterhead: png, topMm: 50, bottomMm: 30);
      expect(String.fromCharCodes(withHead.take(5)), "%PDF-");
      expect(withHead.length, isNot(plain.length));
      // a corrupt letterhead must not break export
      final broken = await Export.resultPdf(order: order, letterhead: Uint8List.fromList([1, 2, 3]));
      expect(String.fromCharCodes(broken.take(5)), '%PDF-');
    });
  });
}
