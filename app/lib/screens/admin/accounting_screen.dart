import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';

import '../../services/api.dart';
import '../../services/export.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/accounting.dart';
import '../../utils/format.dart';
import '../../widgets/glass.dart';
import '../shared/statement_screen.dart';

/// Admin: what every partner owes, with a PDF summary and a way into each clinic's statement.
class AccountingScreen extends StatefulWidget {
  const AccountingScreen({super.key});
  @override
  State<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends State<AccountingScreen> {
  late final List<StatementPeriod> _periods = StatementPeriod.presets(DateTime.now());
  late StatementPeriod _period = _periods.last; // overall balance by default
  List<RecordModel>? _clinics;
  List<RecordModel> _orders = [];
  List<RecordModel> _payments = [];
  String? _error;
  bool _busy = false;
  bool _onlyDebt = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final clinics = await Api.pb.collection('users').getFullList(filter: 'role = "clinic"');
      final orders = await Api.pb.collection('orders').getFullList(sort: 'created');
      final pays = await Api.pb.collection('payments').getFullList();
      if (!mounted) return;
      setState(() {
        _clinics = clinics;
        _orders = orders;
        _payments = pays;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = Api.error(e));
    }
  }

  List<(RecordModel, Statement)> get _rows {
    final out = <(RecordModel, Statement)>[];
    for (final c in _clinics ?? <RecordModel>[]) {
      final st = Statement.build(
        period: _period,
        orders: _orders.where((o) => o.getStringValue('clinic') == c.id),
        payments: _payments.where((p) => p.getStringValue('clinic') == c.id),
      );
      final pendingAll = _payments.any((p) => p.getStringValue('clinic') == c.id && p.getStringValue('status') == 'pending');
      if (st.closing.abs() < 0.5 && st.charges.isEmpty && st.payments.isEmpty && !pendingAll) continue;
      if (_onlyDebt && st.closing <= 0.5) continue;
      out.add((c, st));
    }
    out.sort((a, b) => b.$2.closing.compareTo(a.$2.closing));
    return out;
  }

  Future<void> _pdf(List<(RecordModel, Statement)> rows) async {
    setState(() => _busy = true);
    try {
      final bytes = await Export.debtsPdf(period: _period, rows: rows, settings: context.read<AppState>().settings);
      await Export.share(bytes, 'melopet-receivables-${_period.key}.pdf', Export.pdfMime, text: 'گزارش مطالبات همکاران');
    } catch (e) {
      if (mounted) toast(context, 'ساخت PDF انجام نشد: ${Api.error(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _clinics == null ? <(RecordModel, Statement)>[] : _rows;
    final total = rows.fold(0.0, (a, r) => a + (r.$2.closing > 0 ? r.$2.closing : 0));
    final pending = _payments.where((p) => p.getStringValue('status') == 'pending').length;
    return MPScaffold(
      title: 'حسابداری همکاران',
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
                  for (final p in _periods.reversed)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: MPChoiceChip(
                        label: p.key == 'all' ? 'مانده کل' : p.label,
                        selected: p.key == _period.key,
                        onSelected: (_) => setState(() => _period = p),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              ErrorView(_error!, onRetry: _load)
            else if (_clinics == null)
              const Padding(padding: EdgeInsets.all(40), child: Loading())
            else ...[
              Glass(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('جمع مطالبات', style: TextStyle(color: muted(context))),
                    const SizedBox(height: 4),
                    Text(
                      money(total),
                      key: const Key('total-receivable'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: readable(context, total > 0 ? MP.danger : MP.success),
                      ),
                    ),
                    if (pending > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${faNum(pending)} پرداخت در انتظار تایید شماست',
                        style: TextStyle(color: readable(context, MP.warning), fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              GradientButton(
                label: 'گزارش مطالبات (PDF)',
                icon: Icons.picture_as_pdf_rounded,
                loading: _busy,
                onPressed: rows.isEmpty ? null : () => _pdf(rows),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _onlyDebt,
                onChanged: (v) => setState(() => _onlyDebt = v),
                title: const Text('فقط بدهکاران'),
              ),
              if (rows.isEmpty)
                const EmptyState(icon: Icons.account_balance_wallet_rounded, title: 'موردی برای نمایش نیست')
              else
                for (final r in rows)
                  Glass(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => StatementScreen(clinicId: r.$1.id)));
                      _load();
                    },
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.$1.getStringValue('clinic_name'), style: const TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(
                                '${faNum(r.$2.charges.length)} سفارش در این بازه',
                                style: TextStyle(fontSize: 12, color: muted(context)),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          balanceText(r.$2.closing),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: readable(context, r.$2.closing > 0.5 ? MP.danger : MP.success),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14),
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
