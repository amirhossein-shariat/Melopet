import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../services/api.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/form_bits.dart';
import '../../widgets/glass.dart';

/// Create / edit a discount or special offer (optionally notify all clinics).
class PromotionEditScreen extends StatefulWidget {
  final RecordModel? promo;
  const PromotionEditScreen({super.key, this.promo});
  @override
  State<PromotionEditScreen> createState() => _PromotionEditScreenState();
}

class _PromotionEditScreenState extends State<PromotionEditScreen> {
  RecordModel? get p => widget.promo;
  late final title = TextEditingController(text: p?.getStringValue('title'));
  late final body = TextEditingController(text: p?.getStringValue('body'));
  late final code = TextEditingController(text: p?.getStringValue('code'));
  late final discount = TextEditingController(
    text: (p?.getDoubleValue('discount_percent') ?? 0) > 0 ? '${p!.getDoubleValue('discount_percent').toInt()}' : '',
  );
  late DateTime? until = parseDate(p?.getStringValue('valid_until'));
  late bool active = p?.getBoolValue('active') ?? true;
  bool notify = true;
  late String color = p?.getStringValue('color').isNotEmpty == true ? p!.getStringValue('color') : '#F4A6C0';
  PickedBytes? image;
  final _form = GlobalKey<FormState>();
  bool _saving = false;

  static const _colors = ['#F4A6C0', '#C7B5F2', '#8FD8C8', '#FFCBA8', '#A9D4F5', '#F7D774'];

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'title': title.text.trim(),
        'body': body.text.trim(),
        'code': code.text.trim(),
        'discount_percent': double.tryParse(enNum(discount.text.trim())) ?? 0,
        'valid_until': until?.toUtc().toIso8601String() ?? '',
        'active': active,
        'notify': p == null && notify,
        'color': color,
      };
      final files = [if (image != null) image!.toMultipart('image')];
      if (p == null) {
        await Api.pb.collection('promotions').create(body: data, files: files);
      } else {
        await Api.pb.collection('promotions').update(p!.id, body: data, files: files);
        if (notify) {
          await Api.pb
              .collection('notifications')
              .create(body: {'audience': 'clinics', 'type': 'promo', 'title': title.text.trim(), 'body': body.text.trim(), 'ref': p!.id});
        }
      }
      if (mounted) {
        toast(context, notify ? 'منتشر شد و برای همه همکاران اعلان رفت' : 'ذخیره شد');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'حذف پیشنهاد', 'این پیشنهاد حذف شود؟', ok: 'حذف')) return;
    await Api.pb.collection('promotions').delete(p!.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return MPScaffold(
      title: p == null ? 'پیشنهاد / تخفیف جدید' : 'ویرایش پیشنهاد',
      actions: [if (p != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded))],
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Field(title, 'عنوان', required: true, hint: 'مثلا: ۲۰٪ تخفیف پنل بیوشیمی'),
            Field(body, 'توضیحات', maxLines: 4),
            Row(
              children: [
                Expanded(child: Field(discount, 'درصد تخفیف', keyboard: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: Field(code, 'کد تخفیف', ltr: true)),
              ],
            ),
            Glass(
              margin: const EdgeInsets.only(bottom: 12),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: until ?? DateTime.now().add(const Duration(days: 7)),
                );
                if (d != null) setState(() => until = DateTime(d.year, d.month, d.day, 23, 59));
              },
              child: Row(
                children: [
                  const Icon(Icons.event_rounded),
                  const SizedBox(width: 10),
                  Expanded(child: Text(until == null ? 'تاریخ پایان (اختیاری)' : 'معتبر تا ${jDateLong(until)}')),
                  if (until != null) IconButton(onPressed: () => setState(() => until = null), icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            const Text('رنگ کارت', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                for (final c in _colors)
                  GestureDetector(
                    onTap: () => setState(() => color = c),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Color(0xFF000000 | int.parse(c.substring(1), radix: 16)),
                        shape: BoxShape.circle,
                        border: Border.all(color: color == c ? MP.plum : Colors.white, width: 3),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            ImagePickTile(
              title: 'تصویر بنر (اختیاری)',
              subtitle: 'نسبت ۲ به ۱ پیشنهاد می‌شود',
              file: image,
              currentUrl: p != null && p!.getStringValue('image').isNotEmpty ? Api.fileUrl(p!, 'image', thumb: '600x300').toString() : null,
              onPick: () async {
                final f = await pickOne(imagesOnly: true);
                if (f != null) setState(() => image = f);
              },
            ),
            SwitchListTile(value: active, onChanged: (v) => setState(() => active = v), title: const Text('نمایش برای همکاران')),
            SwitchListTile(
              value: notify,
              onChanged: (v) => setState(() => notify = v),
              title: const Text('ارسال نوتیفیکیشن برای همه همکاران'),
              secondary: const Icon(Icons.notifications_active_rounded, color: MP.pinkDeep),
            ),
            const SizedBox(height: 10),
            GradientButton(label: 'انتشار', icon: Icons.campaign_rounded, loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
