import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api.dart';
import '../../services/catalog.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/form_bits.dart';
import '../../widgets/glass.dart';
import '../../widgets/location.dart';
import '../../widgets/voice.dart';

/// "درخواست پیک" in two steps:
///  1. case info (owner, animal, ...) + case history as text and/or voice — required
///  2. choose the lab tests (list + search) → send; the lab gets a notification.
class CourierRequestScreen extends StatefulWidget {
  /// Admins can create an order on behalf of a clinic.
  final String? clinicId;
  const CourierRequestScreen({super.key, this.clinicId});
  @override
  State<CourierRequestScreen> createState() => _CourierRequestScreenState();
}

class _CourierRequestScreenState extends State<CourierRequestScreen> {
  int _step = 0;

  // ---- step 1: case
  final _form = GlobalKey<FormState>();
  final owner = TextEditingController();
  final pet = TextEditingController();
  final breed = TextEditingController();
  final age = TextEditingController();
  final weight = TextEditingController();
  final fileNo = TextEditingController();
  final history = TextEditingController();
  final pickupAddress = TextEditingController();
  String? species;
  String sex = 'unknown';
  bool urgent = false;
  bool fasting = false;
  String pickupTime = 'همین حالا';
  VoiceClip? voice;
  LatLng? location;
  bool _historyError = false;
  bool _speciesError = false;

