import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';

import '../../services/api.dart';
import '../../services/export.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/form_bits.dart';
import '../../widgets/glass.dart';
import '../../widgets/logo.dart';
import '../shared/contact_screen.dart';
import '../shared/notifications_screen.dart';
import 'price_list_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.me;
    if (me == null) return const SizedBox();
    final logo = me.getStringValue('logo');
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 130),
        children: [
          Glass(
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: logo.isNotEmpty
                      ? Image.network(Api.fileUrl(me, 'logo', thumb: '200x200').toString(), width: 64, height: 64, fit: BoxFit.cover)
                      : const MelopetLogo(size: 64),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(me.getStringValue('clinic_name'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                      Text('دکتر ${me.getStringValue('doctor_name')}'),
                      Text(faNum(me.getStringValue('mobile')), style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            state.approved || state.isAdmin ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                            size: 16,
                            color: state.approved || state.isAdmin ? MP.success : MP.warning,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            state.isAdmin ? 'مدیر آزمایشگاه' : (state.approved ? 'همکار تایید شده' : 'در انتظار تایید'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('حساب و مجموعه'),
          _tile(
            context,
            Icons.edit_rounded,
            MP.pinkDeep,
            'ویرایش مشخصات مجموعه',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())),
          ),
          if (!state.isAdmin)
            _tile(
              context,
              Icons.article_rounded,
              MP.lavenderDeep,
              'سربرگ و قالب PDF',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LetterheadScreen())),
            ),
          if (!state.isAdmin)
            _tile(
              context,
              Icons.price_change_rounded,
              MP.mintDeep,
              'تعرفه آزمایش‌ها',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PriceListScreen())),
            ),
          _tile(
            context,
            Icons.notifications_rounded,
            MP.peachDeep,
            'اعلان‌ها',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          ),
          _tile(context, Icons.lock_reset_rounded, MP.sky, 'تغییر رمز عبور', () => _changePassword(context)),
          const SectionTitle('ظاهر برنامه'),
          Glass(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('روشن')),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('خودکار')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('تیره')),
              ],
              selected: {state.themeMode},
              onSelectionChanged: (s) => state.setTheme(s.first),
            ),
          ),
          const SectionTitle('پشتیبانی'),
          _tile(
            context,
            Icons.support_agent_rounded,
            MP.mintDeep,
            'تماس با ما',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactScreen())),
          ),
          _tile(context, Icons.logout_rounded, MP.danger, 'خروج از حساب', () async {
            if (await confirm(context, 'خروج', 'از حساب کاربری خارج می‌شوید؟', ok: 'خروج')) {
              await state.logout();
            }
          }),
          const SizedBox(height: 16),
          const Center(child: Text('ملوپت • نسخه ۱.۰.۰', style: TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, Color color, String title, VoidCallback onTap) => Glass(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    onTap: onTap,
    child: Row(
      children: [
        GlassIcon(icon, color: color, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const Icon(Icons.arrow_forward_ios_rounded, size: 14),
      ],
    ),
  );

  Future<void> _changePassword(BuildContext context) async {
    final old = TextEditingController();
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تغییر رمز عبور'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Field(old, 'رمز فعلی', obscure: true, ltr: true, required: true),
              Field(p1, 'رمز جدید', obscure: true, ltr: true, required: true, validator: (s) => s.length < 8 ? 'حداقل ۸ کاراکتر' : null),
              Field(p2, 'تکرار رمز جدید', obscure: true, ltr: true, required: true, validator: (s) => s != p1.text ? 'یکسان نیست' : null),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => form.currentState!.validate() ? Navigator.pop(c, true) : null, child: const Text('ذخیره')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final me = Api.me!;
      final mobile = me.getStringValue('mobile');
      await Api.pb.collection('users').update(me.id, body: {'oldPassword': old.text, 'password': p1.text, 'passwordConfirm': p2.text});
      await Api.pb.collection('users').authWithPassword(mobile, p1.text);
      if (context.mounted) toast(context, 'رمز عبور تغییر کرد');
    } catch (e) {
      if (context.mounted) toast(context, Api.error(e), error: true);
    }
  }
}

