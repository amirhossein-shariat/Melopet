import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/utils/units.dart';
import 'package:melopet/widgets/glass.dart';

void main() {
  group('parseUnit', () {
    test('superscript characters and ^n become exponents', () {
      expect(parseUnit('×10³/µL').map((p) => p.toString()).toList(), ['×10', '^3', '/µL']);
      expect(parseUnit('×10⁶/µL').map((p) => p.toString()).toList(), ['×10', '^6', '/µL']);
      expect(parseUnit('x10^9/L').map((p) => p.toString()).toList(), ['x10', '^9', '/L']);
      expect(parseUnit('×10⁻³').map((p) => p.toString()).toList(), ['×10', '^-3']);
    });
    test('ordinary units are untouched', () {
      for (final u in ['mg/dL', 'U/L', '%', 'g/dL', 'µg/dL', '']) {
        expect(parseUnit(u).length, 1);
        expect(parseUnit(u).single.sup, false);
        expect(unitPlain(u), u);
      }
    });
    test('plain text keeps the exponent readable (Excel)', () {
      expect(unitPlain('×10³/µL'), '×10^3/µL');
    });
  });

  Widget rtl(Widget child) => MaterialApp(
    locale: const Locale('fa', 'IR'),
    supportedLocales: const [Locale('fa', 'IR')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(child: SizedBox(width: 200, child: child)),
      ),
    ),
  );

  RenderParagraph para(WidgetTester t, String contains) =>
      t.renderObject<RenderParagraph>(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains(contains)).first);

  testWidgets('in a right-to-left screen the unit still reads left-to-right: "×10³/µL", not "µL/10³×"', (t) async {
    await t.pumpWidget(rtl(const UnitText('×10³/µL')));
    final p = para(t, '×10');
    final plain = p.text.toPlainText();
    final first = p.getBoxesForSelection(TextSelection(baseOffset: plain.indexOf('×'), extentOffset: plain.indexOf('×') + 1)).first;
    final last = p.getBoxesForSelection(TextSelection(baseOffset: plain.indexOf('µ'), extentOffset: plain.indexOf('µ') + 1)).first;
    expect(first.left, lessThan(last.left), reason: '"×" comes before "µ" from the left');
  });

  testWidgets('control: WITHOUT the fix a plain Text in a right-to-left screen shows the range reversed', (t) async {
    await t.pumpWidget(rtl(const Text('5.5 - 19.5')));
    final p = para(t, '5.5');
    final first = p.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1)).first;
    final last = p.getBoxesForSelection(const TextSelection(baseOffset: 8, extentOffset: 9)).first;
    expect(first.left, greaterThan(last.left), reason: 'this is the bug the lab saw');
  });

  testWidgets('a range keeps its order: "5.5 - 19.5" (low first, reading left to right)', (t) async {
    await t.pumpWidget(rtl(const LtrText('5.5 - 19.5')));
    final p = para(t, '5.5');
    final first = p.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1)).first;
    final last = p.getBoxesForSelection(const TextSelection(baseOffset: 8, extentOffset: 9)).first;
    expect(first.left, lessThan(last.left));
  });
}
