import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../services/api.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../utils/results.dart';
import '../../widgets/glass.dart';

/// Lab staff enter results here ("ما از این ور پر می‌کنیم، اون اون‌ور می‌بینه").
class ResultEntryScreen extends StatefulWidget {
  final RecordModel order;
  const ResultEntryScreen({super.key, required this.order});
  @override
  State<ResultEntryScreen> createState() => _ResultEntryScreenState();
}

class _ResultEntryScreenState extends State<ResultEntryScreen> {
  List<TestResult> _results = [];
  final Map<String, TextEditingController> _ctrl = {};
  late final TextEditingController _comment = TextEditingController(text: widget.order.getStringValue('lab_comment'));
  bool _loading = true;
  bool _saving = false;
  List<RecordModel> _allTests = [];

  String get _species => widget.order.getStringValue('species');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _allTests = await Api.pb.collection('tests').getFullList(sort: 'sort,name');
      final existing = parseResults(widget.order.data['results']);
      final items = (widget.order.data['items'] as List? ?? []).cast<Map>();
      final byId = {for (final e in existing) e.test: e};
      final list = <TestResult>[];
      for (final i in items) {
        final id = '${i['test']}';
        list.add(byId[id] ?? _fromCatalog(id, fallbackName: '${i['name']}'));
      }
      // keep extra tests that were added earlier
      for (final e in existing) {
        if (!list.any((x) => x.test == e.test)) list.add(e);
      }
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
      setState(() => _loading = false);
    }
  }

  TestResult _fromCatalog(String id, {String fallbackName = ''}) {
    final t = _allTests.where((x) => x.id == id).firstOrNull;
    if (t == null) return TestResult(test: id, name: fallbackName);
    final params = (t.data['parameters'] as List? ?? []).map((p) {
      final m = Map<String, dynamic>.from(p as Map);
      final (lo, hi) = refFor(m, _species);
      return ParamResult(key: '${m['key']}', name: '${m['name']}', unit: '${m['unit'] ?? ''}', low: lo, high: hi);
    }).toList();
    return TestResult(
      test: t.id,
      name: t.getStringValue('name'),
      code: t.getStringValue('code'),
      category: t.getStringValue('category'),
      params: params,
    );
  }

  TextEditingController _c(String key, String initial) => _ctrl.putIfAbsent(key, () => TextEditingController(text: initial));

  void _collect() {
    for (final t in _results) {
      t.text = _c('${t.test}::text', t.text).text;
      for (final p in t.params) {
        p.value = enNum(_c('${t.test}::${p.key}', p.value).text.trim());
      }
    }
  }

  Future<void> _save({bool publish = false}) async {
    _collect();
    if (publish && !_results.any((t) => t.hasValues)) {
      toast(context, 'هیچ نتیجه‌ای وارد نشده است', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await Api.pb
          .collection('orders')
          .update(
            widget.order.id,
            body: {'results': encodeResults(_results), 'lab_comment': _comment.text.trim(), if (publish) 'status': 'ready'},
          );
      if (!mounted) return;
      toast(context, publish ? 'جواب منتشر شد و برای همکار اعلان ارسال شد' : 'ذخیره شد');
      if (publish) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addTest() async {
    final chosen = await showGlassSheet<RecordModel>(
      context,
      (c) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(12),
        children: [
          for (final t in _allTests.where((t) => !_results.any((r) => r.test == t.id)))
            ListTile(
              leading: Icon(categoryInfo(t.getStringValue('category')).icon),
              title: Text(t.getStringValue('name')),
              onTap: () => Navigator.pop(c, t),
            ),
        ],
      ),
    );
    if (chosen != null) setState(() => _results.add(_fromCatalog(chosen.id)));
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return MPScaffold(
      title: 'ورود جواب ${faNum(o.getStringValue('code'))}',
      actions: [IconButton(tooltip: 'افزودن آزمایش', onPressed: _addTest, icon: const Icon(Icons.playlist_add_rounded))],
      body: _loading
          ? const Loading()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                Glass(
                  child: Text(
                    '${o.getStringValue('pet_name')} • ${speciesLabels[_species] ?? ''} • ${o.getStringValue('breed')} • ${o.getStringValue('age')}\n'
                    'محدوده مرجع بر اساس گونه «${speciesLabels[_species] ?? 'سگ'}» پر شده است.',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 10),
                for (final t in _results) _testCard(t),
                const SectionTitle('تفسیر / توضیحات کلی'),
                TextField(
                  controller: _comment,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'تفسیر نتایج، توصیه‌ها...'),
                ),
              ],
            ),
      bottom: _loading
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : () => _save(),
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('ذخیره پیش‌نویس'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GradientButton(
                      label: 'انتشار جواب',
                      icon: Icons.send_rounded,
                      loading: _saving,
                      onPressed: () => _save(publish: true),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _testCard(TestResult t) {
    return Glass(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GlassIcon(categoryInfo(t.category).icon, color: categoryInfo(t.category).color, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final p in t.params) _paramRow(t, p),
          TextField(
            controller: _c('${t.test}::text', t.text),
            maxLines: t.params.isEmpty ? 5 : 2,
            decoration: InputDecoration(labelText: t.params.isEmpty ? 'گزارش / نتیجه' : 'توضیح (اختیاری)', alignLabelWithHint: true),
          ),
        ],
      ),
    );
  }

  Widget _paramRow(TestResult t, ParamResult p) {
    final c = _c('${t.test}::${p.key}', p.value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder(
          valueListenable: c,
          builder: (context, v, _) {
            final f = flagOf(enNum(v.text), p.low, p.high);
            final color = f == Flag.high
                ? MP.danger
                : f == Flag.low
                ? const Color(0xFF3F7FD0)
                : f == Flag.normal
                ? MP.success
                : null;
            return Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(p.range.isEmpty ? p.unit : '${p.range} ${p.unit}', style: const TextStyle(fontSize: 10.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: c,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: InputDecoration(
                      isDense: true,
                      suffixText: p.unit,
                      suffixIcon: f == Flag.high
                          ? const Icon(Icons.arrow_upward_rounded, color: MP.danger)
                          : f == Flag.low
                          ? const Icon(Icons.arrow_downward_rounded, color: Color(0xFF3F7FD0))
                          : f == Flag.normal
                          ? const Icon(Icons.check_rounded, color: MP.success)
                          : null,
                      enabledBorder: color == null
                          ? null
                          : OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(color: color),
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