/// Edit clinic info (also used by admins to edit any clinic via [user]).
class EditProfileScreen extends StatefulWidget {
  final RecordModel? user;
  const EditProfileScreen({super.key, this.user});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final RecordModel u = widget.user ?? Api.me!;
  late final c = {
    for (final f in [
      'clinic_name',
      'doctor_name',
      'council_no',
      'phone',
      'contact_person',
      'contact_mobile',
      'city',
      'address',
      'working_hours',
      'instagram',
      'email',
    ])
      f: TextEditingController(text: u.getStringValue(f)),
  };
  late String type = u.getStringValue('clinic_type').isEmpty ? 'clinic' : u.getStringValue('clinic_type');
  PickedBytes? logo;
  final _form = GlobalKey<FormState>();
  bool _saving = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = {for (final e in c.entries) e.key: enNum(e.value.text.trim())};
      if (body['email']!.isEmpty) body.remove('email');
      await Api.pb
          .collection('users')
          .update(
            u.id,
            body: {...body, 'clinic_type': type, 'name': body['doctor_name']},
            files: [if (logo != null) logo!.toMultipart('logo')],
          );
      if (!mounted) return;
      if (widget.user == null) await context.read<AppState>().reloadMe();
      if (mounted) {
        toast(context, 'ذخیره شد');
        Navigator.pop(context, true);
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
      title: 'مشخصات مجموعه',
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ImagePickTile(
              title: 'لوگو',
              subtitle: 'برای تغییر لمس کنید',
              file: logo,
              currentUrl: u.getStringValue('logo').isNotEmpty ? Api.fileUrl(u, 'logo', thumb: '200x200').toString() : null,
              previewHeight: 80,
              onPick: () async {
                final f = await pickOne(imagesOnly: true);
                if (f != null) setState(() => logo = f);
              },
            ),
            ChoiceRow(options: clinicTypeLabels, value: type, onChanged: (v) => setState(() => type = v)),
            const SizedBox(height: 14),
            Field(c['clinic_name']!, 'نام مجموعه', required: true, icon: Icons.local_hospital_rounded),
            Field(c['doctor_name']!, 'نام دکتر مسئول', required: true, icon: Icons.badge_rounded),
            Field(c['council_no']!, 'شماره نظام دامپزشکی', ltr: true, icon: Icons.verified_user_rounded),
            Field(c['phone']!, 'تلفن ثابت', ltr: true, required: true, icon: Icons.call_rounded),
            Field(c['contact_person']!, 'مسئول تحویل نمونه', icon: Icons.person_pin_rounded),
            Field(c['contact_mobile']!, 'موبایل مسئول تحویل', ltr: true, icon: Icons.phone_android_rounded),
            Field(c['city']!, 'شهر', icon: Icons.location_city_rounded),
            Field(c['address']!, 'آدرس', maxLines: 3, required: true, icon: Icons.location_on_rounded),
            Field(c['working_hours']!, 'ساعات کاری', icon: Icons.schedule_rounded),
            Field(c['instagram']!, 'اینستاگرام', ltr: true, icon: Icons.camera_alt_rounded),
            Field(c['email']!, 'ایمیل', ltr: true, icon: Icons.alternate_email_rounded),
            const SizedBox(height: 8),
            GradientButton(label: 'ذخیره', icon: Icons.save_rounded, loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

/// Upload letterhead + set the printable area; preview the generated PDF.
class LetterheadScreen extends StatefulWidget {
  const LetterheadScreen({super.key});
  @override
  State<LetterheadScreen> createState() => _LetterheadScreenState();
}

class _LetterheadScreenState extends State<LetterheadScreen> {
  RecordModel get me => Api.me!;
  PickedBytes? _file;
  late double _top = me.getDoubleValue('letterhead_top') > 0 ? me.getDoubleValue('letterhead_top') : 45;
  late double _bottom = me.getDoubleValue('letterhead_bottom') > 0 ? me.getDoubleValue('letterhead_bottom') : 25;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.pb
          .collection('users')
          .update(
            me.id,
            body: {'letterhead_top': _top.round(), 'letterhead_bottom': _bottom.round()},
            files: [if (_file != null) _file!.toMultipart('letterhead')],
          );
      if (!mounted) return;
      await context.read<AppState>().reloadMe();
      _file = null;
      if (mounted) toast(context, 'سربرگ ذخیره شد');
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    await Api.pb.collection('users').update(me.id, body: {'letterhead': null});
    if (mounted) await context.read<AppState>().reloadMe();
    setState(() {});
  }

  Future<void> _preview() async {
    await _save();
    final sample = RecordModel.fromJson({
      'id': 'sample',
      'code': 'MP-10000',
      'pet_name': 'ملو',
      'species': 'cat',
      'breed': 'پرشین',
      'age': '۳ سال',
      'sex': 'female',
      'owner_name': 'نمونه',
      'created': DateTime.now().toUtc().toIso8601String(),
      'lab_comment': 'این یک پیش‌نمایش است.',
      'results': {
        'tests': [
          {
            'name': 'ALT (SGPT)',
            'category': 'biochemistry',
            'params': [
              {'key': 'alt', 'name': 'ALT', 'unit': 'U/L', 'low': 12, 'high': 130, 'value': '145'},
            ],
          },
          {
            'name': 'Glucose',
            'category': 'biochemistry',
            'params': [
              {'key': 'glu', 'name': 'Glucose', 'unit': 'mg/dL', 'low': 71, 'high': 159, 'value': '98'},
            ],
          },
        ],
      },
    });
    if (!mounted) return;
    final bytes = await Export.resultPdfFor(sample, Api.me, settings: context.read<AppState>().settings);
    await Export.printPdf(bytes, 'preview.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final current = me.getStringValue('letterhead');
    return MPScaffold(
      title: 'سربرگ مجموعه',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Glass(
            child: Text(
              'تصویر سربرگ A4 مجموعه خود را (JPG یا PNG، ترجیحا ۲۴۸۰×۳۵۰۸ پیکسل) آپلود کنید. '
              'جواب آزمایش‌ها روی این سربرگ ساخته می‌شود و مستقیم قابل ارسال برای صاحب حیوان است.\n'
              'با اسلایدرها فاصله متن از بالا و پایین سربرگ را تنظیم کنید تا روی لوگو و آدرس نیفتد.',
              style: TextStyle(fontSize: 12.5, height: 1.7),
            ),
          ),
          const SizedBox(height: 12),
          ImagePickTile(
            title: current.isEmpty && _file == null ? 'آپلود سربرگ' : 'تغییر سربرگ',
            subtitle: 'برای انتخاب تصویر لمس کنید',
            file: _file,
            currentUrl: current.isNotEmpty ? Api.fileUrl(me, 'letterhead').toString() : null,
            previewHeight: 260,
            onPick: () async {
              final f = await pickOne(imagesOnly: true);
              if (f != null) setState(() => _file = f);
            },
          ),
          Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('فاصله از بالا: ${faNum(_top.round())} میلی‌متر'),
                Slider(value: _top, min: 10, max: 120, divisions: 110, onChanged: (v) => setState(() => _top = v)),
                Text('فاصله از پایین: ${faNum(_bottom.round())} میلی‌متر'),
                Slider(value: _bottom, min: 10, max: 100, divisions: 90, onChanged: (v) => setState(() => _bottom = v)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _preview,
                  icon: const Icon(Icons.visibility_rounded),
                  label: const Text('پیش‌نمایش PDF'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GradientButton(label: 'ذخیره', icon: Icons.save_rounded, loading: _saving, onPressed: _save),
              ),
            ],
          ),
          if (current.isNotEmpty)
            TextButton.icon(
              onPressed: _remove,
              icon: const Icon(Icons.delete_outline_rounded, color: MP.danger),
              label: const Text('حذف سربرگ', style: TextStyle(color: MP.danger)),
            ),
        ],
      ),
    );
  }
}
