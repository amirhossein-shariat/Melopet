import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/form_bits.dart';
import '../../widgets/glass.dart';
import '../../widgets/location.dart';

import 'package:latlong2/latlong.dart';

/// One-time sign-up of a clinic / hospital (4 short steps).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int _step = 0;
  bool _loading = false;
  final _forms = List.generate(4, (_) => GlobalKey<FormState>());

  // step 1 — account
  final mobile = TextEditingController();
  final pass = TextEditingController();
  final pass2 = TextEditingController();
  // step 2 — center
  String clinicType = 'clinic';
  final clinicName = TextEditingController();
  final doctorName = TextEditingController();
  final councilNo = TextEditingController();
  final phone = TextEditingController();
  final contactPerson = TextEditingController();
  final contactMobile = TextEditingController();
  // step 3 — address
  final city = TextEditingController(text: 'تهران');
  final address = TextEditingController();
  final hours = TextEditingController();
  final email = TextEditingController();
  final instagram = TextEditingController();
  // step 4 — branding
  LatLng? location;
  PickedBytes? logo;
  PickedBytes? letterhead;
  bool accepted = false;

  static const _titles = ['حساب کاربری', 'مشخصات مرکز', 'آدرس و ساعات کاری', 'لوگو و سربرگ'];
  static const _icons = [Icons.person_rounded, Icons.local_hospital_rounded, Icons.location_on_rounded, Icons.image_rounded];

  Future<void> _next() async {
    if (!_forms[_step].currentState!.validate()) return;
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    if (!accepted) {
      toast(context, 'لطفا قوانین همکاری را تایید کنید', error: true);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final m = enNum(mobile.text.trim());
      final files = <http.MultipartFile>[
        if (logo != null) logo!.toMultipart('logo'),
        if (letterhead != null) letterhead!.toMultipart('letterhead'),
      ];
      await Api.pb
          .collection('users')
          .create(
            body: {
              'mobile': m,
              'password': pass.text,
              'passwordConfirm': pass2.text,
              if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
              'emailVisibility': false,
              'name': doctorName.text.trim(),
              'clinic_type': clinicType,
              'clinic_name': clinicName.text.trim(),
              'doctor_name': doctorName.text.trim(),
              'council_no': enNum(councilNo.text.trim()),
              'phone': enNum(phone.text.trim()),
              'contact_person': contactPerson.text.trim(),
              'contact_mobile': enNum(contactMobile.text.trim()),
              'city': city.text.trim(),
              'address': address.text.trim(),
              if (location != null) 'location': geoJson(location!),
              'working_hours': hours.text.trim(),
              'instagram': instagram.text.trim(),
              'letterhead_top': 45,
              'letterhead_bottom': 25,
              'profile_completed': true,
            },
            files: files,
          );
      await Api.pb.collection('users').authWithPassword(m, pass.text);
      if (!mounted) return;
      await context.read<AppState>().onLoggedIn();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (did, _) {
        if (!did) setState(() => _step--);
      },
      child: MPScaffold(
        title: 'ثبت‌نام همکار',
        body: SafeArea(
          child: Column(
            children: [
              // progress
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: i <= _step ? cs.primary : cs.primary.withValues(alpha: .15),
                          ),
                        ),
                      ),
                      if (i < 3) const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    GlassIcon(_icons[_step], size: 44),
                    const SizedBox(width: 12),
                    Text(
                      'مرحله ${faNum(_step + 1)} از ۴ — ${_titles[_step]}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(key: ValueKey(_step), child: _stepBody()),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    if (_step > 0) ...[
                      OutlinedButton(onPressed: () => setState(() => _step--), child: const Text('قبلی')),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: GradientButton(
                        label: _step == 3 ? 'ثبت نهایی' : 'ادامه',
                        icon: _step == 3 ? Icons.check_rounded : Icons.arrow_forward_rounded,
                        loading: _loading,
                        onPressed: _next,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return Form(
          key: _forms[0],
          child: Column(
            children: [
              Field(
                mobile,
                'شماره موبایل (نام کاربری)',
                icon: Icons.phone_iphone_rounded,
                required: true,
                ltr: true,
                keyboard: TextInputType.phone,
                hint: '09xxxxxxxxx',
                validator: mobileValidator,
              ),
              Field(
                pass,
                'رمز عبور',
                icon: Icons.lock_rounded,
                required: true,
                ltr: true,
                obscure: true,
                validator: (s) => s.length < 8 ? 'حداقل ۸ کاراکتر' : null,
              ),
              Field(
                pass2,
                'تکرار رمز عبور',
                icon: Icons.lock_outline_rounded,
                required: true,
                ltr: true,
                obscure: true,
                validator: (s) => s != pass.text ? 'رمزها یکسان نیستند' : null,
              ),
              const _Hint('با همین شماره موبایل و رمز عبور وارد اپ می‌شوید.'),
            ],
          ),
        );
      case 1:
        return Form(
          key: _forms[1],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('نوع مرکز', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ChoiceRow(options: clinicTypeLabels, value: clinicType, onChanged: (v) => setState(() => clinicType = v)),
              const SizedBox(height: 16),
              Field(clinicName, 'نام کلینیک / بیمارستان', icon: Icons.local_hospital_rounded, required: true),
              Field(doctorName, 'نام دکتر مسئول مجموعه', icon: Icons.badge_rounded, required: true),
              Field(
                councilNo,
                'شماره نظام دامپزشکی',
                icon: Icons.verified_user_rounded,
                ltr: true,
                keyboard: TextInputType.number,
                hint: 'برای تایید سریع‌تر حساب',
              ),
              Field(
                phone,
                'تلفن ثابت مجموعه',
                icon: Icons.call_rounded,
                required: true,
                ltr: true,
                keyboard: TextInputType.phone,
                validator: phoneValidator,
              ),
              Field(
                contactPerson,
                'نام مسئول تحویل نمونه / پذیرش',
                icon: Icons.person_pin_rounded,
                hint: 'شخصی که پیک با او هماهنگ می‌کند',
              ),
              Field(
                contactMobile,
                'موبایل مسئول تحویل نمونه',
                icon: Icons.phone_android_rounded,
                ltr: true,
                keyboard: TextInputType.phone,
                validator: mobileValidator,
              ),
            ],
          ),
        );
      case 2:
        return Form(
          key: _forms[2],
          child: Column(
            children: [
              Field(city, 'شهر', icon: Icons.location_city_rounded, required: true),
              LocationField(title: 'لوکیشن مجموعه روی نقشه', value: location, onChanged: (p) => setState(() => location = p)),
              Field(address, 'آدرس کامل (برای مراجعه پیک)', icon: Icons.location_on_rounded, required: true, maxLines: 3),
              Field(hours, 'ساعات کاری', icon: Icons.schedule_rounded, hint: 'مثلا: هر روز ۹ تا ۲۱'),
              Field(email, 'ایمیل (اختیاری)', icon: Icons.alternate_email_rounded, ltr: true, keyboard: TextInputType.emailAddress),
              Field(instagram, 'اینستاگرام (اختیاری)', icon: Icons.camera_alt_rounded, ltr: true),
            ],
          ),
        );
      default:
        return Form(
          key: _forms[3],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ImagePickTile(
                title: 'لوگوی مجموعه (اختیاری)',
                subtitle: 'در پروفایل و چت نمایش داده می‌شود',
                file: logo,
                previewHeight: 90,
                onPick: () async {
                  final f = await pickOne(imagesOnly: true);
                  if (f != null) setState(() => logo = f);
                },
                onClear: () => setState(() => logo = null),
              ),
              ImagePickTile(
                title: 'سربرگ مجموعه (اختیاری)',
                subtitle: 'تصویر A4 سربرگ شما؛ جواب آزمایش روی آن چاپ و آماده ارسال می‌شود',
                file: letterhead,
                previewHeight: 200,
                onPick: () async {
                  final f = await pickOne(imagesOnly: true);
                  if (f != null) setState(() => letterhead = f);
                },
                onClear: () => setState(() => letterhead = null),
              ),
              CheckboxListTile(
                value: accepted,
                onChanged: (v) => setState(() => accepted = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('اطلاعات وارد شده صحیح است و قوانین همکاری با آزمایشگاه ملوپت را می‌پذیرم.'),
              ),
              const _Hint(
                'پس از ثبت‌نام، حساب شما توسط آزمایشگاه بررسی و تایید می‌شود. '
                'لوگو و سربرگ را بعدا هم از بخش پروفایل می‌توانید تغییر دهید.',
              ),
            ],
          ),
        );
    }
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
      ],
    ),
  );
}
