import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api.dart';
import '../../services/export.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../utils/results.dart';
import '../../widgets/form_bits.dart';
import '../../widgets/glass.dart';
import '../../widgets/location.dart';
import '../../widgets/voice.dart';
import '../admin/result_entry_screen.dart';
import '../chat/chat_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  RecordModel? _o;
  String? _error;
  UnsubscribeFunc? _unsub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    Api.pb.collection('orders').subscribe(widget.orderId, (_) => _load()).then((u) => _unsub = u).catchError((_) => () async {});
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await Api.pb.collection('orders').getOne(widget.orderId, expand: 'clinic');
      if (mounted) setState(() => _o = o);
    } catch (e) {
      if (mounted) setState(() => _error = Api.error(e));
    }
  }

  RecordModel? get _clinic => _o?.get<RecordModel?>('expand.clinic');

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _fileBase =>
      'melopet-${_o!.getStringValue('code')}${_o!.getStringValue('pet_name').isNotEmpty ? '-${_o!.getStringValue('pet_name')}' : ''}';

  Future<void> _pdf({required bool letterhead, bool print = false}) => _run(() async {
    final settings = context.read<AppState>().settings;
    final bytes = await Export.resultPdfFor(_o!, _clinic, useLetterhead: letterhead, settings: settings);
    if (print) {
      await Export.printPdf(bytes, '$_fileBase.pdf');
    } else {
      await Export.share(bytes, '$_fileBase.pdf', Export.pdfMime, text: 'جواب آزمایش ${_o!.getStringValue('pet_name')}');
    }
  });

  Future<void> _excel() => _run(() async {
    await Export.share(Export.resultExcel(_o!, _clinic), '$_fileBase.xlsx', Export.xlsxMime);
  });

  Future<void> _cancel() async {
    if (!await confirm(context, 'لغو درخواست', 'از لغو این درخواست اطمینان دارید؟', ok: 'لغو درخواست')) return;
    await _run(() async {
      await Api.pb.send('/api/melopet/orders/${_o!.id}/cancel', method: 'POST');
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    return MPScaffold(
      title: o == null ? 'جزئیات سفارش' : 'سفارش ${faNum(o.getStringValue('code'))}',
      actions: [
        if (o != null)
          IconButton(
            tooltip: 'پیام درباره این سفارش',
            icon: const Icon(Icons.chat_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  clinicId: Api.isAdmin ? o.getStringValue('clinic') : null,
                  draft: 'درباره سفارش ${o.getStringValue('code')}: ',
                ),
              ),
            ),
          ),
      ],
      body: _error != null
          ? ErrorView(_error!, onRetry: _load)
          : o == null
          ? const Loading()
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    children: [
                      _header(o),
                      const SizedBox(height: 12),
                      _Timeline(o),
                      if (Api.isAdmin) ...[const SizedBox(height: 12), _AdminPanel(order: o, onChanged: _load)],
                      _results(o),
                      const SectionTitle('مشخصات کیس'),
                      _patient(o),
                      ..._history(o),
                      if (geoOf(o, 'location') != null) ...[
                        const SectionTitle('محل دریافت نمونه'),
                        MapPreview(point: geoOf(o, 'location')!, label: _clinic?.getStringValue('clinic_name') ?? ''),
                      ],
                      const SectionTitle('آزمایش‌ها و هزینه'),
                      _items(o),
                      if (!Api.isAdmin && o.getStringValue('status') == 'requested') ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: MP.danger),
                          onPressed: _cancel,
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('لغو درخواست'),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_busy)
                  const Positioned.fill(
                    child: ColoredBox(color: Colors.black26, child: Loading()),
                  ),
              ],
            ),
    );
  }

  Widget _header(RecordModel o) {
    final status = o.getStringValue('status');
    final s = statusInfo(status);
    final clinic = _clinic;
    return Glass(
      child: Row(
        children: [
          GlassIcon(s.icon, color: s.color, size: 58),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        o.getStringValue('pet_name').isEmpty ? 'بدون نام' : o.getStringValue('pet_name'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    StatusChip(status),
                  ],
                ),
                const SizedBox(height: 4),
                Text('ثبت: ${jDateTime(parseDate(o.getStringValue('created')))}', style: const TextStyle(fontSize: 12)),
                if (Api.isAdmin && clinic != null)
                  Text(
                    '${clinic.getStringValue('clinic_name')} • دکتر ${clinic.getStringValue('doctor_name')}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                if (o.getBoolValue('urgent'))
                  const Text(
                    '⚡ فوری',
                    style: TextStyle(color: MP.danger, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                if (o.getStringValue('courier_name').isNotEmpty)
                  InkWell(
                    onTap: () => launchUrl(Uri.parse('tel:${o.getStringValue('courier_phone')}')),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '🛵 پیک: ${o.getStringValue('courier_name')}  ${faNum(o.getStringValue('courier_phone'))}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _results(RecordModel o) {
    final results = parseResults(o.data['results']);
    final ready = o.getStringValue('status') == 'ready';
    final files = o.getListValue<String>('result_files');
    if (!ready && !(Api.isAdmin && results.isNotEmpty)) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(ready ? 'جواب آزمایش' : 'پیش‌نمایش جواب (منتشر نشده)'),
        if (ready)
          Glass(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _ActionBtn(Icons.picture_as_pdf_rounded, 'PDF با سربرگ', MP.pinkDeep, () => _pdf(letterhead: true)),
                _ActionBtn(Icons.description_rounded, 'PDF ملوپت', MP.lavenderDeep, () => _pdf(letterhead: false)),
                _ActionBtn(Icons.table_view_rounded, 'اکسل', MP.mintDeep, _excel),
                _ActionBtn(Icons.print_rounded, 'چاپ', MP.peachDeep, () => _pdf(letterhead: true, print: true)),
              ],
            ),
          ),
        if (ready && !Api.isAdmin && (Api.me?.getStringValue('letterhead').isEmpty ?? true))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('💡 سربرگ مجموعه را در پروفایل آپلود کنید تا جواب روی سربرگ خودتان ساخته شود.', style: TextStyle(fontSize: 11.5)),
          ),
        const SizedBox(height: 10),
        for (final t in results) ResultCard(t),
        if (o.getStringValue('lab_comment').isNotEmpty)
          Glass(
            margin: const EdgeInsets.only(top: 4),
            tint: MP.pink.withValues(alpha: .12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('تفسیر / توضیحات آزمایشگاه', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(o.getStringValue('lab_comment')),
              ],
            ),
          ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final f in files)
            Glass(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onTap: () => launchUrl(Api.fileUrlByName(o, f), mode: LaunchMode.externalApplication),
              child: Row(
                children: [
                  const Icon(Icons.attach_file_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(f, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
                  ),
                  const Icon(Icons.download_rounded),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _patient(RecordModel o) {
    final rows = <(String, String)>[
      ('گونه', speciesLabels[o.getStringValue('species')] ?? '-'),
      ('نژاد', o.getStringValue('breed')),
      ('سن', o.getStringValue('age')),
      ('جنس', sexLabels[o.getStringValue('sex')] ?? ''),
      ('وزن', o.getDoubleValue('weight') > 0 ? '${faNum(o.getDoubleValue('weight'))} kg' : ''),
      ('صاحب حیوان', o.getStringValue('owner_name')),
      ('شماره پرونده', o.getStringValue('file_no')),
      ('ناشتا', o.getBoolValue('fasting') ? 'بله' : ''),
      ('زمان مراجعه پیک', o.getStringValue('pickup_time')),
      ('آدرس', o.getStringValue('pickup_address')),
    ].where((r) => r.$2.isNotEmpty).toList();
    return Glass(
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(r.$1, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .6))),
                  ),
                  Expanded(
                    child: Text(faNum(r.$2), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _history(RecordModel o) {
    final text = o.getStringValue('clinical_notes');
    final voice = o.getStringValue('history_voice');
    if (text.isEmpty && voice.isEmpty) return const [];
    return [
      const SectionTitle('تاریخچه کیس (History)'),
      Glass(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (text.isNotEmpty) SelectableText(text, style: const TextStyle(height: 1.8)),
            if (text.isNotEmpty && voice.isNotEmpty) const Divider(height: 20),
            if (voice.isNotEmpty) VoicePlayer.url(Api.fileUrlByName(o, voice).toString(), seconds: o.getIntValue('history_voice_seconds')),
          ],
        ),
      ),
    ];
  }

  Widget _items(RecordModel o) {
    final items = (o.data['items'] as List? ?? []).cast<Map>();
    return Glass(
      child: Column(
        children: [
          if (items.isEmpty) const Text('آزمایش‌ها در چت هماهنگ می‌شود'),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(categoryInfo('${i['category']}').icon, size: 18, color: categoryInfo('${i['category']}').color),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${i['name']}')),
                  Text(money(i['price'] as num? ?? 0, unit: false)),
                ],
              ),
            ),
          const Divider(),
          Row(
            children: [
              const Expanded(
                child: Text('جمع کل', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              Text(money(o.getDoubleValue('total')), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          if (o.getBoolValue('paid'))
            const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                '✓ تسویه شده',
                style: TextStyle(color: MP.success, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(this.icon, this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            GlassIcon(icon, color: color, size: 46),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Status progress with timestamps.
class _Timeline extends StatelessWidget {
  final RecordModel o;
  const _Timeline(this.o);

  @override
  Widget build(BuildContext context) {
    final status = o.getStringValue('status');
    if (status == 'cancelled') {
      return const Glass(
        child: Row(
          children: [
            Icon(Icons.cancel_rounded, color: Colors.grey),
            SizedBox(width: 8),
            Text('این درخواست لغو شده است'),
          ],
        ),
      );
    }
    final history = <String, DateTime?>{};
    for (final h in (o.data['history'] as List? ?? [])) {
      history['${h['status']}'] = parseDate('${h['at']}');
    }
    final current = orderStatuses.indexOf(status);
    final cs = Theme.of(context).colorScheme;
    return Glass(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < orderStatuses.length; i++)
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 3,
                          color: i == 0 ? Colors.transparent : (i <= current ? cs.primary : cs.primary.withValues(alpha: .15)),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i <= current ? statusInfo(orderStatuses[i]).color : cs.primary.withValues(alpha: .1),
                        ),
                        child: Icon(
                          i < current ? Icons.check_rounded : statusInfo(orderStatuses[i]).icon,
                          size: 16,
                          color: i <= current ? Colors.white : cs.onSurface.withValues(alpha: .4),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 3,
                          color: i == orderStatuses.length - 1
                              ? Colors.transparent
                              : (i < current ? cs.primary : cs.primary.withValues(alpha: .15)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    statusInfo(orderStatuses[i]).label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9.5, fontWeight: i == current ? FontWeight.w900 : FontWeight.w500),
                  ),
                  if (history[orderStatuses[i]] != null) Text(hm(history[orderStatuses[i]]), style: const TextStyle(fontSize: 9)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One test's results as a card with H/L flags.
class ResultCard extends StatelessWidget {
  final TestResult t;
  const ResultCard(this.t, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final params = t.params.where((p) => p.value.trim().isNotEmpty).toList();
    return Glass(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(categoryInfo(t.category).icon, color: categoryInfo(t.category).color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          if (params.isNotEmpty) ...[
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final h in const ['Parameter', 'Result', 'Unit', 'Reference'])
                        Expanded(
                          flex: h == 'Parameter' ? 3 : 2,
                          child: Text(
                            h,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.primary),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 10),
                  for (final p in params)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text(p.name, style: const TextStyle(fontSize: 12.5))),
                          Expanded(
                            flex: 2,
                            child: Row(
                              children: [
                                Text(
                                  p.value,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: p.flag == Flag.high
                                        ? MP.danger
                                        : p.flag == Flag.low
                                        ? const Color(0xFF3F7FD0)
                                        : null,
                                  ),
                                ),
                                if (p.flag == Flag.high) const Icon(Icons.arrow_upward_rounded, size: 14, color: MP.danger),
                                if (p.flag == Flag.low) const Icon(Icons.arrow_downward_rounded, size: 14, color: Color(0xFF3F7FD0)),
                              ],
                            ),
                          ),
                          Expanded(flex: 2, child: Text(p.unit, style: const TextStyle(fontSize: 11))),
                          Expanded(flex: 2, child: Text(p.range, style: const TextStyle(fontSize: 11))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (t.text.trim().isNotEmpty) ...[const SizedBox(height: 8), Text(t.text)],
        ],
      ),
    );
  }
}

/// Admin-only controls on an order.
class _AdminPanel extends StatelessWidget {
  final RecordModel order;
  final VoidCallback onChanged;
  const _AdminPanel({required this.order, required this.onChanged});

  Future<void> _setStatus(BuildContext context, String status) async {
    try {
      final body = <String, dynamic>{'status': status};
      if (status == 'courier_assigned') {
        final name = TextEditingController(text: order.getStringValue('courier_name'));
        final phone = TextEditingController(text: order.getStringValue('courier_phone'));
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('اعزام پیک'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Field(name, 'نام پیک', icon: Icons.person_rounded),
                Field(phone, 'شماره پیک', icon: Icons.phone_rounded, ltr: true, keyboard: TextInputType.phone),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('اعزام')),
            ],
          ),
        );
        if (ok != true) return;
        body['courier_name'] = name.text.trim();
        body['courier_phone'] = enNum(phone.text.trim());
      }
      if (status == 'ready' && parseResults(order.data['results']).isEmpty && order.getListValue<String>('result_files').isEmpty) {
        if (!context.mounted) return;
        if (!await confirm(context, 'جواب ثبت نشده', 'هنوز نتیجه‌ای وارد نشده است. باز هم «جواب آماده» شود؟')) return;
      }
      await Api.pb.collection('orders').update(order.id, body: body);
      onChanged();
      if (context.mounted) toast(context, 'وضعیت به «${statusInfo(status).label}» تغییر کرد و به همکار اطلاع داده شد');
    } catch (e) {
      if (context.mounted) toast(context, Api.error(e), error: true);
    }
  }

  Future<void> _uploadFile(BuildContext context) async {
    final f = await pickOne();
    if (f == null) return;
    try {
      await Api.pb.collection('orders').update(order.id, files: [f.toMultipart('result_files+')]);
      onChanged();
    } catch (e) {
      if (context.mounted) toast(context, Api.error(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = order.getStringValue('status');
    final idx = orderStatuses.indexOf(status);
    final next = idx >= 0 && idx < orderStatuses.length - 1 ? orderStatuses[idx + 1] : null;
    return Glass(
      tint: MP.lavender.withValues(alpha: .14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.admin_panel_settings_rounded, color: MP.lavenderDeep),
              SizedBox(width: 6),
              Text('مدیریت سفارش', style: TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          if (next != null)
            GradientButton(
              label: 'مرحله بعد: ${statusInfo(next).label}',
              icon: statusInfo(next).icon,
              onPressed: () => _setStatus(context, next),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('ورود جواب'),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ResultEntryScreen(order: order)));
                  onChanged();
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('پیوست فایل جواب'),
                onPressed: () => _uploadFile(context),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.swap_vert_rounded),
                label: const Text('تغییر وضعیت'),
                onPressed: () => showGlassSheet(
                  context,
                  (c) => ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final s in [...orderStatuses, 'cancelled'])
                        ListTile(
                          leading: Icon(statusInfo(s).icon, color: statusInfo(s).color),
                          title: Text(statusInfo(s).label),
                          trailing: s == status ? const Icon(Icons.check_rounded) : null,
                          onTap: () {
                            Navigator.pop(c);
                            if (s != status) _setStatus(context, s);
                          },
                        ),
                    ],
                  ),
                ),
              ),
              MPChoiceChip(
                label: 'تسویه شده',
                selected: order.getBoolValue('paid'),
                onSelected: (v) async {
                  await Api.pb.collection('orders').update(order.id, body: {'paid': v});
                  onChanged();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
