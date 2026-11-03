import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/glass.dart';
import '../../widgets/logo.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobile = TextEditingController();
  final _pass = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscure = true;

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await Api.pb.collection('users').authWithPassword(enNum(_mobile.text.trim()), _pass.text);
      if (!mounted) return;
      await context.read<AppState>().onLoggedIn();
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _serverDialog() async {
    final c = TextEditingController(text: Api.serverUrl(Api.prefs));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('آدرس سرور'),
        content: TextField(
          controller: c,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: 'https://api.example.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (ok == true) {
      await Api.setServer(c.text);
      if (mounted) {
        await context.read<AppState>().loadSettings();
        if (mounted) toast(context, 'سرور تنظیم شد');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    Text(
                      'پنل همکاران آزمایشگاه دامپزشکی',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .6)),
                    ),
                    const SizedBox(height: 28),
                    Glass(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('ورود به حساب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _mobile,
                            keyboardType: TextInputType.visiblePassword,
                            autocorrect: false,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'شماره موبایل',
                              hintText: '09xxxxxxxxx',
                              prefixIcon: Icon(Icons.phone_iphone_rounded),
                            ),
                            validator: (v) {
                              final s = enNum(v?.trim() ?? '');
                              // clinics: mobile number — lab admin: dedicated admin ID
                              if (RegExp(r'^09\d{9}$').hasMatch(s) || RegExp(r'^[a-zA-Z][a-zA-Z0-9_.\-]{2,}$').hasMatch(s)) return null;
                              return 'شماره موبایل معتبر نیست';
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
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
                            onFieldSubmitted: (_) => _login(),
                          ),
                          const SizedBox(height: 20),
                          GradientButton(label: 'ورود', icon: Icons.login_rounded, loading: _loading, onPressed: _login),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: () => showDialog(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('فراموشی رمز عبور'),
                                content: Text(
                                  'برای بازیابی رمز با آزمایشگاه تماس بگیرید:\n${context.read<AppState>().settings?.getStringValue('phone') ?? ''}',
                                ),
                                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('باشه'))],
                              ),
                            ),
                            child: const Text('رمز عبور را فراموش کرده‌ام'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Glass(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                      child: Row(
                        children: [
                          const GlassIcon(Icons.local_hospital_rounded, size: 46),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ثبت‌نام کلینیک / بیمارستان', style: TextStyle(fontWeight: FontWeight.w800)),
                                SizedBox(height: 2),
                                Text('فقط یک بار مشخصات مرکز را ثبت کنید', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    ),
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
