import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melopet/theme.dart';
import 'package:melopet/utils/schedule.dart';
import 'package:melopet/widgets/work_schedule.dart';

void main() {
  Future<GlobalKey<FormState>> pumpField(WidgetTester t, WorkSchedule initial, ValueChanged<WorkSchedule> onChanged) async {
    final key = GlobalKey<FormState>();
    t.view.physicalSize = const Size(393, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: const Locale('fa', 'IR'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                key: key,
                child: WorkScheduleField(initial: initial, onChanged: onChanged),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    return key;
  }

  testWidgets('time is chosen with wheels, not typed', (t) async {
    var value = const WorkSchedule(days: {0, 1, 2}, from: 8 * 60, to: 18 * 60, closedOnHolidays: false);
    await pumpField(t, value, (s) => value = s);
    expect(find.byType(TextField), findsNothing, reason: 'no free typing anywhere in the schedule');

    await t.tap(find.text('شروع کار'));
    await t.pumpAndSettle();
    expect(find.text('ساعت شروع کار'), findsOneWidget);
    // two wheels: hours and minutes
    expect(find.byType(ListWheelScrollView), findsNWidgets(2));

    // scroll the hour wheel two steps forward (08 → 10) and confirm
    await t.drag(find.byType(ListWheelScrollView).first, const Offset(0, -96));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('تایید'));
    await t.pumpAndSettle();
    expect(value.from, 10 * 60);
    expect(value.to, 18 * 60);
  });

  testWidgets('presets, day chips and the holiday question work, and the question cannot be skipped', (t) async {
    var value = const WorkSchedule();
    final form = await pumpField(t, value, (s) => value = s);

    // nothing chosen → the form refuses
    expect(form.currentState!.validate(), isFalse);

    await t.tap(find.text('۰۸:۰۰ تا ۲۰:۰۰'));
    await t.pump();
    expect((value.from, value.to), (8 * 60, 20 * 60));

    await t.tap(find.text('شنبه تا پنجشنبه'));
    await t.pump();
    expect(value.days, {0, 1, 2, 3, 4, 5});
    // Friday is off → the summary says so
    expect(value.summary, contains('جمعه‌ها تعطیل'));

    // still invalid: the holiday answer is missing
    expect(form.currentState!.validate(), isFalse);
    await t.pump();
    expect(find.textContaining('تعطیلات رسمی'), findsWidgets);

    await t.tap(find.text('خیر، باز هستیم'));
    await t.pump();
    expect(value.closedOnHolidays, isFalse);
    expect(form.currentState!.validate(), isTrue);

    // a day can be toggled off again
    await t.tap(find.text('شنبه').first);
    await t.pump();
    expect(value.days.contains(0), isFalse);
  });
}
