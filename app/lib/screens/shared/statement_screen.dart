import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';

import '../../services/api.dart';
import '../../services/export.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/accounting.dart';
import '../../utils/format.dart';
import '../../widgets/form_bits.dart';
import '../../widgets/glass.dart';
import 'order_detail_screen.dart';

/// Account statement ("حسابرسی"): what a clinic owes for a period, PDF export,
/// and recording of card-to-card payments.
/// Clinics see their own account; admins open it for a chosen clinic.
class StatementScreen extends StatefulWidget {
  final String? clinicId;
  const StatementScreen({super.key, this.clinicId});
  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  late final String _clinicId = widget.clinicId ?? Api.myId;
  late final List<StatementPeriod> _periods = StatementPeriod.presets(DateTime.now());
  late StatementPeriod _period = _periods.first;
  RecordModel? _clinic;
  List<RecordModel>? _orders;
  List<RecordModel> _payments = [];
  String? _error;
  bool _busy = false;
  UnsubscribeFunc? _unsub;

  @override
  void initState() {
    super.initState();
    _load();
    Api.pb.collection('payments').subscribe('*', (_) => _load()).then((u) => _unsub = u).catchError((_) => () async {});
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final clinic = Api.isAdmin ? await Api.pb.collection('users').getOne(_clinicId) : Api.me!;
      final orders = await Api.pb.collection('orders').getFullList(filter: 'clinic = "$_clinicId"', sort: 'created');
      final pays = await Api.pb.collection('payments').getFullList(filter: 'clinic = "$_clinicId"', sort: '-created');
      if (!mounted) return;
      setState(() {
        _clinic = clinic;
        _orders = orders;
        _payments = pays;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = Api.error(e));
    }
  }

  Statement get _statement => Statement.build(period: _period, orders: _orders ?? [], payments: _payments);

