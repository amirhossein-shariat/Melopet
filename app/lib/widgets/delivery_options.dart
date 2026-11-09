import 'package:flutter/material.dart';

import '../services/delivery.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'glass.dart';

/// "نحوه ارسال": two radio cards, free vs urgent (with its quoted price).
class DeliveryOptions extends StatelessWidget {
  final DeliveryOptionsData? data;
  final bool loading;
  final String value; // standard | urgent
  final ValueChanged<String> onChanged;
  final VoidCallback onRetry;
  const DeliveryOptions({
    super.key,
    required this.data,
    required this.loading,
    required this.value,
    required this.onChanged,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final d = data;
    final hours = d?.windowHours ?? 4;
    String urgentSub;
    Widget urgentPrice;
    var urgentEnabled = false;
    if (loading) {
      urgentSub = 'در حال دریافت قیمت پیک…';
      urgentPrice = const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5));
    } else if (d == null) {
      urgentSub = 'قیمت دریافت نشد. اتصال را بررسی کنید.';
      urgentPrice = TextButton(onPressed: onRetry, child: const Text('تلاش دوباره'));
    } else if (!d.urgentAvailable) {
      urgentSub = switch (d.urgentReason) {
        'location' => 'برای قیمت پیک، محل دریافت نمونه را روی نقشه ثبت کنید.',
        'lab_location' => 'لوکیشن آزمایشگاه هنوز ثبت نشده است؛ با آزمایشگاه تماس بگیرید.',
        _ => 'در حال حاضر قیمت پیک فوری در دسترس نیست.',
      };
      urgentPrice = const SizedBox();
    } else {
      urgentEnabled = true;
      urgentSub = 'پیک همین حالا برای دریافت نمونه می‌آید${d.distanceKm > 0 ? ' • مسافت حدود ${faNum(d.distanceKm)} کیلومتر' : ''}';
      urgentPrice = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            money(d.urgentFee, unit: false),
            key: const Key('urgent-fee'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          Text(kCurrency, style: const TextStyle(fontSize: 11)),
          if (d.isEstimate)
            Text(
              'قیمت تقریبی',
              style: TextStyle(fontSize: 11, color: readable(context, MP.warning), fontWeight: FontWeight.w700),
            ),
        ],
      );
    }

    return Column(
      children: [
        _Card(
          key: const Key('delivery-standard'),
          selected: value == 'standard',
          icon: Icons.local_shipping_rounded,
          color: MP.mintDeep,
          title: 'ارسال عادی',
          subtitle: 'پیک آزمایشگاه هر ${faNum(hours)} ساعت یک دور می‌آید؛ نمونه حداکثر تا ${faNum(hours)} ساعت دیگر دریافت می‌شود.',
          price: Text(
            'رایگان',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: readable(context, MP.success)),
          ),
          onTap: () => onChanged('standard'),
        ),
        const SizedBox(height: 10),
        _Card(
          key: const Key('delivery-urgent'),
          selected: value == 'urgent',
          enabled: urgentEnabled,
          icon: Icons.bolt_rounded,
          color: MP.danger,
          title: 'ارسال فوری (پیک اختصاصی)',
          subtitle: urgentSub,
          price: urgentPrice,
          onTap: urgentEnabled ? () => onChanged('urgent') : null,
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final bool selected;
  final bool enabled;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget price;
  final VoidCallback? onTap;
  const _Card({
    super.key,
    required this.selected,
    this.enabled = true,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : .7,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? cs.primary : Colors.transparent, width: 2),
        ),
        child: Glass(
          onTap: onTap,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? cs.primary : muted(context),
              ),
              const SizedBox(width: 10),
              Icon(icon, color: readable(context, color)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, height: 1.5, color: muted(context))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              price,
            ],
          ),
        ),
      ),
    );
  }
}
