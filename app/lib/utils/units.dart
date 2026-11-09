/// Lab units such as "×10³/µL" or "×10^6/µL" split into plain text and exponent parts, so they can be
/// drawn with a real superscript (a font without "⁶" would otherwise show an empty box) and always
/// read left-to-right (in a right-to-left screen "×10³/µL" would come out as "µL/10³×").
library;

class UnitPart {
  final String text;
  final bool sup;
  const UnitPart(this.text, {this.sup = false});
  @override
  String toString() => sup ? '^$text' : text;
}

const _supDigits = {'⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9', '⁻': '-'};

// "10" followed by an exponent written as superscript characters or as ^n
final _exp = RegExp(r'(?<=10)(?:\^\s*(-?\d+)|([⁰¹²³⁴⁵⁶⁷⁸⁹⁻]+))');

List<UnitPart> parseUnit(String unit) {
  final parts = <UnitPart>[];
  var last = 0;
  for (final m in _exp.allMatches(unit)) {
    if (m.start > last) parts.add(UnitPart(unit.substring(last, m.start)));
    final e = m.group(1) ?? m.group(2)!.split('').map((c) => _supDigits[c] ?? c).join();
    parts.add(UnitPart(e, sup: true));
    last = m.end;
  }
  if (last < unit.length) parts.add(UnitPart(unit.substring(last)));
  return parts.isEmpty ? [const UnitPart('')] : parts;
}

/// Plain-text form for places without rich text (Excel): "×10^6/µL".
String unitPlain(String unit) => parseUnit(unit).map((p) => p.toString()).join();
