import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/theme.dart';
import 'package:melopet/widgets/form_bits.dart';

double _lum(Color c) {
  double ch(double v) => v <= .03928 ? v / 12.92 : pow((v + .055) / 1.055, 2.4).toDouble();
  return .2126 * ch(c.r) + .7152 * ch(c.g) + .0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (max(la, lb) + .05) / (min(la, lb) + .05);
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.linux]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('chip labels are readable: $platform / $brightness', (t) async {
        final theme = buildTheme(brightness).copyWith(platform: platform);
        final dark = brightness == Brightness.dark;
        await t.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: ChoiceRow(options: const {'a': 'کلینیک دامپزشکی', 'b': 'بیمارستان دامپزشکی'}, value: 'a', onChanged: (_) {}),
              ),
            ),
          ),
        );
        final chips = t.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
        expect(chips.length, 2);

        final page = dark ? MP.darkBg : MP.lightBg;
        for (final chip in chips) {
          final label = (chip.label as Text);
          final fg = label.style!.color!;
          expect(label.style!.color, isNotNull, reason: 'label colour must be explicit');
          final Color bg = chip.selected ? chip.selectedColor! : Color.alphaBlend(chip.backgroundColor!, page);
          expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '${chip.selected ? "selected" : "unselected"} chip contrast');
        }
      });
    }
  }
}
