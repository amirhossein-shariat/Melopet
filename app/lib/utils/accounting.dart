/// Account statement maths — kept free of UI/network so it can be unit-tested.
///
/// A clinic's balance = charges (orders that are not cancelled) − payments the lab confirmed.
/// Pending payments are shown but not deducted until the lab confirms them.
library;

import 'package:pocketbase/pocketbase.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'format.dart';

/// A selectable reporting window. [from] is inclusive, [to] exclusive; null = unbounded.
class StatementPeriod {
  final String key;
  final String label;
  final DateTime? from;
  final DateTime? to;
  const StatementPeriod(this.key, this.label, this.from, this.to);

  /// Standard windows relative to [now]: this Jalali month, last Jalali month, 30 days, all time.
  static List<StatementPeriod> presets(DateTime now) {
    final j = Jalali.fromDateTime(now);
    final thisMonth = Jalali(j.year, j.month, 1);
    final nextMonth = j.month == 12 ? Jalali(j.year + 1, 1, 1) : Jalali(j.year, j.month + 1, 1);
    final prevMonth = j.month == 1 ? Jalali(j.year - 1, 12, 1) : Jalali(j.year, j.month - 1, 1);
    return [
      StatementPeriod('month', 'این ماه', thisMonth.toDateTime(), nextMonth.toDateTime()),
      StatementPeriod('prev', 'ماه قبل', prevMonth.toDateTime(), thisMonth.toDateTime()),
      StatementPeriod('d30', '۳۰ روز اخیر', DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)), null),
      const StatementPeriod('all', 'همه', null, null),
    ];
  }

  bool contains(DateTime d) => (from == null || !d.isBefore(from!)) && (to == null || d.isBefore(to!));
  bool before(DateTime d) => from != null && d.isBefore(from!);
}

class Charge {
  final RecordModel order;
  final DateTime date;
  final double amount;
  Charge(this.order, this.date, this.amount);
}

class Payment {
  final RecordModel record;
  final DateTime date;
  final double amount;
  final String status; // pending | confirmed | rejected
  Payment(this.record, this.date, this.amount, this.status);
}

class Statement {
  final StatementPeriod period;

  /// Balance carried in from before the period (positive = clinic owes).
  final double opening;
  final List<Charge> charges;
  final List<Payment> payments;

  Statement(this.period, this.opening, this.charges, this.payments);

  double get chargesTotal => charges.fold(0.0, (a, c) => a + c.amount);
  double get confirmedTotal => payments.where((p) => p.status == 'confirmed').fold(0.0, (a, p) => a + p.amount);
  double get pendingTotal => payments.where((p) => p.status == 'pending').fold(0.0, (a, p) => a + p.amount);

  /// What the clinic owes at the end of the period (negative = credit).
  double get closing => opening + chargesTotal - confirmedTotal;

  static double orderAmount(RecordModel o) => o.getDoubleValue('total') - o.getDoubleValue('discount');

  /// Builds a statement from every order and payment of one clinic.
  static Statement build({
    required StatementPeriod period,
    required Iterable<RecordModel> orders,
    required Iterable<RecordModel> payments,
  }) {
    var opening = 0.0;
    final charges = <Charge>[];
    for (final o in orders) {
      if (o.getStringValue('status') == 'cancelled') continue;
      final d = parseDate(o.getStringValue('created'));
      if (d == null) continue;
      final amount = orderAmount(o);
      if (period.before(d)) {
        opening += amount;
      } else if (period.contains(d)) {
        charges.add(Charge(o, d, amount));
      }
    }
    final pays = <Payment>[];
    for (final p in payments) {
      final status = p.getStringValue('status');
      if (status == 'rejected') continue;
      final d = parseDate(p.getStringValue('paid_at')) ?? parseDate(p.getStringValue('created'));
      if (d == null) continue;
      final amount = p.getDoubleValue('amount');
      if (period.before(d)) {
        if (status == 'confirmed') opening -= amount;
      } else if (period.contains(d)) {
        pays.add(Payment(p, d, amount, status));
      }
    }
    charges.sort((a, b) => a.date.compareTo(b.date));
    pays.sort((a, b) => a.date.compareTo(b.date));
    return Statement(period, opening, charges, pays);
  }

  /// Overall balance for a clinic (all time, confirmed payments only).
  static double balance(Iterable<RecordModel> orders, Iterable<RecordModel> payments) {
    final all = Statement.build(period: const StatementPeriod('all', 'همه', null, null), orders: orders, payments: payments);
    return all.closing;
  }
}

/// "بدهکار" / "بستانکار" / "تسویه" wording for a balance.
String balanceLabel(double v) => v > 0.5 ? 'بدهکار' : (v < -0.5 ? 'بستانکار' : 'تسویه');
String balanceText(double v) => v.abs() < 0.5 ? 'تسویه شده' : '${money(v.abs())} ${balanceLabel(v)}';

/// Formats a card number as 4-4-4-4 (digits kept as given).
String cardGroups(String raw) {
  final d = enNum(raw).replaceAll(RegExp(r'\D'), '');
  final parts = <String>[];
  for (var i = 0; i < d.length; i += 4) {
    parts.add(d.substring(i, i + 4 > d.length ? d.length : i + 4));
  }
  return parts.join(' ');
}

const paymentMethodLabels = {'card': 'کارت به کارت', 'cash': 'نقدی', 'other': 'سایر'};
