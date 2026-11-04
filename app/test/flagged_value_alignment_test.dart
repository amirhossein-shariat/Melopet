import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/widgets/glass.dart';

/// The high/low arrow must sit on the same optical centre as the digits (it used to hang ~2px too low).
Future<void> loadFonts() async {
  final f = FontLoader('Vazirmatn');
  for (final w in ['Regular', 'Bold']) {
    f.addFont(rootBundle.load('assets/fonts/Vazirmatn-$w.ttf'));
  }
  await f.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/root/sdk/flutter';
  final bytes = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync();
  final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(bytes)));
  await icons.load();
}

void main() {
  testWidgets('result arrow is vertically aligned with the digits', (t) async {
    await loadFonts();
    t.view.physicalSize = const Size(400, 120);
    t.view.devicePixelRatio = 1;
    final key = GlobalKey();
    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: Colors.white,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                DefaultTextStyle(
                  style: TextStyle(fontFamily: 'Vazirmatn'),
                  child: FlaggedValue(value: '21.4', high: true, color: Colors.black),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.runAsync(() async {
      final img = await t.renderObject<RenderRepaintBoundary>(find.byKey(key)).toImage(pixelRatio: 8);
      final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final w = img.width, h = img.height;
      // text box and icon box in image pixels
      final textBox = t.getRect(find.text('21.4')), iconBox = t.getRect(find.byType(Icon));
      double centerY(Rect r) {
        var minY = h, maxY = -1;
        for (var y = (r.top * 8).floor(); y < (r.bottom * 8).ceil() && y < h; y++) {
          for (var x = (r.left * 8).floor(); x < (r.right * 8).ceil() && x < w; x++) {
            final i = (y * w + x) * 4;
            if (bd.getUint8(i) < 128) {
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
            }
          }
        }
        return (minY + maxY) / 2 / 8;
      }

      // ignore: avoid_print
      print(
        'INK centre: digits=${centerY(textBox).toStringAsFixed(2)}  arrow=${centerY(iconBox).toStringAsFixed(2)}  (px, 1x)  boxes: text=${textBox.top.toStringAsFixed(1)}..${textBox.bottom.toStringAsFixed(1)} icon=${iconBox.top.toStringAsFixed(1)}..${iconBox.bottom.toStringAsFixed(1)}',
      );
    });
  });
}
