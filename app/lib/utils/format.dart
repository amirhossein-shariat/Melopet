import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../theme.dart';

const kCurrency = 'تومان';

const _fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

/// Converts latin digits to Persian digits.
String faNum(Object? v) {
  final s = v?.toString() ?? '';
  final b = StringBuffer();
  for (final c in s.runes) {
    if (c >= 48 && c <= 57) {
      b.write(_fa[c - 48]);
    } else {
      b.writeCharCode(c);
    }
  }
  return b.toString();
}

/// Converts Persian/Arabic digits typed by users to latin digits.
String enNum(String s) {
  const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  var out = s;
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll(_fa[i], '$i').replaceAll(ar[i], '$i');
  }
  return out;
}

String groupDigits(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return (v < 0 ? '-' : '') + b.toString();
}

String money(num v, {bool unit = true, bool persian = true}) {
  final g = groupDigits(v);
  final s = persian ? faNum(g).replaceAll(',', '٬') : g;
  return unit ? '$s $kCurrency' : s;
}

DateTime? parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s.replaceFirst(' ', 'T'))?.toLocal();
}

const _months = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];

String jDate(DateTime? d, {bool persian = true}) {
  if (d == null) return '-';
  final f = Jalali.fromDateTime(d).formatter;
  final s = '${f.yyyy}/${f.mm}/${f.dd}';
  return persian ? faNum(s) : s;
}

String jDateLong(DateTime? d) {
  if (d == null) return '-';
  final j = Jalali.fromDateTime(d);
  return faNum('${j.day} ${_months[j.month - 1]} ${j.year}');
}

String hm(DateTime? d, {bool persian = true}) {
  if (d == null) return '';
  final s = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  return persian ? faNum(s) : s;
}

String jDateTime(DateTime? d) => d == null ? '-' : '${jDate(d)} - ${hm(d)}';

String relativeDay(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'امروز';
  if (diff == 1) return 'دیروز';
  return jDateLong(d);
}

String fileSize(num bytes) {
  if (bytes < 1024) return '${faNum(bytes.toInt())} B';
  if (bytes < 1024 * 1024) return '${faNum((bytes / 1024).toStringAsFixed(0))} KB';
  return '${faNum((bytes / 1024 / 1024).toStringAsFixed(1))} MB';
}

// ---------------------------------------------------------------- labels

class StatusInfo {
  final String label;
  final Color color;
  final IconData icon;
  const StatusInfo(this.label, this.color, this.icon);
}

const orderStatuses = ['requested', 'courier_assigned', 'picked_up', 'received', 'in_progress', 'ready'];

StatusInfo statusInfo(String s) {
  switch (s) {
    case 'requested':
      return const StatusInfo('ثبت شده', MP.lavenderDeep, Icons.receipt_long_rounded);
    case 'courier_assigned':
      return const StatusInfo('پیک در راه', MP.peachDeep, Icons.delivery_dining_rounded);
    case 'picked_up':
      return const StatusInfo('نمونه دریافت شد', Color(0xFF4F8FD8), Icons.inventory_2_rounded);
    case 'received':
      return const StatusInfo('در آزمایشگاه', MP.mintDeep, Icons.biotech_rounded);
    case 'in_progress':
      return const StatusInfo('در حال انجام', MP.pinkDeep, Icons.science_rounded);
    case 'ready':
      return const StatusInfo('جواب آماده', MP.success, Icons.verified_rounded);
    case 'cancelled':
      return const StatusInfo('لغو شده', Colors.grey, Icons.cancel_rounded);
  }
  return StatusInfo(s, Colors.grey, Icons.help_outline);
}

const speciesLabels = {
  'dog': 'سگ',
  'cat': 'گربه',
  'bird': 'پرنده',
  'rabbit': 'خرگوش',
  'rodent': 'جونده',
  'reptile': 'خزنده',
  'horse': 'اسب',
  'ruminant': 'نشخوارکننده',
  'other': 'سایر',
};

const sexLabels = {'male': 'نر', 'female': 'ماده', 'male_neutered': 'نر عقیم', 'female_spayed': 'ماده عقیم', 'unknown': 'نامشخص'};

const clinicTypeLabels = {
  'clinic': 'کلینیک دامپزشکی',
  'hospital': 'بیمارستان دامپزشکی',
  'petshop': 'پت‌شاپ / مرکز نگهداری',
  'other': 'سایر',
};

const tierLabels = {'gold': 'طلایی', 'silver': 'نقره‌ای', 'bronze': 'برنزی'};
const tierColors = {'gold': Color(0xFFE2B33C), 'silver': Color(0xFF9EA7B3), 'bronze': Color(0xFFC07A4A)};

class CategoryInfo {
  final String label;
  final String en;
  final IconData icon;
  final Color color;
  const CategoryInfo(this.label, this.en, this.icon, this.color);
}

const categories = {
  'hematology': CategoryInfo('هماتولوژی', 'Hematology', Icons.bloodtype_rounded, MP.pinkDeep),
  'biochemistry': CategoryInfo('بیوشیمی', 'Biochemistry', Icons.science_rounded, MP.lavenderDeep),
  'urinalysis': CategoryInfo('آنالیز ادرار', 'Urinalysis', Icons.water_drop_rounded, MP.warning),
  'fluid': CategoryInfo('آنالیز مایعات', 'Fluid Analysis', Icons.opacity_rounded, Color(0xFF4F8FD8)),
  'culture': CategoryInfo('کشت و آنتی‌بیوگرام', 'Culture & Antibiogram', Icons.coronavirus_rounded, MP.mintDeep),
  'hormone': CategoryInfo('هورمون', 'Hormone', Icons.monitor_heart_rounded, MP.peachDeep),
  'pathology': CategoryInfo('بیوپسی و نکروپسی', 'Biopsy & Necropsy', Icons.biotech_rounded, Color(0xFF8E6E5B)),
  'pcr': CategoryInfo('PCR', 'PCR', Icons.hub_rounded, Color(0xFF3E8EA8)),
  'parasitology': CategoryInfo('انگل‌شناسی', 'Parasitology', Icons.bug_report_rounded, Color(0xFF7A9A3C)),
  'serology': CategoryInfo('سرولوژی', 'Serology', Icons.vaccines_rounded, Color(0xFFB5568A)),
  'other': CategoryInfo('سایر', 'Other', Icons.more_horiz_rounded, Colors.blueGrey),
};

CategoryInfo categoryInfo(String c) => categories[c] ?? categories['other']!;
