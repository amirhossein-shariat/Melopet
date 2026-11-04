import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../services/api.dart';
import '../../services/export.dart';
import '../../utils/format.dart';
import '../../widgets/glass.dart';
import '../clinic/home_screen.dart';

/// Orders list. For clinics: their own orders. For admins: all orders
/// (optionally of a single clinic).
class OrdersScreen extends StatefulWidget {
  final String? clinicId;
  final bool standalone;
  const OrdersScreen({super.key, this.clinicId, this.standalone = false});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const _filters = {'all': 'همه', 'open': 'در جریان', 'requested': 'جدید', 'ready': 'جواب آماده', 'cancelled': 'لغو شده'};
  String _filter = 'all';
  String _q = '';
  final List<RecordModel> _items = [];
  int _page = 1;
  bool _more = true;
  bool _loading = false;
  UnsubscribeFunc? _unsub;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (Api.isAdmin && widget.clinicId == null) _filter = 'open';
    _reload();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _fetch();
    });
    Api.pb.collection('orders').subscribe('*', (_) => _reload()).then((u) => _unsub = u).catchError((_) => () async {});
  }

  @override
  void dispose() {
    _unsub?.call();
    _scroll.dispose();
    super.dispose();
  }

  String get _filterExpr {
    final parts = <String>[];
    if (widget.clinicId != null) parts.add('clinic = "${widget.clinicId}"');
    switch (_filter) {
      case 'open':
        parts.add('status != "ready" && status != "cancelled"');
      case 'requested':
      case 'ready':
      case 'cancelled':
        parts.add('status = "$_filter"');
    }
    if (_q.isNotEmpty) {
      final q = _q.replaceAll('"', '');
      parts.add('(code ~ "$q" || pet_name ~ "$q" || owner_name ~ "$q" || clinic.clinic_name ~ "$q")');
    }
    return parts.join(' && ');
  }

  Future<void> _reload() async {
    _page = 1;
    _more = true;
    _items.clear();
    await _fetch(force: true);
  }

  Future<void> _fetch({bool force = false}) async {
    if ((_loading && !force) || !_more) return;
    _loading = true;
    try {
      final r = await Api.pb
          .collection('orders')
          .getList(page: _page, perPage: 30, sort: '-created', filter: _filterExpr, expand: 'clinic');
      _page++;
      _more = r.page < r.totalPages;
      if (mounted) setState(() => _items.addAll(r.items));
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _export() async {
    final all = await Api.pb.collection('orders').getFullList(sort: '-created', filter: _filterExpr, expand: 'clinic');
    await Export.share(Export.ordersExcel(all), 'melopet-orders.xlsx', Export.xlsxMime);
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      bottom: false,
      child: Column(
        children: [
          if (!widget.standalone)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('سفارش‌ها', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  ),
                  IconButton(tooltip: 'خروجی اکسل', onPressed: _export, icon: const Icon(Icons.table_view_rounded)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'جستجو: کد، نام حیوان، صاحب یا مرکز'),
              onSubmitted: (v) {
                _q = v.trim();
                _reload();
              },
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in _filters.entries)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: MPChoiceChip(
                      label: f.value,
                      selected: _filter == f.key,
                      onSelected: (_) {
                        setState(() => _filter = f.key);
                        _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: _items.isEmpty && !_loading
                  ? ListView(
                      children: const [
                        SizedBox(height: 80),
                        EmptyState(icon: Icons.receipt_long_rounded, title: 'سفارشی یافت نشد'),
                      ],
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      itemCount: _items.length + (_more ? 1 : 0),
                      itemBuilder: (_, i) => i >= _items.length
                          ? const Padding(padding: EdgeInsets.all(16), child: Loading())
                          : OrderTile(_items[i], showClinic: Api.isAdmin && widget.clinicId == null),
                    ),
            ),
          ),
          if (_items.isNotEmpty && Api.isAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${faNum(_items.length)} مورد', style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
    if (!widget.standalone) return body;
    return MPScaffold(
      title: 'سفارش‌های مرکز',
      actions: [IconButton(onPressed: _export, icon: const Icon(Icons.table_view_rounded))],
      body: body,
    );
  }
}
