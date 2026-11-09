import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../services/api.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/form_bits.dart';
import '../../widgets/glass.dart';

/// Admin: the lab's test list and prices (one price per test; empty = by agreement).
class TestsScreen extends StatefulWidget {
  const TestsScreen({super.key});
  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  List<RecordModel>? _items;
  String _q = '';
  String _cat = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Api.pb.collection('tests').getFullList(sort: 'category,sort,name');
    if (mounted) setState(() => _items = r);
  }

  Future<void> _edit([RecordModel? t]) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => TestEditScreen(test: t)));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = (_items ?? [])
        .where((t) => _cat == 'all' || t.getStringValue('category') == _cat)
        .where(
          (t) => _q.isEmpty || t.getStringValue('name').toLowerCase().contains(_q) || t.getStringValue('code').toLowerCase().contains(_q),
        )
        .toList();
    return MPScaffold(
      title: 'آزمایش‌ها و تعرفه‌ها',
      fab: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('آزمایش جدید')),
      body: _items == null
          ? const Loading()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'جستجو'),
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final e in {'all': 'همه', for (final c in categories.entries) c.key: c.value.label}.entries)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: MPChoiceChip(label: e.value, selected: _cat == e.key, onSelected: (_) => setState(() => _cat = e.key)),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text('${faNum(list.length)} آزمایش', style: const TextStyle(fontSize: 12)),
                ),
                if (list.isEmpty) const EmptyState(icon: Icons.science_rounded, title: 'آزمایشی پیدا نشد'),
                for (final t in list)
                  Glass(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    onTap: () => _edit(t),
                    child: Row(
                      children: [
                        GlassIcon(
                          categoryInfo(t.getStringValue('category')).icon,
                          color: categoryInfo(t.getStringValue('category')).color,
                          size: 42,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(t.getStringValue('name'), style: const TextStyle(fontWeight: FontWeight.w800)),
                                  ),
                                  if (t.getStringValue('code').isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(start: 6),
                                      child: Text(
                                        t.getStringValue('code'),
                                        textDirection: TextDirection.ltr,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  if (!t.getBoolValue('active')) const Text('غیرفعال', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                priceText(t.getDoubleValue('price')),
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: readable(context, MP.pinkDeep)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class TestEditScreen extends StatefulWidget {
  final RecordModel? test;
  const TestEditScreen({super.key, this.test});
  @override
  State<TestEditScreen> createState() => _TestEditScreenState();
}

class _ParamDraft {
  final key = TextEditingController();
  final name = TextEditingController();
  final unit = TextEditingController();
  final dogLo = TextEditingController();
  final dogHi = TextEditingController();
  final catLo = TextEditingController();
  final catHi = TextEditingController();

  _ParamDraft();

  factory _ParamDraft.from(Map p) {
    final d = _ParamDraft();
    d.key.text = '${p['key'] ?? ''}';
    d.name.text = '${p['name'] ?? ''}';
    d.unit.text = '${p['unit'] ?? ''}';
    final ref = (p['ref'] as Map?) ?? {};
    String s(dynamic v) => v == null ? '' : (v is num && v == v.roundToDouble() ? '${v.toInt()}' : '$v');
    if (ref['dog'] is List) {
      d.dogLo.text = s(ref['dog'][0]);
      d.dogHi.text = s(ref['dog'][1]);
    }
    if (ref['cat'] is List) {
      d.catLo.text = s(ref['cat'][0]);
      d.catHi.text = s(ref['cat'][1]);
    }
    return d;
  }

  Map<String, dynamic> toJson() {
    double? n(TextEditingController c) => double.tryParse(enNum(c.text.trim()));
    final ref = <String, dynamic>{};
    if (n(dogLo) != null || n(dogHi) != null) ref['dog'] = [n(dogLo), n(dogHi)];
    if (n(catLo) != null || n(catHi) != null) ref['cat'] = [n(catLo), n(catHi)];
    final k = key.text.trim().isEmpty ? name.text.trim().toLowerCase().replaceAll(' ', '_') : key.text.trim();
    return {'key': k, 'name': name.text.trim(), 'unit': unit.text.trim(), 'ref': ref};
  }
}

class _TestEditScreenState extends State<TestEditScreen> {
  RecordModel? get t => widget.test;
  late final name = TextEditingController(text: t?.getStringValue('name'));
  late final code = TextEditingController(text: t?.getStringValue('code'));
  late final sample = TextEditingController(text: t?.getStringValue('sample_type'));
  late final hours = TextEditingController(text: _num(t?.getDoubleValue('turnaround_hours')));
  late final desc = TextEditingController(text: t?.getStringValue('description'));
  late final price = TextEditingController(text: _num(t?.getDoubleValue('price')));
  late String category = t?.getStringValue('category') ?? 'biochemistry';
  late bool active = t?.getBoolValue('active') ?? true;
  late final List<_ParamDraft> params = ((t?.data['parameters'] as List?) ?? []).map((p) => _ParamDraft.from(p as Map)).toList();
  final _form = GlobalKey<FormState>();
  bool _saving = false;

  static String _num(double? v) => v == null || v == 0 ? '' : (v == v.roundToDouble() ? '${v.toInt()}' : '$v');

  Future<void> _save() async {
    if (!validateForm(context, _form)) return;
    setState(() => _saving = true);
    try {
      final body = {
        'name': name.text.trim(),
        'code': code.text.trim(),
        'category': category,
        'sample_type': sample.text.trim(),
        'turnaround_hours': double.tryParse(enNum(hours.text)) ?? 0,
        'description': desc.text.trim(),
        'price': double.tryParse(enNum(price.text.replaceAll(RegExp(r'[,٬\s]'), ''))) ?? 0,
        'active': active,
        'parameters': params.where((p) => p.name.text.trim().isNotEmpty).map((p) => p.toJson()).toList(),
      };
      if (t == null) {
        await Api.pb.collection('tests').create(body: body);
      } else {
        await Api.pb.collection('tests').update(t!.id, body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      'حذف آزمایش',
      '«${t!.getStringValue('name')}» از لیست حذف شود؟ سفارش‌های قبلی که این آزمایش را داشته‌اند تغییری نمی‌کنند. برای پنهان‌کردن موقت، به‌جای حذف آن را غیرفعال کنید.',
      ok: 'حذف',
    );
    if (!ok) return;
    try {
      await Api.pb.collection('tests').delete(t!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MPScaffold(
      title: t == null ? 'آزمایش جدید' : 'ویرایش آزمایش',
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            Field(name, 'نام آزمایش', required: true),
            Row(
              children: [
                Expanded(child: Field(code, 'کد (مثلا ALT)', ltr: true)),
                const SizedBox(width: 10),
                Expanded(child: Field(hours, 'زمان جوابدهی (ساعت)', keyboard: TextInputType.number)),
              ],
            ),
            Field(sample, 'نوع نمونه', hint: 'سرم، خون کامل EDTA، ...'),
            const Text('بخش', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ChoiceRow(
              options: {for (final e in categories.entries) e.key: e.value.label},
              value: category,
              onChanged: (v) => setState(() => category = v),
            ),
            Field(price, 'قیمت ($kCurrency) — خالی = توافقی', icon: Icons.payments_rounded, ltr: true, keyboard: TextInputType.number),
            SwitchListTile(value: active, onChanged: (v) => setState(() => active = v), title: const Text('فعال')),
            Field(desc, 'توضیحات', maxLines: 2),
            SectionTitle('پارامترها و محدوده مرجع', action: 'افزودن', onAction: () => setState(() => params.add(_ParamDraft()))),
            for (var i = 0; i < params.length; i++) _paramCard(i),
            const SizedBox(height: 12),
            GradientButton(label: 'ذخیره', icon: Icons.save_rounded, loading: _saving, onPressed: _save),
            if (t != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _delete,
                icon: Icon(Icons.delete_outline_rounded, color: readable(context, MP.danger)),
                label: Text('حذف این آزمایش', style: TextStyle(color: readable(context, MP.danger))),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paramCard(int i) {
    final p = params[i];
    Widget small(TextEditingController c, String label) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: TextField(
          controller: c,
          textDirection: TextDirection.ltr,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      ),
    );
    return Glass(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            children: [
              small(p.name, 'نام'),
              small(p.unit, 'واحد'),
              IconButton(onPressed: () => setState(() => params.removeAt(i)), icon: const Icon(Icons.delete_outline_rounded)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              small(p.dogLo, 'سگ: حداقل'),
              small(p.dogHi, 'سگ: حداکثر'),
              small(p.catLo, 'گربه: حداقل'),
              small(p.catHi, 'گربه: حداکثر'),
            ],
          ),
        ],
      ),
    );
  }
}
