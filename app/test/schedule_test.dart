import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/utils/schedule.dart';

void main() {
  test('summary groups consecutive days and mentions closed days and holidays', () {
    const s = WorkSchedule(days: {0, 1, 2, 3, 4, 5}, from: 8 * 60, to: 20 * 60, closedOnHolidays: true);
    expect(s.summary, 'شنبه تا پنجشنبه • ۰۸:۰۰ تا ۲۰:۰۰ • جمعه‌ها تعطیل • تعطیلات رسمی تعطیل');
    const all = WorkSchedule(days: {0, 1, 2, 3, 4, 5, 6}, from: 0, to: 1439, closedOnHolidays: false);
    expect(all.summary, 'همه روزه • ۲۴ ساعته • تعطیلات رسمی باز');
    const gaps = WorkSchedule(days: {0, 2, 3, 4}, from: 9 * 60 + 30, to: 17 * 60, closedOnHolidays: false);
    expect(gaps.daysText, 'شنبه و دوشنبه تا چهارشنبه');
  });

  test('every missing answer is reported, and a complete schedule has no problem', () {
    expect(const WorkSchedule().problem, isNotNull);
    expect(const WorkSchedule(days: {0}).problem, contains('ساعت'));
    expect(const WorkSchedule(days: {0}, from: 600, to: 500, closedOnHolidays: true).problem, contains('بعد از'));
    // the holiday question can't be skipped
    expect(const WorkSchedule(days: {0}, from: 480, to: 1200).problem, contains('تعطیلات'));
    expect(const WorkSchedule(days: {0}, from: 480, to: 1200, closedOnHolidays: false).problem, isNull);
  });

  test('json round trip', () {
    const s = WorkSchedule(days: {5, 0, 3}, from: 495, to: 1215, closedOnHolidays: true);
    final j = s.toJson();
    expect(j['days'], [0, 3, 5]);
    expect(j['from'], '08:15');
    expect(j['to'], '20:15');
    final back = WorkSchedule.fromJson(j);
    expect(back.days, {0, 3, 5});
    expect(back.from, 495);
    expect(back.to, 1215);
    expect(back.closedOnHolidays, true);
    expect(WorkSchedule.fromJson(null).problem, isNotNull);
    expect(
      WorkSchedule.fromJson({
        'days': [9, -1, 'x'],
      }).days,
      isEmpty,
    );
  });
}
