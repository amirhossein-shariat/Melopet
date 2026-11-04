import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../utils/format.dart';
import '../utils/schedule.dart';
import 'glass.dart';

/// Picks the working schedule without any typing:
///  * start / end time with wheels (15-minute steps) + quick presets
///  * working days as tappable chips + quick presets
///  * "closed on official holidays?" as two big cards that must be answered
class WorkScheduleField extends FormField<WorkSchedule> {
  WorkScheduleField({super.key, required WorkSchedule initial, required ValueChanged<WorkSchedule> onChanged})
    : super(
        initialValue: initial,
        validator: (v) => (v ?? const WorkSchedule()).problem,
        builder: (state) {
          void set(WorkSchedule s) {
            state.didChange(s);
            onChanged(s);
          }

          return _ScheduleBody(value: state.value ?? const WorkSchedule(), error: state.errorText, onChange: set);
        },
      );
}

class _ScheduleBody extends StatelessWidget {
  final WorkSchedule value;
  final String? error;
  final ValueChanged<WorkSchedule> onChange;
  const _ScheduleBody({required this.value, required this.error, required this.onChange});

  static const _timePresets = [(8 * 60, 16 * 60), (9 * 60, 18 * 60), (8 * 60, 20 * 60), (9 * 60, 21 * 60), (0, 1439)];