  // ---- step 2: tests
  List<CatalogItem> _catalog = [];
  final Set<String> _selected = {};
  bool _loadingCatalog = true;
  String? _catalogError;
  String _query = '';
  String? _category;
  final _search = TextEditingController();

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    if (widget.clinicId == null) {
      location = geoOf(Api.me, 'location');
    } else {
      Api.pb
          .collection('users')
          .getOne(widget.clinicId!)
          .then((c) {
            if (mounted) setState(() => location = geoOf(c, 'location'));
          })
          .catchError((_) {});
    }
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });
    try {
      _catalog = await Catalog.load(clinicId: widget.clinicId);
      if (mounted) setState(() => _loadingCatalog = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingCatalog = false;
          _catalogError = Api.error(e);
        });
      }
    }
  }

  num get _total => _catalog.where((c) => _selected.contains(c.id)).fold<num>(0, (s, c) => s + c.price);

  void _next() {
    final okForm = _form.currentState!.validate();
    setState(() {
      _speciesError = species == null;
      _historyError = history.text.trim().isEmpty && voice == null;
    });
    if (!okForm || _speciesError || _historyError) {
      toast(context, _historyError ? 'تاریخچه کیس را بنویسید یا ویس آن را ضبط کنید' : 'موارد ستاره‌دار را کامل کنید', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step = 1);
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      final ok = await confirm(
        context,
        'بدون انتخاب آزمایش',
        'هیچ فاکتوری انتخاب نشده. پیک ارسال شود و آزمایش‌ها در چت هماهنگ شود؟',
        ok: 'ارسال پیک',
      );
      if (!ok) return;
    }
    setState(() => _sending = true);
    try {
      final payload = {
        'clinic': ?widget.clinicId,
        'tests': _selected.toList(),
        'owner_name': owner.text.trim(),
        'pet_name': pet.text.trim(),
        'species': species,
        'breed': breed.text.trim(),
        'age': age.text.trim(),
        'sex': sex,
        'weight': double.tryParse(enNum(weight.text.trim())) ?? 0,
        'file_no': enNum(fileNo.text.trim()),
        'urgent': urgent,
        'fasting': fasting,
        'pickup_time': pickupTime,
        'pickup_address': pickupAddress.text.trim(),
        'clinical_notes': history.text.trim(),
        if (voice != null) 'history_voice_seconds': voice!.seconds,
        if (location != null) 'lat': location!.latitude,
        if (location != null) 'lon': location!.longitude,
      };
      if (voice != null) {
        await Api.pb.send('/api/melopet/orders', method: 'POST', body: payload, files: [voice!.file.toMultipart('history_voice')]);
      } else {
        await Api.pb.send('/api/melopet/orders', method: 'POST', body: payload);
      }
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          icon: const GlassIcon(Icons.delivery_dining_rounded, color: MP.success, size: 64),
          title: const Text('درخواست پیک ثبت شد'),
          content: const Text(
            'آزمایشگاه ملوپت مطلع شد و به زودی پیک اعزام می‌شود. وضعیت را از بخش سفارش‌ها دنبال کنید.',
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
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (did, _) {
        if (!did) setState(() => _step = 0);
      },
      child: MPScaffold(
        title: 'درخواست پیک',
        body: Column(
          children: [
            _StepHeader(step: _step),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: _step == 0
                    ? KeyedSubtree(key: const ValueKey(0), child: _caseStep())
                    : KeyedSubtree(key: const ValueKey(1), child: _testsStep()),
              ),
            ),
          ],
        ),
        bottom: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _step == 0
              ? GradientButton(label: 'مرحله بعد: انتخاب فاکتورها', icon: Icons.arrow_forward_rounded, onPressed: _next)
              : Glass(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => setState(() => _step = 0),
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'مرحله قبل',
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${faNum(_selected.length)} فاکتور', style: const TextStyle(fontSize: 12)),
                            Text(money(_total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: GradientButton(
                          label: 'ارسال پیک',
                          icon: Icons.delivery_dining_rounded,
                          loading: _sending,
                          onPressed: _submit,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ step 1
  Widget _caseStep() {
    final cs = Theme.of(context).colorScheme;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const SectionTitle('اطلاعات کیس'),
          Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Field(owner, 'نام صاحب حیوان', icon: Icons.person_rounded, required: true),
                Field(pet, 'نام حیوان', icon: Icons.pets_rounded, required: true),
                Text(
                  'نوع حیوان *',
                  style: TextStyle(fontWeight: FontWeight.w700, color: _speciesError ? MP.danger : null),
                ),
                const SizedBox(height: 8),
                ChoiceRow(
                  options: speciesLabels,
                  value: species,
                  onChanged: (v) => setState(() {
                    species = v;
                    _speciesError = false;
                  }),
                ),
                const SizedBox(height: 14),
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
                const Text('جنس', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ChoiceRow(options: sexLabels, value: sex, onChanged: (v) => setState(() => sex = v)),
              ],
            ),
          ),
          const SectionTitle('تاریخچه کیس (History) *'),
          Glass(
            tint: _historyError ? MP.danger.withValues(alpha: .08) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'شرح حال، علائم، داروهای مصرفی و تشخیص احتمالی را بنویسید یا ویس بگیرید. حداقل یکی الزامی است.',
                  style: TextStyle(fontSize: 12.5, color: _historyError ? MP.danger : cs.onSurface.withValues(alpha: .7)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: history,
                  maxLines: 5,
                  minLines: 3,
                  onChanged: (_) {
                    if (_historyError) setState(() => _historyError = false);
                  },
                  decoration: const InputDecoration(
                    hintText: 'مثلا: استفراغ و بی‌اشتهایی از ۳ روز قبل، تب ۳۹.۸...',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: Divider(color: cs.onSurface.withValues(alpha: .15))),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('و / یا', style: TextStyle(fontSize: 12)),
                    ),
                    Expanded(child: Divider(color: cs.onSurface.withValues(alpha: .15))),
                  ],
                ),
                const SizedBox(height: 10),
                VoiceRecorderField(
                  value: voice,
                  onChanged: (v) => setState(() {
                    voice = v;
                    if (v != null) _historyError = false;
                  }),
                ),
              ],
            ),
          ),
          const SectionTitle('نمونه و پیک'),
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
                LocationField(title: 'محل دریافت نمونه', value: location, onChanged: (p) => setState(() => location = p)),
                Field(
                  pickupAddress,
                  'توضیح آدرس (اختیاری)',
                  icon: Icons.location_on_rounded,
                  hint: 'خالی = آدرس ثبت‌شده مرکز',
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ step 2
  Widget _testsStep() {
    if (_loadingCatalog) return const Loading();
    if (_catalogError != null) return ErrorView(_catalogError!, onRetry: _loadCatalog);

    final q = _query.toLowerCase();
    final filtered = _catalog.where((c) {
      if (_category != null && c.category != _category) return false;
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) || c.code.toLowerCase().contains(q) || categoryInfo(c.category).label.contains(q);
    }).toList();
    final cats = _catalog.map((c) => c.category).toSet().toList();
    final selected = _catalog.where((c) => _selected.contains(c.id)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: TextField(
            controller: _search,
            autofocus: false,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'جستجوی فاکتور: نام یا کد (مثلا CBC، ALT، قند)',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    ),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: MPChoiceChip(label: 'همه', selected: _category == null, onSelected: (_) => setState(() => _category = null)),
              ),
              for (final c in cats)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: MPChoiceChip(
                    avatar: Icon(categoryInfo(c).icon, size: 16, color: readable(context, categoryInfo(c).color)),
                    label: categoryInfo(c).label,
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = _category == c ? null : c),
                  ),
                ),
            ],
          ),
        ),
        if (selected.isNotEmpty)
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              children: [
                for (final c in selected)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: InputChip(
                      label: Text(
                        c.code.isNotEmpty ? c.code : c.name,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600),
                      ),
                      deleteIconColor: Theme.of(context).colorScheme.onSurface,
                      onDeleted: () => setState(() => _selected.remove(c.id)),
                      backgroundColor: MP.pink.withValues(alpha: .25),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyState(icon: Icons.search_off_rounded, title: 'فاکتوری پیدا نشد')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    final on = _selected.contains(c.id);
                    final info = categoryInfo(c.category);
                    return Glass(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      tint: on ? MP.pink.withValues(alpha: .22) : null,
                      onTap: () => setState(() => on ? _selected.remove(c.id) : _selected.add(c.id)),
                      child: Row(
                        children: [
                          Checkbox(value: on, onChanged: (v) => setState(() => v == true ? _selected.add(c.id) : _selected.remove(c.id))),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(
                                  [info.label, if (c.sampleType.isNotEmpty) c.sampleType].join(' • '),
                                  style: TextStyle(fontSize: 11.5, color: readable(context, info.color)),
                                ),
                              ],
                            ),
                          ),
                          Text(money(c.price, unit: false), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int step;
  const _StepHeader({required this.step});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget dot(int i, String label, IconData icon) {
      final active = step >= i;
      return Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: active ? cs.primary : cs.primary.withValues(alpha: .15),
              child: Icon(step > i ? Icons.check_rounded : icon, size: 16, color: active ? cs.onPrimary : cs.primary),
            ),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: step == i ? FontWeight.w900 : FontWeight.w500, fontSize: 13)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Glass(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            dot(0, '۱. اطلاعات کیس', Icons.pets_rounded),
            Container(width: 24, height: 2, color: step > 0 ? cs.primary : cs.primary.withValues(alpha: .2)),
            dot(1, '۲. فاکتورها', Icons.science_rounded),
          ],
        ),
      ),
    );
  }
}
