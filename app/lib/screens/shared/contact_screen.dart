import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/glass.dart';
import '../../widgets/logo.dart';
import '../chat/chat_screen.dart';

/// "ارتباط با ما"
class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().settings;
    String v(String f) => s?.getStringValue(f) ?? '';

    Future<void> open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    String digits(String x) => enNum(x).replaceAll(RegExp(r'[^0-9+]'), '');

    final items = <(IconData, Color, String, String, VoidCallback?)>[
      if (v('phone').isNotEmpty)
        (Icons.call_rounded, MP.mintDeep, 'تلفن آزمایشگاه', faNum(v('phone')), () => open('tel:${digits(v('phone'))}')),
      if (v('mobile').isNotEmpty)
        (Icons.phone_iphone_rounded, MP.pinkDeep, 'موبایل', faNum(v('mobile')), () => open('tel:${digits(v('mobile'))}')),
      if (v('whatsapp').isNotEmpty)
        (
          Icons.chat_rounded,
          const Color(0xFF25D366),
          'واتساپ',
          faNum(v('whatsapp')),
          () => open('https://wa.me/${digits(v('whatsapp')).replaceFirst(RegExp(r'^0'), '98')}'),
        ),
      if (v('telegram').isNotEmpty)
        (
          Icons.send_rounded,
          const Color(0xFF2AABEE),
          'تلگرام',
          v('telegram'),
          () => open('https://t.me/${v('telegram').replaceAll('@', '')}'),
        ),
      if (v('instagram').isNotEmpty)
        (
          Icons.camera_alt_rounded,
          const Color(0xFFD62976),
          'اینستاگرام',
          v('instagram'),
          () => open('https://instagram.com/${v('instagram').replaceAll('@', '')}'),
        ),
      if (v('email').isNotEmpty) (Icons.alternate_email_rounded, MP.lavenderDeep, 'ایمیل', v('email'), () => open('mailto:${v('email')}')),
      if (v('website').isNotEmpty)
        (
          Icons.language_rounded,
          MP.peachDeep,
          'وب‌سایت',
          v('website'),
          () => open(v('website').startsWith('http') ? v('website') : 'https://${v('website')}'),
        ),
      if (v('address').isNotEmpty)
        (Icons.location_on_rounded, MP.danger, 'آدرس', v('address'), () => open('geo:0,0?q=${Uri.encodeComponent(v('address'))}')),
      if (v('working_hours').isNotEmpty) (Icons.schedule_rounded, MP.warning, 'ساعات کاری', faNum(v('working_hours')), null),
    ];

    return MPScaffold(
      title: 'تماس با ما',
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Center(child: MelopetLogo(size: 84, withText: true)),
          if (v('slogan').isNotEmpty) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(v('slogan'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
          const SizedBox(height: 18),
          GradientButton(
            label: 'گفتگوی آنلاین با آزمایشگاه',
            icon: Icons.forum_rounded,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen())),
          ),
          const SizedBox(height: 14),
          for (final i in items)
            Glass(
              margin: const EdgeInsets.only(bottom: 10),
              onTap: i.$5,
              child: Row(
                children: [
                  GlassIcon(i.$1, color: i.$2, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.$3, style: const TextStyle(fontSize: 12)),
                        Text(i.$4, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  if (i.$5 != null) const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                ],
              ),
            ),
          if (v('about').isNotEmpty)
            Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('درباره ملوپت', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(v('about'), style: const TextStyle(height: 1.8)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
