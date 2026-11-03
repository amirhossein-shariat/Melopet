/// Result data model shared by the admin entry screen, the clinic result
/// view and the PDF / Excel exporters.
///
/// Stored in `orders.results` as a self-contained snapshot so the clinic
/// never needs read access to the (price-bearing) tests catalog:
/// {
///   "tests": [
///     {"test": id, "name": "...", "code": "...", "category": "...",
///      "text": "free text / interpretation",
///      "params": [{"key","name","unit","low","high","value"}]}
///   ]
/// }
library;

enum Flag { normal, low, high, none }

class ParamResult {
  final String key;
  final String name;
  final String unit;
  final double? low;
  final double? high;
  String value;

  ParamResult({required this.key, required this.name, this.unit = '', this.low, this.high, this.value = ''});

  factory ParamResult.fromJson(Map<String, dynamic> j) => ParamResult(
    key: '${j['key'] ?? ''}',
    name: '${j['name'] ?? ''}',
    unit: '${j['unit'] ?? ''}',
    low: _d(j['low']),
    high: _d(j['high']),
    value: '${j['value'] ?? ''}',
  );

  Map<String, dynamic> toJson() => {'key': key, 'name': name, 'unit': unit, 'low': low, 'high': high, 'value': value};

  Flag get flag => flagOf(value, low, high);

  String get range {
    if (low == null && high == null) return '';
    return '${_fmt(low)} - ${_fmt(high)}';
  }
}

class TestResult {
  final String test;
  final String name;
  final String code;
  final String category;
  String text;
  final List<ParamResult> params;

  TestResult({required this.test, required this.name, this.code = '', this.category = '', this.text = '', List<ParamResult>? params})
    : params = params ?? [];

  factory TestResult.fromJson(Map<String, dynamic> j) => TestResult(
    test: '${j['test'] ?? ''}',
    name: '${j['name'] ?? ''}',
    code: '${j['code'] ?? ''}',
    category: '${j['category'] ?? ''}',
    text: '${j['text'] ?? ''}',
    params: ((j['params'] as List?) ?? []).map((e) => ParamResult.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
  );

  Map<String, dynamic> toJson() => {
    'test': test,
    'name': name,
    'code': code,
    'category': category,
    'text': text,
    'params': params.map((e) => e.toJson()).toList(),
  };

  bool get hasValues => text.trim().isNotEmpty || params.any((p) => p.value.trim().isNotEmpty);
}

List<TestResult> parseResults(dynamic raw) {
  if (raw is Map && raw['tests'] is List) {
    return (raw['tests'] as List).map((e) => TestResult.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
  return [];
}

Map<String, dynamic> encodeResults(List<TestResult> list) => {'tests': list.map((e) => e.toJson()).toList()};

Flag flagOf(String value, double? low, double? high) {
  final v = double.tryParse(value.trim().replaceAll(',', '.'));
  if (v == null) return Flag.none;
  if (low != null && v < low) return Flag.low;
  if (high != null && v > high) return Flag.high;
  if (low == null && high == null) return Flag.none;
  return Flag.normal;
}

/// Reference range of a catalog parameter for a species; falls back to dog.
(double?, double?) refFor(Map<String, dynamic> param, String species) {
  final ref = param['ref'];
  if (ref is! Map) return (null, null);
  final r = ref[species] ?? (species == 'cat' ? null : ref['dog']);
  if (r is List && r.length == 2) return (_d(r[0]), _d(r[1]));
  return (null, null);
}

double? _d(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

String _fmt(double? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
