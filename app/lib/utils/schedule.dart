import 'format.dart';

/// Weekly working schedule of a clinic (or of the lab).
///
/// Days use the Iranian week: 0 = شنبه … 6 = جمعه.
/// Times are minutes since midnight.
class WorkSchedule {
  static const dayNames = ['شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه'];

  final Set<int> days;
  final int? from;
  final int? to;

  /// null = not answered yet (the form refuses to continue until it is).
  final bool? closedOnHolidays;

  const WorkSchedule({this.days = const {}, this.from, this.to, this.closedOnHolidays});

  bool get isAllDay => from == 0 && to == 1439;

  /// Why the schedule can't be saved, or null when it is complete.
  String? get problem {
    if (days.isEmpty) return 'حداقل یک روز کاری را انتخاب کنید';
    if (from == null || to == null) return 'ساعت شروع و پایان کار را انتخاب کنید';
    if (to! <= from!) return 'ساعت پایان باید بعد از ساعت شروع باشد';
    if (closedOnHolidays == null) return 'مشخص کنید در تعطیلات رسمی تعطیل هستید یا نه';
    return null;
  }

  WorkSchedule copyWith({Set<int>? days, int? from, int? to, bool? closedOnHolidays, bool clearFrom = false, bool clearTo = false}) =>
      WorkSchedule(
        days: days ?? this.days,
        from: clearFrom ? null : (from ?? this.from),
        to: clearTo ? null : (to ?? this.to),
        closedOnHolidays: closedOnHolidays ?? this.closedOnHolidays,
      );

  static String time(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return faNum('$h:$m');
  }

  /// "شنبه تا چهارشنبه" / "شنبه، دوشنبه و پنجشنبه" / "همه روزه"
  String get daysText {
    if (days.isEmpty) return '';
    if (days.length == 7) return 'همه روزه';
    final sorted = days.toList()..sort();
    // group consecutive runs
    final runs = <List<int>>[];
    for (final d in sorted) {
      if (runs.isNotEmpty && runs.last.last == d - 1) {
        runs.last.add(d);
      } else {
        runs.add([d]);
      }
    }
    final parts = runs.map((r) {
      if (r.length >= 3) return '${dayNames[r.first]} تا ${dayNames[r.last]}';
      return r.map((d) => dayNames[d]).join(' و ');
    }).toList();
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join('، ')} و ${parts.last}';
  }

  /// One readable line, also stored in the plain-text `working_hours` field.
  String get summary {
    if (problem != null && days.isEmpty && from == null) return '';
    final b = <String>[];
    if (days.isNotEmpty) b.add(daysText);
    if (from != null && to != null) b.add(isAllDay ? '۲۴ ساعته' : '${time(from!)} تا ${time(to!)}');
    final off = <int>[
      for (var d = 0; d < 7; d++)
        if (!days.contains(d)) d,
    ];
    if (off.isNotEmpty && off.length <= 2) b.add('${off.map((d) => '${dayNames[d]}‌ها').join(' و ')} تعطیل');
    if (closedOnHolidays == true) b.add('تعطیلات رسمی تعطیل');
    if (closedOnHolidays == false) b.add('تعطیلات رسمی باز');
    return b.join(' • ');
  }

  Map<String, dynamic> toJson() => {
    'days': (days.toList()..sort()),
    'from': from == null ? null : time24(from!),
    'to': to == null ? null : time24(to!),
    'closed_on_holidays': closedOnHolidays,
  };

  static String time24(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  static int? _parse(dynamic v) {
    if (v is! String) return null;
    final p = v.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    return (h == null || m == null) ? null : h * 60 + m;
  }

  factory WorkSchedule.fromJson(dynamic j) {
    if (j is! Map) return const WorkSchedule();
    return WorkSchedule(
      days: {
        for (final d in (j['days'] as List? ?? const []))
          if (d is int && d >= 0 && d <= 6) d,
      },
      from: _parse(j['from']),
      to: _parse(j['to']),
      closedOnHolidays: j['closed_on_holidays'] is bool ? j['closed_on_holidays'] as bool : null,
    );
  }
}
