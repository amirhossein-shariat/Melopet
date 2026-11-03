import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/form_bits.dart';
import '../../widgets/glass.dart';
import '../chat/chat_screen.dart';
import '../clinic/courier_request_screen.dart';
import '../clinic/profile_screen.dart';
import '../shared/orders_screen.dart';

Future<Map<String, String>> loadTiers() async {
  final r = await Api.pb.send<Map<String, dynamic>>('/api/melopet/admin/tiers');
  return r.map((k, v) => MapEntry(k, '$v'));
}

/// Admin: list of partner clinics with their (private) tier.
class ClinicsScreen extends StatefulWidget {
  final bool pickMode;
  const ClinicsScreen({super.key, this.pickMode = false});
  @override
  State<ClinicsScreen> createState() => _ClinicsScreenState();
}

class _ClinicsScreenState extends State<ClinicsScreen> {
  List<RecordModel>? _items;
  Map<String, String> _tiers = {};
  String _q = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.pb.collection('users').getFullList(filter: 'role = "clinic"', sort: 'approved,-created');
      final t = await loadTiers();
      if (mounted) {
        setState(() {
          _items = r;
          _tiers = t;
        });
      }
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = (_items ?? []).where((c) {
      if (_filter == 'pending' && c.getBoolValue('approved')) return false;
      if (['gold', 'silver', 'bronze'].contains(_filter) && (_tiers[c.id] ?? 'bronze') != _filter) return false;
      if (_q.isEmpty) return true;
      return '${c.getStringValue('clinic_name')} ${c.getStringValue('doctor_name')} ${c.getStringValue('mobile')} ${c.getStringValue('city')}'
          .contains(_q);
    }).toList();

    final body = SafeArea(
      bottom: false,
      child: Column(
        children: [
          if (!widget.pickMode)
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 12, 18, 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('همکاران', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'نام مرکز، دکتر، موبایل یا شهر'),
              onChanged: (v) => setState(() => _q = enNum(v.trim())),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in {'all': 'همه', 'pending': 'در انتظار تایید', ...tierLabels}.entries)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(label: Text(f.value), selected: _filter == f.key, onSelected: (_) => setState(() => _filter = f.key)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _items == null
                ? const Loading()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: list.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 60),
                              EmptyState(icon: Icons.local_hospital_rounded, title: 'موردی یافت نشد'),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 130),
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final c = list[i];
                              final tier = _tiers[c.id] ?? 'bronze';
                              return Glass(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                onTap: () async {
                                  if (widget.pickMode) {
                                    Navigator.pop(context, c);
                                    return;
                                  }
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ClinicAdminScreen(clinic: c, tier: tier),
                                    ),
                                  );
                                  _load();
                                },
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: tierColors[tier]!.withValues(alpha: .25),
                                      backgroundImage: c.getStringValue('logo').isNotEmpty
                                          ? NetworkImage(Api.fileUrl(c, 'logo', thumb: '200x200').toString())
                                          : null,
                                      child: c.getStringValue('logo').isEmpty
                                          ? Icon(Icons.local_hospital_rounded, color: tierColors[tier])
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c.getStringValue('clinic_name').isEmpty
                                                ? c.getStringValue('mobile')
                                                : c.getStringValue('clinic_name'),
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                          Text(
                                            'دکتر ${c.getStringValue('doctor_name')} • ${c.getStringValue('city')}',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!c.getBoolValue('approved'))
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Icon(Icons.hourglass_top_rounded, color: MP.warning, size: 20),
                                      ),
                                    TierBadge(tier),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
    if (!widget.pickMode) return Scaffold(backgroundColor: Colors.transparent, body: body);
    return MPScaffold(title: 'انتخاب همکار', body: body);
  }
}

class TierBadge extends StatelessWidget {
  final String tier;
  const TierBadge(this.tier, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [tierColors[tier]!, tierColors[tier]!.withValues(alpha: .6)]),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      tierLabels[tier] ?? tier,
      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
}

/// Admin view of a single clinic: approve, tier, contact, orders, chat.
class ClinicAdminScreen extends StatefulWidget {
  final RecordModel clinic;
  final String tier;
  const ClinicAdminScreen({super.key, required this.clinic, required this.tier});
  @override
  State<ClinicAdminScreen> createState() => _ClinicAdminScreenState();
}

class _ClinicAdminScreenState extends State<ClinicAdminScreen> {
  late RecordModel c = widget.clinic;
  late String tier = widget.tier;

  Future<void> _reload() async {
    final r = await Api.pb.collection('users').getOne(c.id);
    if (mounted) setState(() => c = r);
  }

