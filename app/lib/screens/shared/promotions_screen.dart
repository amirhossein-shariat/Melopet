import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../services/api.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/glass.dart';
import '../admin/promotion_edit_screen.dart';

/// Discounts & special offers.
class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key});
  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  List<RecordModel>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.pb.collection('promotions').getFullList(sort: '-created');
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = Api.error(e));
    }
  }

  Future<void> _edit([RecordModel? p]) async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => PromotionEditScreen(promo: p)));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Api.isAdmin
          ? Padding(
              padding: const EdgeInsets.only(bottom: 80),
              child: FloatingActionButton.extended(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('پیشنهاد جدید'),
              ),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
            children: [
              const Text('پیشنهادهای ویژه 🎁', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                'تخفیف‌ها و طرح‌های ویژه همکاران ملوپت',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .6)),
              ),
              const SizedBox(height: 14),
              if (_error != null)
                ErrorView(_error!, onRetry: _load)
              else if (_items == null)
                const Padding(padding: EdgeInsets.all(40), child: Loading())
              else if (_items!.isEmpty)
                const EmptyState(
                  icon: Icons.local_offer_rounded,
                  title: 'فعلا پیشنهاد فعالی نیست',
                  subtitle: 'به محض انتشار تخفیف جدید، اعلان دریافت می‌کنید.',
                )
              else
                for (final p in _items!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: PromoCard(p, onTap: Api.isAdmin ? () => _edit(p) : null),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class PromoCard extends StatelessWidget {
  final RecordModel p;
  final bool compact;
  final VoidCallback? onTap;
  const PromoCard(this.p, {super.key, this.compact = false, this.onTap});

  Color get _color {
    final c = p.getStringValue('color');
    final v = int.tryParse(c.replaceFirst('#', ''), radix: 16);
    return v == null ? MP.pink : Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    final img = p.getStringValue('image');
    final discount = p.getDoubleValue('discount_percent');
    final until = parseDate(p.getStringValue('valid_until'));
    final code = p.getStringValue('code');
    final expired = until != null && until.isBefore(DateTime.now());
    final color = _color;

    return Opacity(
      opacity: expired ? .55 : 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(colors: [color.withValues(alpha: .95), Color.lerp(color, MP.lavender, .6)!]),
          boxShadow: [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap ?? (compact ? null : () => _details(context)),
            child: Stack(
              children: [
                if (img.isNotEmpty && !compact)
                  Image.network(
                    Api.fileUrl(p, 'image', thumb: '600x300').toString(),
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(),
                  ),
                Positioned(
                  left: -24,
                  top: -24,
                  child: Icon(Icons.local_offer_rounded, size: 120, color: Colors.white.withValues(alpha: .18)),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(18, img.isNotEmpty && !compact ? 172 : 18, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.getStringValue('title'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: MP.plum, fontWeight: FontWeight.w900, fontSize: 17),
                            ),
                          ),
                          if (discount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .7), borderRadius: BorderRadius.circular(14)),
                              child: Text(
                                '${faNum(discount.toInt())}٪',
                                style: const TextStyle(color: MP.plum, fontWeight: FontWeight.w900, fontSize: 18),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        p.getStringValue('body'),
                        maxLines: compact ? 2 : 6,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: MP.plum.withValues(alpha: .85), fontSize: 12.5, height: 1.6),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (until != null)
                            Text(
                              expired ? 'منقضی شده' : 'تا ${jDateLong(until)}',
                              style: const TextStyle(color: MP.plum, fontSize: 11.5, fontWeight: FontWeight.w700),
                            ),
                          const Spacer(),
                          if (code.isNotEmpty)
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: code));
                                toast(context, 'کد تخفیف کپی شد');
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(color: MP.plum.withValues(alpha: .5)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'کد: $code',
                                  style: const TextStyle(color: MP.plum, fontWeight: FontWeight.w800, fontSize: 12),
                                ),
                              ),
                            ),
                          if (Api.isAdmin && !p.getBoolValue('active'))
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Text('غیرفعال', style: TextStyle(color: MP.plum)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _details(BuildContext context) {
    showGlassSheet(
      context,
      (c) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.getStringValue('title'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 10),
            Text(p.getStringValue('body'), style: const TextStyle(height: 1.8)),
          ],
        ),
      ),
    );
  }
}
