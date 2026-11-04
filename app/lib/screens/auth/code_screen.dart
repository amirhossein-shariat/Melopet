import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/glass.dart';
import 'register_screen.dart';

/// Enter the 4-digit SMS code. Existing clinics are signed in; new numbers go on to registration.
class CodeScreen extends StatefulWidget {
  final String mobile;

  /// Server is in test mode: the code is fixed (1111) and no SMS is sent.
  final bool testMode;
  const CodeScreen({super.key, required this.mobile, required this.testMode});

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> {
  static const _length = 4;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _loading = false;
  bool _error = false;
  int _left = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _ctrl.addListener(() {
      setState(() => _error = false);
      if (_ctrl.text.length == _length) _verify();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _left = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) {
        t.cancel();
      }
      if (mounted) setState(() => _left = (_left - 1).clamp(0, 60));
    });
  }

  Future<void> _verify() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final proof = await Api.verifyCode(widget.mobile, enNum(_ctrl.text));
      if (!mounted) return;
      if (proof == null) {
        // existing clinic: signed in — go back to the root, which shows the app
        final state = context.read<AppState>();
        Navigator.of(context).popUntil((r) => r.isFirst);
        await state.onLoggedIn();
      } else {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RegisterScreen(mobile: widget.mobile, proof: proof),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = true);
        _ctrl.clear();
        toast(context, Api.error(e), error: true);
        _focus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    try {
      await Api.requestCode(widget.mobile);
      _startTimer();
      if (mounted) toast(context, 'کد جدید ارسال شد');
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MPScaffold(
      title: 'تایید شماره موبایل',
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  const GlassIcon(Icons.sms_rounded, size: 76),
                  const SizedBox(height: 16),
                  Text('کد ۴ رقمی ارسال‌شده به', style: TextStyle(color: cs.onSurface.withValues(alpha: .7))),
                  const SizedBox(height: 4),
                  Text(
                    faNum(widget.mobile),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 24),
                  if (widget.testMode)
                    Glass(
                      margin: const EdgeInsets.only(bottom: 18),
                      tint: MP.warning.withValues(alpha: .18),
                      padding: const EdgeInsets.all(12),
                      child: const Row(
                        children: [
                          Icon(Icons.science_rounded, color: MP.warning),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'حالت آزمایشی: پنل پیامک هنوز فعال نیست و پیامکی ارسال نمی‌شود.\nکد ورود را ۱۱۱۱ وارد کنید.',
                              style: TextStyle(fontSize: 12.5, height: 1.7, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // 4 boxes driven by one hidden text field
                  GestureDetector(
                    onTap: () => _focus.requestFocus(),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < _length; i++)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  margin: const EdgeInsets.symmetric(horizontal: 6),
                                  width: 58,
                                  height: 66,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isDark(context) ? Colors.white.withValues(alpha: .07) : Colors.white.withValues(alpha: .8),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      width: i == _ctrl.text.length ? 2 : 1.2,
                                      color: _error ? MP.danger : (i == _ctrl.text.length ? cs.primary : cs.primary.withValues(alpha: .25)),
                                    ),
                                  ),
                                  child: Text(
                                    i < _ctrl.text.length ? faNum(_ctrl.text[i]) : '',
                                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // the real input, invisible but focusable
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0.01,
                            child: TextField(
                              controller: _ctrl,
                              focusNode: _focus,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              maxLength: _length,
                              enableInteractiveSelection: false,
                              showCursor: false,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹٠-٩]'))],
                              decoration: const InputDecoration(counterText: '', border: InputBorder.none, filled: false),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_loading)
                    const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))
                  else
                    GradientButton(label: 'تایید', icon: Icons.check_rounded, onPressed: _ctrl.text.length == _length ? _verify : null),
                  const SizedBox(height: 14),
                  _left > 0
                      ? Text('ارسال دوباره کد تا ${faNum(_left)} ثانیه دیگر', style: const TextStyle(fontSize: 12.5))
                      : TextButton.icon(onPressed: _resend, icon: const Icon(Icons.refresh_rounded), label: const Text('ارسال دوباره کد')),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('تغییر شماره موبایل')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