  Future<void> _pdf() async {
    if (_clinic == null) return;
    setState(() => _busy = true);
    try {
      final settings = context.read<AppState>().settings;
      final bytes = await Export.statementPdf(statement: _statement, clinic: _clinic!, settings: settings);
      await Export.share(bytes, 'melopet-statement-${_period.key}.pdf', Export.pdfMime, text: 'صورت‌حساب ملوپت');
    } catch (e) {
      if (mounted) toast(context, 'ساخت PDF انجام نشد: ${Api.error(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPayment() async {
    final saved = await showGlassSheet<bool>(
      context,
      (c) => _PaymentSheet(clinicId: _clinicId, suggested: _statement.closing > 0 ? _statement.closing : 0),
    );
    if (saved == true) {
      await _load();
      if (mounted) {
        toast(context, Api.isAdmin ? 'پرداخت ثبت شد' : 'پرداخت ثبت شد؛ پس از تایید آزمایشگاه از بدهی کسر می‌شود');
      }
    }
  }

  Future<void> _decide(RecordModel p, String status) async {
    try {
      await Api.pb.collection('payments').update(p.id, body: {'status': status});
      await _load();
      if (mounted) toast(context, status == 'confirmed' ? 'پرداخت تایید شد' : 'پرداخت رد شد');
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _orders == null ? null : _statement;
    return MPScaffold(
      title: Api.isAdmin ? 'حسابرسی ${_clinic?.getStringValue('clinic_name') ?? ''}' : 'حسابرسی و پرداخت',
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in _periods)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: MPChoiceChip(label: p.label, selected: p.key == _period.key, onSelected: (_) => setState(() => _period = p)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              ErrorView(_error!, onRetry: _load)
            else if (st == null)
              const Padding(padding: EdgeInsets.all(40), child: Loading())
            else ...[
              _BalanceCard(st),
              const SizedBox(height: 12),
              GradientButton(label: 'دریافت صورت‌حساب (PDF)', icon: Icons.picture_as_pdf_rounded, loading: _busy, onPressed: _pdf),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _addPayment,
                icon: const Icon(Icons.payments_rounded),
                label: Text(Api.isAdmin ? 'ثبت پرداخت دریافتی' : 'پرداخت و ثبت در برنامه'),
              ),
              SectionTitle('پرداخت‌ها (${faNum(st.payments.length)})'),
              if (st.payments.isEmpty)
                const Glass(child: Text('در این بازه پرداختی ثبت نشده است.'))
              else
                for (final p in st.payments.reversed) _PaymentTile(p, admin: Api.isAdmin, onDecide: _decide),
              SectionTitle('سفارش‌ها (${faNum(st.charges.length)})'),
              if (st.charges.isEmpty)
                const Glass(child: Text('در این بازه سفارشی ثبت نشده است.'))
              else
                for (final c in st.charges.reversed)
                  Glass(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: c.order.id))),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${c.order.getStringValue('code')}  •  ${c.order.getStringValue('pet_name')}',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(jDate(c.date), style: TextStyle(fontSize: 12, color: muted(context))),
                            ],
                          ),
                        ),
                        Text(money(c.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final Statement st;
  const _BalanceCard(this.st);

  @override
  Widget build(BuildContext context) {
    final owes = st.closing > 0.5;
    final color = readable(context, owes ? MP.danger : MP.success);

    Widget line(String label, double v, {bool minus = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13, color: muted(context))),
          ),
          Text('${minus ? '− ' : ''}${money(v)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );

    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(owes ? 'مانده بدهی شما' : (st.closing < -0.5 ? 'بستانکار' : 'وضعیت حساب'), style: TextStyle(color: muted(context))),
          const SizedBox(height: 4),
          Text(
            st.closing.abs() < 0.5 ? 'تسویه شده' : money(st.closing.abs()),
            key: const Key('statement-balance'),
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color),
          ),
          const Divider(height: 24),
          if (st.period.from != null) line('مانده از قبل', st.opening),
          line('هزینه آزمایش‌ها (${faNum(st.charges.length)} سفارش)', st.chargesTotal),
          line('پرداخت‌های تایید شده', st.confirmedTotal, minus: true),
          if (st.pendingTotal > 0) line('در انتظار تایید (هنوز کسر نشده)', st.pendingTotal),
        ],
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final Payment p;
  final bool admin;
  final Future<void> Function(RecordModel, String) onDecide;
  const _PaymentTile(this.p, {required this.admin, required this.onDecide});

  @override
  Widget build(BuildContext context) {
    final pending = p.status == 'pending';
    final color = pending ? MP.warning : MP.success;
    final tracking = p.record.getStringValue('tracking_no');
    return Glass(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(pending ? Icons.hourglass_top_rounded : Icons.check_circle_rounded, size: 20, color: readable(context, color)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(money(p.amount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
              Text(
                pending ? 'در انتظار تایید' : 'تایید شده',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: readable(context, color)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              jDate(p.date),
              paymentMethodLabels[p.record.getStringValue('method')] ?? '',
              if (tracking.isNotEmpty) 'پیگیری: $tracking',
              if (p.record.getStringValue('note').isNotEmpty) p.record.getStringValue('note'),
            ].where((e) => e.isNotEmpty).join('  •  '),
            style: TextStyle(fontSize: 12, color: muted(context)),
          ),
          if (admin && pending) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onDecide(p.record, 'confirmed'),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('تایید پرداخت'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: () => onDecide(p.record, 'rejected'), child: const Text('رد')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Where to pay (clinics) + the form that records the payment.
class _PaymentSheet extends StatefulWidget {
  final String clinicId;
  final double suggested;
  const _PaymentSheet({required this.clinicId, required this.suggested});
  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late final _amount = TextEditingController(text: widget.suggested > 0 ? widget.suggested.round().toString() : '');
  final _tracking = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;
  String? _err;

  @override
  void dispose() {
    _amount.dispose();
    _tracking.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(enNum(_amount.text).replaceAll(RegExp(r'[,٬\s]'), ''));
    if (amount == null || amount <= 0) {
      setState(() => _err = 'مبلغ پرداختی را وارد کنید');
      return;
    }
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      await Api.pb
          .collection('payments')
          .create(
            body: {
              'clinic': widget.clinicId,
              'amount': amount,
              'method': 'card',
              'tracking_no': enNum(_tracking.text.trim()),
              'note': _note.text.trim(),
              'paid_at': DateTime.now().toUtc().toIso8601String(),
            },
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _err = Api.error(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().settings;
    final card = s?.getStringValue('card_number') ?? '';
    final admin = Api.isAdmin;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(admin ? 'ثبت پرداخت دریافتی' : 'پرداخت به آزمایشگاه', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          if (!admin) ...[
            Glass(
              padding: const EdgeInsets.all(14),
              child: card.isEmpty
                  ? const Text('شماره کارت هنوز توسط آزمایشگاه ثبت نشده است؛ لطفا با آزمایشگاه تماس بگیرید.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ابتدا مبلغ را کارت‌به‌کارت کنید:'),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => copyText(context, enNum(card).replaceAll(RegExp(r'\D'), ''), done: 'شماره کارت کپی شد'),
                          child: Row(
                            children: [
                              Expanded(
                                child: Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    cardGroups(card),
                                    key: const Key('lab-card'),
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1),
                                  ),
                                ),
                              ),
                              Icon(Icons.copy_rounded, size: 20, color: readable(context, MP.pinkDeep)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            s?.getStringValue('card_holder') ?? '',
                            s?.getStringValue('bank_name') ?? '',
                          ].where((e) => e.isNotEmpty).join(' • '),
                          style: TextStyle(fontSize: 12.5, color: muted(context)),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            const Text('سپس پرداخت را اینجا ثبت کنید تا آزمایشگاه تایید کند:', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
          ],
          Field(_amount, 'مبلغ پرداختی ($kCurrency)', icon: Icons.payments_rounded, keyboard: TextInputType.number, ltr: true),
          Field(_tracking, 'شماره پیگیری / ۴ رقم آخر کارت مبدأ', icon: Icons.tag_rounded, keyboard: TextInputType.number, ltr: true),
          Field(_note, 'توضیحات (اختیاری)', icon: Icons.notes_rounded),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_err!, style: TextStyle(color: readable(context, MP.danger))),
            ),
          GradientButton(label: admin ? 'ثبت پرداخت' : 'ثبت پرداخت من', icon: Icons.check_rounded, loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}
