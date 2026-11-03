import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/catalog.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/form_bits.dart';
import '../../widgets/glass.dart';

/// "درخواست پیک": choose tests + patient info → the lab dispatches a courier.
class CourierRequestScreen extends StatefulWidget {
  /// Admins can create an order on behalf of a clinic.
  final String? clinicId;
  const CourierRequestScreen({super.key, this.clinicId});
  @override
  State<CourierRequestScreen> createState() => _CourierRequestScreenState();
}

class _CourierRequestScreenState extends State<CourierRequestScreen> {
  List<CatalogItem> _catalog = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String _query = '';

  final _form = GlobalKey<FormState>();
  final pet = TextEditingController();
  final breed = TextEditingController();
  final age = TextEditingController();
  final weight = TextEditingController();
  final owner = TextEditingController();
  final fileNo = TextEditingController();
  final notes = TextEditingController();
  final pickupAddress = TextEditingController();
  String species = 'dog';
  String sex = 'unknown';
  bool urgent = false;
  bool fasting = false;
  bool onlyCourier = false;
  String pickupTime = 'همین حالا';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _catalog = await Catalog.load(clinicId: widget.clinicId);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = Api.error(e);
        });
      }
    }
  }

  num get _total => _catalog.where((c) => _selected.contains(c.id)).fold<num>(0, (s, c) => s + c.price);

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_selected.isEmpty && !onlyCourier) {
      toast(context, 'حداقل یک آزمایش انتخاب کنید یا گزینه «فقط ارسال پیک» را فعال کنید', error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      await Api.pb.send(
        '/api/melopet/orders',
        method: 'POST',
        body: {
          if (widget.clinicId != null) 'clinic': widget.clinicId,
          'tests': _selected.toList(),
          'pet_name': pet.text.trim(),
          'species': species,
          'breed': breed.text.trim(),
          'age': age.text.trim(),
          'sex': sex,
          'weight': double.tryParse(enNum(weight.text.trim())) ?? 0,
          'owner_name': owner.text.trim(),
          'file_no': enNum(fileNo.text.trim()),
          'urgent': urgent,
          'fasting': fasting,
          'pickup_time': pickupTime,
          'pickup_address': pickupAddress.text.trim(),
          'clinical_notes': notes.text.trim(),
        },
      );
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          icon: const GlassIcon(Icons.check_rounded, color: MP.success, size: 64),
          title: const Text('درخواست ثبت شد'),
          content: const Text(
            'همکاران ما به زودی پیک را اعزام می‌کنند. وضعیت سفارش را از بخش سفارش‌ها دنبال کنید.',
            textAlign: TextAlign.center,
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('باشه'))],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MPScaffold(
      title: 'درخواست پیک',
      body: _loading
          ? const Loading()
          : _error != null
          ? ErrorView(_error!, onRetry: _load)
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
                children: [
                  const SectionTitle('۱. انتخاب آزمایش‌ها'),
                  TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'جستجوی آزمایش (مثلا CBC)'),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 10),
                  ..._testGroups(),
                  CheckboxListTile(
                    value: onlyCourier,
                    onChanged: (v) => setState(() => onlyCourier = v ?? false),
                    title: const Text('فقط ارسال پیک (آزمایش‌ها را بعدا در چت هماهنگ می‌کنم)'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SectionTitle('۲. مشخصات بیمار'),
                  Glass(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('گونه', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ChoiceRow(options: speciesLabels, value: species, onChanged: (v) => setState(() => species = v)),
                        const SizedBox(height: 14),
                        Field(pet, 'نام حیوان', icon: Icons.pets_rounded, required: true),
                        Row(
                          children: [
                            Expanded(child: Field(breed, 'نژاد')),
                            const SizedBox(width: 10),
                            Expanded(child: Field(age, 'سن', hint: 'مثلا ۳ سال')),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(child: Field(weight, 'وزن (kg)', keyboard: TextInputType.number)),
                            const SizedBox(width: 10),
                            Expanded(child: Field(fileNo, 'شماره پرونده')),
                          ],
                        ),
                        Field(owner, 'نام صاحب حیوان', icon: Icons.person_rounded),
                        const Text('جنس', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ChoiceRow(options: sexLabels, value: sex, onChanged: (v) => setState(() => sex = v)),
                      ],
                    ),
                  ),
                  const SectionTitle('۳. نمونه و پیک'),
                  Glass(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: urgent,
                          onChanged: (v) => setState(() => urgent = v),
                          title: const Text('فوری (اورژانسی)'),
                          secondary: const Icon(Icons.bolt_rounded, color: MP.danger),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: fasting,
                          onChanged: (v) => setState(() => fasting = v),
                          title: const Text('نمونه ناشتا گرفته شده'),
                          secondary: const Icon(Icons.no_food_rounded),
                        ),
                        const SizedBox(height: 6),
                        const Text('زمان مراجعه پیک', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ChoiceRow(
                          options: const {
                            'همین حالا': 'همین حالا',
                            'تا ۱ ساعت دیگر': 'تا ۱ ساعت دیگر',
                            'عصر امروز': 'عصر امروز',
                            'فردا صبح': 'فردا صبح',
                          },
                          value: pickupTime,
                          onChanged: (v) => setState(() => pickupTime = v),
                        ),
                        const SizedBox(height: 14),
                        Field(
                          pickupAddress,
                          'آدرس دریافت نمونه',
                          icon: Icons.location_on_rounded,
                          hint: 'خالی = آدرس ثبت‌شده مرکز',
                          maxLines: 2,
                        ),
                        Field(
                          notes,
                          'توضیحات بالینی / شرح حال',
                          icon: Icons.notes_rounded,
                          maxLines: 3,
                          hint: 'علائم، داروهای مصرفی، تشخیص افتراقی...',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      bottom: _loading || _error != null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Glass(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${faNum(_selected.length)} آزمایش', style: const TextStyle(fontSize: 12)),
                          Text(money(_total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: GradientButton(label: 'ارسال پیک', icon: Icons.delivery_dining_rounded, loading: _sending, onPressed: _submit),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _testGroups() {
    final filtered = _catalog
        .where((c) => _query.isEmpty || c.name.toLowerCase().contains(_query) || c.code.toLowerCase().contains(_query))
        .toList();
    final groups = <String, List<CatalogItem>>{};
    for (final c in filtered) {
      groups.putIfAbsent(c.category, () => []).add(c);
    }
    if (groups.isEmpty) {
      return [const Padding(padding: EdgeInsets.all(16), child: Text('آزمایشی یافت نشد'))];
    }
    return [
      for (final g in groups.entries)
        Glass(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
                child: Row(
                  children: [
                    Icon(categoryInfo(g.key).icon, color: categoryInfo(g.key).color, size: 20),
                    const SizedBox(width: 6),
                    Text(categoryInfo(g.key).label, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              for (final c in g.value)
                CheckboxListTile(
                  value: _selected.contains(c.id),
                  onChanged: (v) => setState(() => v == true ? _selected.add(c.id) : _selected.remove(c.id)),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: c.sampleType.isNotEmpty ? Text('نمونه: ${c.sampleType}') : null,
                  secondary: Text(money(c.price, unit: false), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
    ];
  }
}