  Future<void> _setApproved(bool v) async {
    try {
      await Api.pb.collection('users').update(c.id, body: {'approved': v});
      await _reload();
      if (mounted) toast(context, v ? 'همکار تایید شد و اعلان ارسال شد' : 'تایید لغو شد');
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    }
  }

  Future<void> _setTier(String t) async {
    try {
      await Api.pb.send('/api/melopet/admin/tiers/${c.id}', method: 'POST', body: {'tier': t});
      setState(() => tier = t);
      if (mounted) toast(context, 'سطح قیمت‌گذاری به «${tierLabels[t]}» تغییر کرد');
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    }
  }

  Future<void> _resetPassword() async {
    final p = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعیین رمز جدید'),
        content: Field(p, 'رمز جدید (حداقل ۸ کاراکتر)', ltr: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (ok != true || p.text.length < 8) return;
    try {
      await Api.pb.collection('users').update(c.id, body: {'password': p.text, 'passwordConfirm': p.text});
      if (mounted) toast(context, 'رمز تغییر کرد. آن را به همکار اطلاع دهید.');
    } catch (e) {
      if (mounted) toast(context, Api.error(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    String v(String f) => c.getStringValue(f);
    final info = <(IconData, String, String)>[
      (Icons.category_rounded, 'نوع', clinicTypeLabels[v('clinic_type')] ?? ''),
      (Icons.badge_rounded, 'دکتر مسئول', v('doctor_name')),
      (Icons.verified_user_rounded, 'نظام دامپزشکی', v('council_no')),
      (Icons.phone_iphone_rounded, 'موبایل (نام کاربری)', v('mobile')),
      (Icons.call_rounded, 'تلفن ثابت', v('phone')),
      (Icons.person_pin_rounded, 'مسئول تحویل نمونه', '${v('contact_person')} ${v('contact_mobile')}'),
      (Icons.location_on_rounded, 'آدرس', '${v('city')} - ${v('address')}'),
      (Icons.schedule_rounded, 'ساعات کاری', v('working_hours')),
      (Icons.alternate_email_rounded, 'ایمیل', v('email')),
      (Icons.camera_alt_rounded, 'اینستاگرام', v('instagram')),
      (Icons.event_rounded, 'تاریخ ثبت‌نام', jDate(parseDate(v('created')))),
    ].where((e) => e.$3.trim().isNotEmpty && e.$3.trim() != '-').toList();

    return MPScaffold(
      title: v('clinic_name'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Glass(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: c.getBoolValue('approved'),
                  onChanged: _setApproved,
                  title: const Text('حساب تایید شده', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('تا تایید نشود، امکان درخواست پیک ندارد'),
                ),
                const Divider(),
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('سطح قیمت‌گذاری (فقط برای ادمین قابل مشاهده است)', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    for (final t in ['gold', 'silver', 'bronze'])
                      ButtonSegment(
                        value: t,
                        label: Text(tierLabels[t]!),
                        icon: Icon(Icons.workspace_premium_rounded, color: tierColors[t]),
                      ),
                  ],
                  selected: {tier},
                  onSelectionChanged: (s) => _setTier(s.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GlassTile(
                  icon: Icons.chat_rounded,
                  label: 'چت',
                  color: MP.pinkDeep,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(clinicId: c.id))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassTile(
                  icon: Icons.call_rounded,
                  label: 'تماس',
                  color: MP.mintDeep,
                  onTap: () => launchUrl(Uri.parse('tel:${v('mobile')}')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassTile(
                  icon: Icons.receipt_long_rounded,
                  label: 'سفارش‌ها',
                  color: MP.lavenderDeep,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersScreen(clinicId: c.id, standalone: true))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassTile(
                  icon: Icons.add_task_rounded,
                  label: 'ثبت سفارش',
                  color: MP.peachDeep,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CourierRequestScreen(clinicId: c.id))),
                ),
              ),
            ],
          ),
          const SectionTitle('مشخصات'),
          Glass(
            child: Column(
              children: [
                for (final i in info)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(i.$1, size: 18, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        SizedBox(width: 120, child: Text(i.$2, style: const TextStyle(fontSize: 12.5))),
                        Expanded(
                          child: Text(faNum(i.$3), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (v('letterhead').isNotEmpty) ...[
            const SectionTitle('سربرگ'),
            ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(Api.fileUrl(c, 'letterhead').toString(), height: 240)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(user: c)));
                  _reload();
                },
                icon: const Icon(Icons.edit_rounded),
                label: const Text('ویرایش مشخصات'),
              ),
              OutlinedButton.icon(
                onPressed: _resetPassword,
                icon: const Icon(Icons.lock_reset_rounded),
                label: const Text('تعیین رمز جدید'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
