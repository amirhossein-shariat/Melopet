import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../widgets/form_bits.dart';
import '../../widgets/glass.dart';

/// Send a notification to every clinic (e.g. holidays, new tests, outages).
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});
  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final title = TextEditingController();
  final body = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _sending = false;

  Future<void> _send() async {
    if (!validateForm(context, _form)) return;
    setState(() => _sending = true);
    try {
      await Api.pb
          .collection('notifications')
          .create(body: {'audience': 'clinics', 'type': 'general', 'title': title.text.trim(), 'body': body.text.trim()});
      if (mounted) {
        toast(context, 'اعلان برای همه همکاران ارسال شد');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MPScaffold(
      title: 'اعلان همگانی',
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Glass(child: Text('این پیام به صورت نوتیفیکیشن برای همه کلینیک‌ها و بیمارستان‌های همکار ارسال می‌شود.')),
            const SizedBox(height: 14),
            Field(title, 'عنوان', required: true, hint: 'مثلا: ساعات کاری ایام تعطیلات'),
            Field(body, 'متن پیام', maxLines: 5, required: true),
            GradientButton(label: 'ارسال برای همه', icon: Icons.campaign_rounded, loading: _sending, onPressed: _send),
          ],
        ),
      ),
    );
  }
}
