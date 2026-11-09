import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/services/demo/demo_server.dart';
import 'package:melopet/services/export.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  test('result PDF builds', () async {
    DemoServer.instance.reset();
    final srv = DemoServer.instance;
    RecordModel rec(Map<String, dynamic> m) => RecordModel.fromJson(m);
    final order = rec(srv.col('orders').firstWhere((o) => o['status'] == 'ready'));
    final clinic = rec(srv.col('users').firstWhere((u) => u['id'] == order.getStringValue('clinic')));
    final bytes = await Export.resultPdf(order: order, clinic: clinic);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final dump = Platform.environment['PDF_DUMP'];
    if (dump != null) File('$dump/result.pdf').writeAsBytesSync(bytes);
  });
}
