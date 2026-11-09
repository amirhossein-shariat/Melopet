import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api.dart';
import '../../services/catalog.dart';
import '../../services/delivery.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/delivery_options.dart';
import '../../widgets/form_bits.dart';
import '../../widgets/glass.dart';
import '../../widgets/location.dart';
import '../../widgets/voice.dart';

/// "درخواست پیک" in three steps:
///  1. case info (owner, animal, ...) + case history as text and/or voice — required
///  2. choose the lab tests (list + search)
///  3. delivery: free (next courier round, ≤ 4 h) or urgent (quoted fee added to the total) → send
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
  bool fasting = false;
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

  // ---- step 3: delivery + discount code
  final _promoField = TextEditingController();
  PromoApplied? _promo;
  bool _checkingPromo = false;
  String? _promoError;
  String _delivery = 'standard';
  DeliveryOptionsData? _opts;
  bool _quoting = false;

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
      _catalog = await Catalog.load();
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

  num get _deliveryFee => _delivery == 'urgent' && (_opts?.urgentAvailable ?? false) ? _opts!.urgentFee : 0;
  num get _discount => _promo?.discount ?? 0;
  num get _grandTotal => _total - _discount + _deliveryFee;

  Future<void> _applyPromo({bool silent = false}) async {
    final code = _promoField.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _checkingPromo = true;
      _promoError = null;
    });
    try {
      final p = await PromoApplied.check(code, _selected.toList());
      if (mounted) setState(() => _promo = p);
      if (mounted && !silent) toast(context, 'کد ${p.code} اعمال شد: ${faNum(p.percent)}٪ تخفیف');
    } catch (e) {
      if (mounted) {
        setState(() {
          _promo = null;
          _promoError = Api.error(e);
        });
      }
    } finally {
      if (mounted) setState(() => _checkingPromo = false);
    }
  }

  void _removePromo() => setState(() {
    _promo = null;
    _promoError = null;
    _promoField.clear();
  });

  Future<void> _loadQuote() async {
    setState(() => _quoting = true);
    try {
      final o = await DeliveryOptionsData.fetch(clinicId: widget.clinicId, lat: location?.latitude, lon: location?.longitude);
      if (mounted) {
        setState(() {
          _opts = o;
          if (!o.urgentAvailable) _delivery = 'standard';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _opts = null);
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _toDelivery() async {
    if (_selected.isEmpty) {
      final ok = await confirm(
        context,
        'بدون انتخاب آزمایش',
        'هیچ فاکتوری انتخاب نشده. ادامه می‌دهید و آزمایش‌ها در چت هماهنگ شود؟',
        ok: 'ادامه',
      );
      if (!ok) return;
    }
    setState(() => _step = 2);
    if (_opts == null || _opts!.stale) _loadQuote();
    // the tests may have changed since the code was applied: let the server re-price it
    if (_promo != null) _applyPromo(silent: true);
  }

  bool get _hasNegotiable => _catalog.any((c) => _selected.contains(c.id) && c.price <= 0);
  num get _total => _catalog.where((c) => _selected.contains(c.id)).fold<num>(0, (s, c) => s + c.price);

  final _speciesKey = GlobalKey();
  final _historyKey = GlobalKey();

  void _next() {
    final okForm = validateForm(context, _form);
    setState(() {
      _speciesError = species == null;
      _historyError = history.text.trim().isEmpty && voice == null;
    });
    // the form check already told the user about missing text fields and scrolled to the first;
    // the choice / history parts are not form fields, so report them the same way
    if (okForm && (_speciesError || _historyError)) {
      toast(context, _speciesError ? 'نوع حیوان را انتخاب کنید' : 'تاریخچه کیس را بنویسید یا ویس آن را ضبط کنید', error: true);
      final target = _speciesError ? _speciesKey : _historyKey;
      if (target.currentContext != null) {
        Scrollable.ensureVisible(
          target.currentContext!,
          alignment: .15,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    }
    if (!okForm || _speciesError || _historyError) return;
    FocusScope.of(context).unfocus();
    setState(() => _step = 1);
  }

  Future<void> _submit() async {
    if (_delivery == 'urgent' && (_opts == null || _opts!.stale)) {
      await _loadQuote();
      if (!mounted) return;
      if (_delivery == 'urgent') {
        toast(context, 'قیمت پیک فوری به‌روز شد؛ مبلغ نهایی را بررسی و دوباره تایید کنید.');
        return;
      }
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
        'delivery': _delivery,
        if (_delivery == 'urgent') 'delivery_quote': _opts!.quote,
        if (_promo != null) 'promo_code': _promo!.code,
        'fasting': fasting,
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
          content: Text(
            _delivery == 'urgent'
                ? 'آزمایشگاه ملوپت مطلع شد و پیک فوری اعزام می‌شود. وضعیت را از بخش سفارش‌ها دنبال کنید.'
                : 'آزمایشگاه ملوپت مطلع شد. پیک در دور بعدی (حداکثر تا ${faNum(_opts?.windowHours ?? 4)} ساعت دیگر) می‌آید. وضعیت را از بخش سفارش‌ها دنبال کنید.',
            textAlign: TextAlign.center,
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('باشه'))],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        toast(context, Api.error(e), error: true);
        if (_delivery == 'urgent') _loadQuote();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (did, _) {
        if (!did) setState(() => _step--);
      },
      child: MPScaffold(
        title: 'درخواست پیک',
        body: Column(
          children: [
            _StepHeader(step: _step),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: switch (_step) {
                  0 => KeyedSubtree(key: const ValueKey(0), child: _caseStep()),
                  1 => KeyedSubtree(key: const ValueKey(1), child: _testsStep()),
                  _ => KeyedSubtree(key: const ValueKey(2), child: _deliveryStep()),
                },
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
                        onPressed: () => setState(() => _step--),
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'مرحله قبل',
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _step == 1
                                  ? '${faNum(_selected.length)} فاکتور${_hasNegotiable ? ' • شامل مورد توافقی' : ''}'
                                  : (_deliveryFee > 0 ? 'شامل ${money(_deliveryFee)} هزینه پیک' : 'ارسال رایگان'),
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              money(_step == 1 ? _total : _grandTotal),
                              key: const Key('grand-total'),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: _step == 1
                            ? GradientButton(label: 'نحوه ارسال', icon: Icons.arrow_forward_rounded, onPressed: _toDelivery)
                            : GradientButton(
                                label: 'ثبت و ارسال پیک',
                                icon: Icons.delivery_dining_rounded,
                                loading: _sending,
                                onPressed: _quoting ? null : _submit,
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
                  key: _speciesKey,
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
          SectionTitle('تاریخچه کیس (History) *', key: _historyKey),
          Glass(
            tint: _historyError ? MP.danger.withValues(alpha: .08) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'شرح حال، علائم، داروهای مصرفی و تشخیص احتمالی را بنویسید یا ویس بگیرید. حداقل یکی الزامی است.',
                  style: TextStyle(fontSize: 12.5, color: _historyError ? MP.danger : cs.onSurface.withValues(alpha: .78)),
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
          const SectionTitle('نمونه و محل دریافت'),
          Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: fasting,
                  onChanged: (v) => setState(() => fasting = v),
                  title: const Text('نمونه ناشتا گرفته شده'),
                  secondary: const Icon(Icons.no_food_rounded),
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
                          Text(priceText(c.price, unit: false), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ step 3
  Widget _promoBox() {
    final p = _promo;
    return Glass(
      child: p != null
          ? Row(
              children: [
                Icon(Icons.local_offer_rounded, color: readable(context, MP.success)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'کد ${p.code} اعمال شد',
                        key: const Key('promo-applied'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${faNum(p.percent)}٪ تخفیف روی آزمایش‌ها • ${money(p.discount)}',
                        style: TextStyle(fontSize: 12, color: readable(context, MP.success), fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                IconButton(tooltip: 'حذف کد', onPressed: _removePromo, icon: const Icon(Icons.close_rounded)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('promo-field'),
                        controller: _promoField,
                        textDirection: TextDirection.ltr,
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _applyPromo(),
                        decoration: InputDecoration(
                          hintText: 'کد تخفیف دارید؟ وارد کنید',
                          prefixIcon: const Icon(Icons.local_offer_outlined),
                          errorText: _promoError,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: FilledButton(
                        key: const Key('promo-apply'),
                        onPressed: _checkingPromo ? null : _applyPromo,
                        child: _checkingPromo
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                            : const Text('اعمال'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'کدهای تخفیف را در بخش «پیشنهادها» ببینید؛ تخفیف روی آزمایش‌ها اعمال می‌شود، نه هزینه پیک.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
    );
  }

  Widget _deliveryStep() {
    final selected = _catalog.where((c) => _selected.contains(c.id)).toList();
    Widget line(String label, String value, {bool strong = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w500)),
          ),
          Text(
            value,
            style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w700, fontSize: strong ? 16 : 14, color: color),
          ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        const SectionTitle('نحوه ارسال'),
        DeliveryOptions(
          data: _opts,
          loading: _quoting,
          value: _delivery,
          onChanged: (v) => setState(() => _delivery = v),
          onRetry: _loadQuote,
        ),
        if (_opts != null && !_opts!.urgentAvailable && _opts!.urgentReason == 'location')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              onPressed: () => setState(() => _step = 0),
              icon: const Icon(Icons.edit_location_alt_rounded),
              label: const Text('ثبت محل دریافت نمونه'),
            ),
          ),
        const SectionTitle('کد تخفیف'),
        _promoBox(),
        const SectionTitle('خلاصه سفارش'),
        Glass(
          child: Column(
            children: [
              for (final c in selected) line(c.name, priceText(c.price, unit: false)),
              if (selected.isEmpty) const Text('آزمایشی انتخاب نشده؛ فاکتور در چت هماهنگ می‌شود.'),
              const Divider(height: 22),
              line('جمع آزمایش‌ها', money(_total)),
              if (_discount > 0) line('تخفیف (کد ${_promo!.code})', '− ${money(_discount)}', color: readable(context, MP.success)),
              line(
                _delivery == 'urgent' ? 'هزینه پیک فوری' : 'هزینه ارسال',
                _delivery == 'urgent' ? money(_deliveryFee) : 'رایگان',
                color: _delivery == 'urgent' ? null : readable(context, MP.success),
              ),
              const Divider(height: 22),
              line('مبلغ قابل پرداخت', money(_grandTotal), strong: true),
              if (_hasNegotiable)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('قیمت موارد «توافقی» جدا از این مبلغ اعلام می‌شود.', style: TextStyle(fontSize: 12)),
                ),
            ],
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
            dot(0, '۱. کیس', Icons.pets_rounded),
            Container(width: 24, height: 2, color: step > 0 ? cs.primary : cs.primary.withValues(alpha: .2)),
            dot(1, '۲. فاکتورها', Icons.science_rounded),
            Container(width: 24, height: 2, color: step > 1 ? cs.primary : cs.primary.withValues(alpha: .2)),
            dot(2, '۳. ارسال', Icons.local_shipping_rounded),
          ],
        ),
      ),
    );
  }
}
