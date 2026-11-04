import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/glass.dart';
import '../../widgets/logo.dart';
import 'code_screen.dart';

/// One login screen for everyone:
///  * a mobile number (09...) → SMS code → signed in (or registration for new numbers)
///  * the lab's admin ID → password
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _id = TextEditingController();
  final _pass = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscure = true;

  static final _mobileRe = RegExp(r'^09\d{9}$');
  static final _adminIdRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9_.\-]{2,}$');

  String get _value => enNum(_id.text.trim());
  bool get _isAdminId => _adminIdRe.hasMatch(_value);

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_isAdminId) {
        await Api.pb.collection('users').authWithPassword(_value, _pass.text);
        if (mounted) await context.read<AppState>().onLoggedIn();
      } else {
        final testMode = await Api.requestCode(_value);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CodeScreen(mobile: _value, testMode: testMode),
          ),
        );
      }
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Demo only: one-tap sign-in with a sample account.
  Future<void> _quick(String id, String password) async {
    setState(() => _loading = true);
    try {
      await Api.pb.collection('users').authWithPassword(id, password);
      if (mounted) await context.read<AppState>().onLoggedIn();
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _serverDialog() async {
    final c = TextEditingController(text: Api.serverUrl(Api.prefs));
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تنظیمات اتصال'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('آدرس سرور', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: c,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(hintText: 'https://api.example.com'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'demo'),
              icon: const Icon(Icons.science_rounded),
              label: Text(Api.isDemo ? 'خروج از حالت نمایشی' : 'حالت نمایشی (بدون سرور)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('ذخیره')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'demo') {
      await Api.setDemo(!Api.isDemo);
    } else {
      await Api.setDemo(false);
      await Api.setServer(c.text);
    }
    if (mounted) {
      await context.read<AppState>().loadSettings();
      if (mounted) toast(context, choice == 'demo' && Api.isDemo ? 'حالت نمایشی فعال شد' : 'تنظیم شد');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showPassword = _isAdminId;
    return MPScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(
                  children: [
                    GestureDetector(onLongPress: _serverDialog, child: const MelopetLogo(size: 96, withText: true)),
                    const SizedBox(height: 12),
                    Text('پنل همکاران آزمایشگاه دامپزشکی', style: TextStyle(color: cs.onSurface.withValues(alpha: .6))),
                    const SizedBox(height: 28),
                    Glass(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('ورود / ثبت‌نام', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(
                            showPassword ? 'رمز عبور مدیر آزمایشگاه را وارد کنید.' : 'شماره موبایل خود را وارد کنید تا کد تایید پیامک شود.',
                            style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .65)),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _id,
                            keyboardType: TextInputType.visiblePassword,
                            autocorrect: false,
                            textDirection: TextDirection.ltr,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'شماره موبایل',
                              hintText: '09xxxxxxxxx',
                              prefixIcon: Icon(Icons.phone_iphone_rounded),
                            ),
                            validator: (v) {
                              final s = enNum(v?.trim() ?? '');
                              // clinics: mobile number — lab admin: dedicated admin ID
                              return _mobileRe.hasMatch(s) || _adminIdRe.hasMatch(s) ? null : 'شماره موبایل معتبر نیست';
                            },
                            onFieldSubmitted: (_) => showPassword ? null : _submit(),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            child: showPassword
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: TextFormField(
                                      controller: _pass,
                                      obscureText: _obscure,
                                      textDirection: TextDirection.ltr,
                                      decoration: InputDecoration(
                                        labelText: 'رمز عبور',
                                        prefixIcon: const Icon(Icons.lock_rounded),
                                        suffixIcon: IconButton(
                                          icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                                          onPressed: () => setState(() => _obscure = !_obscure),
                                        ),
                                      ),
                                      validator: (v) => (v ?? '').length < 8 ? 'حداقل ۸ کاراکتر' : null,
                                      onFieldSubmitted: (_) => _submit(),
                                    ),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                          const SizedBox(height: 20),
                          GradientButton(
                            label: showPassword ? 'ورود' : 'دریافت کد تایید',
                            icon: showPassword ? Icons.login_rounded : Icons.sms_rounded,
                            loading: _loading,
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Glass(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'اگر قبلا ثبت‌نام نکرده‌اید، بعد از تایید کد، یک بار مشخصات کلینیک یا بیمارستان را وارد می‌کنید و همان لحظه وارد پنل می‌شوید.',
                              style: TextStyle(fontSize: 12.5, height: 1.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (Api.isDemo) ...[
                      const SizedBox(height: 16),
                      Glass(
                        tint: MP.lavender.withValues(alpha: .22),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('🧪 نسخه نمایشی', style: TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            const Text(
                              'داده‌ها نمونه‌اند و با رفرش صفحه به حالت اول برمی‌گردند. برای دیدن هر بخش یکی از دو ورود سریع زیر را بزنید. '
                              'ورود با شماره دلخواه: هر شماره ۰۹... و کد ۱۱۱۱.',
                              style: TextStyle(fontSize: 12.5, height: 1.7),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _loading ? null : () => _quick('09121111111', 'demo1234'),
                                    icon: const Icon(Icons.local_hospital_rounded),
                                    label: const Text('پنل کلینیک'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _loading ? null : () => _quick('melopet', 'melopet-admin-1234'),
                                    icon: const Icon(Icons.admin_panel_settings_rounded),
                                    label: const Text('پنل مدیر'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