  Future<void> _pickTime(BuildContext context, {required bool start}) async {
    final initial = (start ? value.from : value.to) ?? (start ? 8 * 60 : 18 * 60);
    final picked = await showGlassSheet<int>(
      context,
      (c) => _TimeWheelSheet(title: start ? 'ساعت شروع کار' : 'ساعت پایان کار', initial: initial),
    );
    if (picked == null) return;
    onChange(start ? value.copyWith(from: picked) : value.copyWith(to: picked));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasError = error != null;
    return Glass(
      margin: const EdgeInsets.only(bottom: 12),
      tint: hasError ? MP.danger.withValues(alpha: .08) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const GlassIcon(Icons.schedule_rounded, size: 42, color: MP.warning),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('ساعت و روزهای کاری *', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ---- times
          Row(
            children: [
              Expanded(
                child: _TimeButton(label: 'شروع کار', minutes: value.from, onTap: () => _pickTime(context, start: true)),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, size: 18)),
              Expanded(
                child: _TimeButton(label: 'پایان کار', minutes: value.to, onTap: () => _pickTime(context, start: false)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _timePresets)
                MPChoiceChip(
                  label: p.$1 == 0 && p.$2 == 1439 ? '۲۴ ساعته' : '${WorkSchedule.time(p.$1)} تا ${WorkSchedule.time(p.$2)}',
                  selected: value.from == p.$1 && value.to == p.$2,
                  onSelected: (_) => onChange(value.copyWith(from: p.$1, to: p.$2)),
                ),
            ],
          ),

          const Divider(height: 28),

          // ---- days
          Text(
            'روزهای کاری',
            style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'روزهایی که باز هستید را لمس کنید؛ روزهای انتخاب‌نشده «تعطیل» حساب می‌شوند.',
            style: TextStyle(fontSize: 12, color: muted(context)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var d = 0; d < 7; d++)
                MPChoiceChip(
                  label: WorkSchedule.dayNames[d],
                  selected: value.days.contains(d),
                  onSelected: (on) {
                    HapticFeedback.selectionClick();
                    final next = {...value.days};
                    on ? next.add(d) : next.remove(d);
                    onChange(value.copyWith(days: next));
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _QuickAction('شنبه تا چهارشنبه', () => onChange(value.copyWith(days: {0, 1, 2, 3, 4}))),
              _QuickAction('شنبه تا پنجشنبه', () => onChange(value.copyWith(days: {0, 1, 2, 3, 4, 5}))),
              _QuickAction('همه روزه', () => onChange(value.copyWith(days: {0, 1, 2, 3, 4, 5, 6}))),
            ],
          ),

          const Divider(height: 28),

          // ---- holidays (must be answered)
          Text(
            'در تعطیلات رسمی تعطیل هستید؟',
            style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _AnswerCard(
                  icon: Icons.event_busy_rounded,
                  label: 'بله، تعطیل هستیم',
                  selected: value.closedOnHolidays == true,
                  onTap: () => onChange(value.copyWith(closedOnHolidays: true)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AnswerCard(
                  icon: Icons.event_available_rounded,
                  label: 'خیر، باز هستیم',
                  selected: value.closedOnHolidays == false,
                  onTap: () => onChange(value.copyWith(closedOnHolidays: false)),
                ),
              ),
            ],
          ),

          if (value.summary.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: .55), borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: cs.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value.summary,
                      style: TextStyle(fontSize: 12.5, height: 1.7, color: cs.onPrimaryContainer, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 18, color: MP.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error!,
                      style: TextStyle(fontSize: 12.5, color: readable(context, MP.danger), fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickAction(this.label, this.onTap);

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
    child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
  );
}

class _TimeButton extends StatelessWidget {
  final String label;
  final int? minutes;
  final VoidCallback onTap;
  const _TimeButton({required this.label, required this.minutes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Glass(
      onTap: onTap,
      radius: 16,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: muted(context))),
          const SizedBox(height: 4),
          Text(
            minutes == null ? 'انتخاب' : WorkSchedule.time(minutes!),
            style: TextStyle(
              fontSize: minutes == null ? 15 : 24,
              fontWeight: FontWeight.w900,
              color: minutes == null ? cs.primary : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AnswerCard({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? cs.primary : cs.onSurface.withValues(alpha: .2), width: selected ? 2 : 1.2),
        color: selected ? cs.primaryContainer : Colors.transparent,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(selected ? Icons.check_circle_rounded : icon, color: selected ? cs.primary : cs.onSurface),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: selected ? cs.onPrimaryContainer : cs.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two scroll wheels (hours, minutes in 15-minute steps).
class _TimeWheelSheet extends StatefulWidget {
  final String title;
  final int initial;
  const _TimeWheelSheet({required this.title, required this.initial});

  @override
  State<_TimeWheelSheet> createState() => _TimeWheelSheetState();
}

class _TimeWheelSheetState extends State<_TimeWheelSheet> {
  static const _step = 15;
  late int _h = widget.initial ~/ 60;
  late int _m = (widget.initial % 60) ~/ _step;
  late final _hc = FixedExtentScrollController(initialItem: _h);
  late final _mc = FixedExtentScrollController(initialItem: _m);

  @override
  void dispose() {
    _hc.dispose();
    _mc.dispose();
    super.dispose();
  }

  Widget _wheel(FixedExtentScrollController c, int count, String Function(int) text, ValueChanged<int> onChanged, int selected) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 96,
      height: 190,
      child: ListWheelScrollView.useDelegate(
        controller: c,
        itemExtent: 48,
        diameterRatio: 1.5,
        perspective: .004,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) {
          HapticFeedback.selectionClick();
          onChanged(i);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (context, i) => Center(
            child: Text(
              text(i),
              style: TextStyle(
                fontSize: i == selected ? 30 : 22,
                fontWeight: i == selected ? FontWeight.w900 : FontWeight.w500,
                color: i == selected ? cs.primary : muted(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 10),
          Stack(
            alignment: Alignment.center,
            children: [
              // highlight band behind the selected row
              Container(
                height: 52,
                decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: .7), borderRadius: BorderRadius.circular(16)),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _wheel(_hc, 24, (i) => faNum(i.toString().padLeft(2, '0')), (i) => setState(() => _h = i), _h),
                    Text(
                      ':',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: cs.primary),
                    ),
                    _wheel(_mc, 60 ~/ _step, (i) => faNum((i * _step).toString().padLeft(2, '0')), (i) => setState(() => _m = i), _m),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GradientButton(
            label: 'تایید ${WorkSchedule.time(_h * 60 + _m * _step)}',
            icon: Icons.check_rounded,
            onPressed: () => Navigator.pop(context, _h * 60 + _m * _step),
          ),
        ],
      ),
    );
  }
}
