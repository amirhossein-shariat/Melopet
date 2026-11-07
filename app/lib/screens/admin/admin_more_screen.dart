import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/form_bits.dart';
import '../../widgets/glass.dart';
import '../../utils/schedule.dart';
import '../../widgets/location.dart';
import '../../widgets/work_schedule.dart';

import 'package:latlong2/latlong.dart';

import '../clinic/profile_screen.dart';
import '../shared/promotions_screen.dart';
import 'accounting_screen.dart';
import 'broadcast_screen.dart';
import 'tests_screen.dart';

class AdminMoreScreen extends StatelessWidget {
  const AdminMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final tools = <(IconData, Color, String, VoidCallback)>[
      (Icons.account_balance_wallet_rounded, MP.mintDeep, 'حسابداری و مطالبات همکاران', () => push(const AccountingScreen())),
      (Icons.science_rounded, MP.lavenderDeep, 'آزمایش‌ها و تعرفه‌ها', () => push(const TestsScreen())),
      (
        Icons.local_offer_rounded,
        MP.pinkDeep,
        'تخفیف‌ها و پیشنهادها',
        () => push(const MPScaffold(title: 'پیشنهادها', body: PromotionsScreen())),
      ),
      (Icons.campaign_rounded, MP.peachDeep, 'اعلان همگانی', () => push(const BroadcastScreen())),
      (Icons.storefront_rounded, MP.mintDeep, 'اطلاعات تماس آزمایشگاه', () => push(const LabSettingsScreen())),
      (
        Icons.manage_accounts_rounded,
        MP.sky,
        'حساب کاربری، ظاهر و خروج',
        () => push(const MPScaffold(title: 'حساب کاربری', body: ProfileScreen())),
      ),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 130),
          children: [
            const Text('ابزارهای مدیریت', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            for (final t in tools)
              Glass(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                onTap: t.$4,
                child: Row(
                  children: [
                    GlassIcon(t.$1, color: t.$2, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(t.$3, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  ],
                ),
              ),
            const Glass(
              margin: EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                'برای تعریف ادمین جدید، حذف کاربران و پشتیبان‌گیری از داشبورد سرور (آدرس سرور + /_/) استفاده کنید.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edit the lab's own contact info shown in "تماس با ما".
class LabSettingsScreen extends StatefulWidget {
  const LabSettingsScreen({super.key});
  @override
  State<LabSettingsScreen> createState() => _LabSettingsScreenState();
}

class _LabSettingsScreenState extends State<LabSettingsScreen> {
  static const _fields = {
    'lab_name': 'نام آزمایشگاه',
    'slogan': 'شعار',
    'technical_manager': 'مسئول فنی (در PDF چاپ می‌شود)',
    'phone': 'تلفن',
    'mobile': 'موبایل',
    'whatsapp': 'واتساپ',
    'telegram': 'آیدی تلگرام',
    'instagram': 'آیدی اینستاگرام',
    'email': 'ایمیل',
    'website': 'وب‌سایت',
    'address': 'آدرس',
    'card_number': 'شماره کارت برای دریافت پرداخت همکاران',
    'card_holder': 'نام صاحب کارت',
    'bank_name': 'نام بانک',
    'about': 'درباره ما',
  };
  late final s = context.read<AppState>().settings;
  late final c = {for (final f in _fields.keys) f: TextEditingController(text: s?.getStringValue(f))};
  bool _saving = false;
  late LatLng? location = geoOf(s, 'location');
  late WorkSchedule schedule = WorkSchedule.fromJson(s?.data['work_schedule']);
  final _form = GlobalKey<FormState>();

  Future<void> _save() async {
    if (s == null) return;
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await Api.pb
          .collection('settings')
          .update(
            s!.id,
            body: {
              for (final e in c.entries) e.key: e.value.text.trim(),
              'working_hours': schedule.summary,
              'work_schedule': schedule.toJson(),
              if (location != null) 'location': geoJson(location!),
            },
          );
      if (!mounted) return;
      await context.read<AppState>().loadSettings();
      if (mounted) {
        toast(context, 'ذخیره شد');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MPScaffold(
      title: 'اطلاعات آزمایشگاه',
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final e in _fields.entries)
              Field(
                c[e.key]!,
                e.value,
                maxLines: e.key == 'about' || e.key == 'address' ? 3 : 1,
                ltr: const ['phone', 'mobile', 'whatsapp', 'telegram', 'instagram', 'email', 'website', 'card_number'].contains(e.key),
              ),
            WorkScheduleField(initial: schedule, onChanged: (s) => schedule = s),
            LocationField(
              title: 'لوکیشن آزمایشگاه (در «تماس با ما» و مسیریابی نشان)',
              value: location,
              onChanged: (p) => setState(() => location = p),
            ),
            GradientButton(label: 'ذخیره', icon: Icons.save_rounded, loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
