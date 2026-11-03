import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/catalog.dart';
import '../../services/export.dart';
import '../../utils/format.dart';
import '../../widgets/glass.dart';

import 'package:excel/excel.dart' as xl;

import 'dart:typed_data';

/// Partner price list (shows only the caller's own prices).
class PriceListScreen extends StatefulWidget {
  const PriceListScreen({super.key});
  @override
  State<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends State<PriceListScreen> {
  late Future<List<CatalogItem>> _future = Catalog.load();
  String _q = '';

  Future<void> _export(List<CatalogItem> items) async {
    final book = xl.Excel.createExcel();
    final s = book[book.getDefaultSheet() ?? 'Sheet1'];
    s.isRTL = true;
    s.appendRow([
      xl.TextCellValue('آزمایش'),
      xl.TextCellValue('کد'),
      xl.TextCellValue('بخش'),
      xl.TextCellValue('نمونه'),
      xl.TextCellValue('قیمت ($kCurrency)'),
    ]);
    for (final c in items) {
      s.appendRow([
        xl.TextCellValue(c.name),
        xl.TextCellValue(c.code),
        xl.TextCellValue(categoryInfo(c.category).label),
        xl.TextCellValue(c.sampleType),
        xl.DoubleCellValue(c.price.toDouble()),
      ]);
    }
    await Export.share(Uint8List.fromList(book.encode() ?? []), 'melopet-prices.xlsx', Export.xlsxMime);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CatalogItem>>(
      future: _future,
      builder: (context, snap) {
        final items = (snap.data ?? [])
            .where((c) => _q.isEmpty || c.name.toLowerCase().contains(_q) || c.code.toLowerCase().contains(_q))
            .toList();
        return MPScaffold(
          title: 'تعرفه آزمایش‌ها',
          actions: [
            if (snap.hasData)
              IconButton(tooltip: 'خروجی اکسل', onPressed: () => _export(snap.data!), icon: const Icon(Icons.table_view_rounded)),
          ],
          body: snap.connectionState != ConnectionState.done
              ? const Loading()
              : snap.hasError
              ? ErrorView(Api.error(snap.error!), onRetry: () => setState(() => _future = Catalog.load()))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'جستجو'),
                      onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 12),
                    for (final c in items)
                      Glass(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            GlassIcon(categoryInfo(c.category).icon, color: categoryInfo(c.category).color, size: 42),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(
                                    [
                                      categoryInfo(c.category).label,
                                      if (c.sampleType.isNotEmpty) c.sampleType,
                                      if (c.hours > 0) 'جواب: ${faNum(c.hours)} ساعت',
                                    ].join(' • '),
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                            Text(money(c.price), style: const TextStyle(fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}
