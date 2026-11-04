import 'demo_server.dart';

/// Sample data for the demo build. Everything here is made up (names, phone
/// numbers, prices) — it only exists so reviewers can click through the app.
///
/// Demo logins (also available as one-tap buttons on the login screen):
///   clinic : 09121111111  (any 09... number works too; the SMS code is always 1111)
///   admin  : melopet / melopet-admin-1234
void seedDemoData(DemoServer s) {
  final now = DateTime.now();
  DateTime ago({int d = 0, int h = 0, int m = 0}) => now.subtract(Duration(days: d, hours: h, minutes: m));

  // ----------------------------------------------------------------- settings
  s.newRecord('settings', {
    'lab_name': 'آزمایشگاه دامپزشکی ملوپت',
    'slogan': 'دقت، سرعت، اعتماد',
    'phone': '021-88001122',
    'mobile': '09120000000',
    'whatsapp': '09120000000',
    'telegram': 'melopet_lab',
    'instagram': 'melopet.lab',
    'email': 'info@melopet.example',
    'website': 'melopet.example',
    'address': 'تهران، ونک، خیابان ملاصدرا، پلاک ۲۰ (آدرس نمونه)',
    'location': {'lat': 35.7575, 'lon': 51.4105},
    'working_hours': 'شنبه تا پنجشنبه ۸ تا ۲۰',
    'about': 'ملوپت، آزمایشگاه تخصصی دامپزشکی با خدمات نمونه‌گیری در محل از طریق پیک.',
    'technical_manager': 'دکتر نمونه',
  });

  // -------------------------------------------------------------------- users
  s.newRecord('users', {
    'mobile': '09000000000',
    'username': 'melopet',
    'password': 'melopet-admin-1234',
    'role': 'admin',
    'name': 'مدیر آزمایشگاه',
    'clinic_name': 'آزمایشگاه ملوپت',
    'approved': true,
    'profile_completed': true,
  }, id: 'demoadmin00001');

  Map<String, dynamic> clinic(
    String id,
    String mobile,
    String name,
    String doctor,
    String type,
    String city,
    String address,
    double lat,
    double lon, {
    bool approved = true,
    String tier = 'bronze',
    int daysAgo = 30,
  }) {
    final c = s.newRecord(
      'users',
      {
        'mobile': mobile,
        'password': 'demo1234',
        'role': 'clinic',
        'name': doctor,
        'clinic_type': type,
        'clinic_name': name,
        'doctor_name': doctor,
        'council_no': '12${mobile.substring(7)}',
        'phone': '02188${mobile.substring(6)}',
        'contact_person': 'پذیرش',
        'contact_mobile': mobile,
        'city': city,
        'address': address,
        'location': {'lat': lat, 'lon': lon},
        'working_hours': 'هر روز ۹ تا ۲۱',
        'instagram': '',
        'letterhead_top': 45,
        'letterhead_bottom': 25,
        'approved': approved,
        'profile_completed': true,
      },
      id: id,
      created: ago(d: daysAgo),
    );
    s.newRecord('clinic_tiers', {'clinic': id, 'tier': tier, 'note': ''});
    return c;
  }

  clinic(
    'democlinic0001',
    '09121111111',
    'کلینیک دامپزشکی مهر',
    'سارا احمدی',
    'clinic',
    'تهران',
    'تهران، خیابان ولیعصر، کوچه گلها، پلاک ۱۲',
    35.7219,
    51.3347,
    tier: 'gold',
  );
  clinic(
    'democlinic0002',
    '09122222222',
    'بیمارستان دامپزشکی سپید',
    'رضا نوری',
    'hospital',
    'کرج',
    'کرج، گوهردشت، بلوار ارم',
    35.8200,
    50.9300,
    tier: 'silver',
    daysAgo: 12,
  );
  clinic(
    'democlinic0003',
    '09123333333',
    'کلینیک آریا',
    'نیلوفر کریمی',
    'clinic',
    'تهران',
    'تهران، سعادت‌آباد، خیابان سرو',
    35.7800,
    51.3700,
    approved: false,
    daysAgo: 1,
  );

  // -------------------------------------------------------------------- tests
  Map<String, dynamic> p(String key, String name, String unit, {List<num>? dog, List<num>? cat}) => {
    'key': key,
    'name': name,
    'unit': unit,
    'ref': {'dog': ?dog, 'cat': ?cat},
  };

  var sort = 0;
  final tests = <String, Map<String, dynamic>>{};
  void test(String name, String code, String category, String sample, int hours, int bronze, List<Map<String, dynamic>> params) {
    tests[code] = s.newRecord('tests', {
      'name': name,
      'code': code,
      'category': category,
      'sample_type': sample,
      'turnaround_hours': hours,
      'price_bronze': bronze,
      'price_silver': (bronze * 0.93 / 1000).round() * 1000,
      'price_gold': (bronze * 0.86 / 1000).round() * 1000,
      'visible_tiers': ['gold', 'silver', 'bronze'],
      'active': true,
      'sort': ++sort,
      'description': '',
      'parameters': params,
    });
  }

  test('CBC (شمارش کامل سلول‌های خون)', 'CBC', 'hematology', 'خون کامل (EDTA)', 6, 400000, [
    p('wbc', 'WBC', '×10³/µL', dog: [5.5, 16.9], cat: [5.5, 19.5]),
    p('rbc', 'RBC', '×10⁶/µL', dog: [5.5, 8.5], cat: [5, 10]),
    p('hgb', 'HGB', 'g/dL', dog: [12, 18], cat: [8, 15]),
    p('hct', 'HCT', '%', dog: [37, 55], cat: [24, 45]),
    p('mcv', 'MCV', 'fL', dog: [60, 77], cat: [39, 55]),
    p('mch', 'MCH', 'pg', dog: [19.5, 24.5], cat: [12.5, 17.5]),
    p('mchc', 'MCHC', 'g/dL', dog: [32, 36], cat: [30, 36]),
    p('plt', 'PLT', '×10³/µL', dog: [175, 500], cat: [300, 800]),
    p('neut', 'Neutrophils', '%', dog: [60, 77], cat: [35, 75]),
    p('lymph', 'Lymphocytes', '%', dog: [12, 30], cat: [20, 55]),
    p('mono', 'Monocytes', '%', dog: [3, 10], cat: [1, 4]),
    p('eos', 'Eosinophils', '%', dog: [2, 10], cat: [2, 12]),
    p('baso', 'Basophils', '%', dog: [0, 1], cat: [0, 1]),
  ]);
  test('AST (SGOT)', 'AST', 'biochemistry', 'سرم', 4, 95000, [
    p('ast', 'AST', 'U/L', dog: [0, 50], cat: [0, 48]),
  ]);
  test('ALT (SGPT)', 'ALT', 'biochemistry', 'سرم', 4, 95000, [
    p('alt', 'ALT', 'U/L', dog: [10, 125], cat: [12, 130]),
  ]);
  test('ALP (آلکالین فسفاتاز)', 'ALP', 'biochemistry', 'سرم', 4, 95000, [
    p('alp', 'ALP', 'U/L', dog: [23, 212], cat: [14, 111]),
  ]);
  test('Cholesterol (کلسترول)', 'Chol', 'biochemistry', 'سرم', 4, 95000, [
    p('chol', 'Cholesterol', 'mg/dL', dog: [110, 320], cat: [65, 225]),
  ]);
  test('Triglyceride (تری‌گلیسرید)', 'TG', 'biochemistry', 'سرم', 4, 95000, [
    p('tg', 'Triglyceride', 'mg/dL', dog: [20, 150], cat: [10, 100]),
  ]);
  test('Glucose (قند خون)', 'Glu', 'biochemistry', 'سرم / پلاسما (فلوراید)', 4, 95000, [
    p('glu', 'Glucose', 'mg/dL', dog: [74, 143], cat: [71, 159]),
  ]);
  test('GGT (گاما گلوتامیل ترانسفراز)', 'GGT', 'biochemistry', 'سرم', 4, 95000, [
    p('ggt', 'GGT', 'U/L', dog: [0, 11], cat: [0, 4]),
  ]);
  // extra sample tests (not in the lab's price list yet)
  test('BUN (اوره خون)', 'BUN', 'biochemistry', 'سرم', 4, 95000, [
    p('bun', 'BUN', 'mg/dL', dog: [7, 27], cat: [16, 36]),
  ]);
  test('Creatinine (کراتینین)', 'Cr', 'biochemistry', 'سرم', 4, 95000, [
    p('cr', 'Creatinine', 'mg/dL', dog: [0.5, 1.8], cat: [0.8, 2.4]),
  ]);
  test('Albumin (آلبومین)', 'ALB', 'biochemistry', 'سرم', 4, 95000, [
    p('alb', 'Albumin', 'g/dL', dog: [2.3, 4], cat: [2.2, 4.4]),
  ]);
  test('Amylase (آمیلاز)', 'AMY', 'biochemistry', 'سرم', 4, 120000, [
    p('amy', 'Amylase', 'U/L', dog: [200, 1200], cat: [500, 1500]),
  ]);
  test('T4 (تیروکسین)', 'T4', 'hormone', 'سرم', 24, 350000, [
    p('t4', 'Total T4', 'µg/dL', dog: [1, 4], cat: [1, 4]),
  ]);
  test('Cortisol (کورتیزول)', 'Cort', 'hormone', 'سرم', 24, 380000, [
    p('cort', 'Cortisol', 'µg/dL', dog: [1, 6]),
  ]);
  test('Urinalysis (آنالیز ادرار)', 'UA', 'urinalysis', 'ادرار (استریل)', 6, 150000, [
    p('sg', 'Specific gravity', '', dog: [1.015, 1.045], cat: [1.035, 1.06]),
  ]);
  test('FeLV / FIV Ag', 'FeLV', 'serology', 'سرم / خون کامل', 4, 450000, []);
  test('Parvo (CPV) Ag', 'CPV', 'serology', 'مدفوع', 4, 300000, []);
  test('Culture & Antibiogram', 'Cult', 'culture', 'سواب / ادرار / خون', 72, 600000, []);
  test('Cytology (سیتولوژی)', 'Cyto', 'pathology', 'اسمیر / FNA', 48, 500000, []);
  test('Biopsy (بیوپسی)', 'Bx', 'pathology', 'بافت (فرمالین ۱۰٪)', 120, 900000, []);
  test('PCR پنل بیماری‌های تنفسی', 'PCR', 'pcr', 'سواب', 48, 1200000, []);

  // ------------------------------------------------------------------- orders
  const tierOf = {'democlinic0001': 'gold', 'democlinic0002': 'silver', 'democlinic0003': 'bronze'};

  Map<String, dynamic> order(
    String clinicId,
    String status, {
    required String pet,
    required String species,
    String breed = '',
    String age = '',
    String sex = 'unknown',
    String owner = '',
    required List<String> codes,
    String history = '',
    bool urgent = false,
    DateTime? created,
    Object? results,
    String comment = '',
    bool courier = false,
  }) {
    final tier = tierOf[clinicId]!;
    final items = [
      for (final c in codes)
        {
          'test': tests[c]!['id'],
          'name': tests[c]!['name'],
          'code': c,
          'category': tests[c]!['category'],
          'price': tests[c]!['price_$tier'],
        },
    ];
    final c = clinicId == 'democlinic0001' ? {'lat': 35.7219, 'lon': 51.3347} : {'lat': 35.8200, 'lon': 50.9300};
    final created0 = created ?? ago(h: 2);
    final flow = ['requested', 'courier_assigned', 'picked_up', 'received', 'in_progress', 'ready'];
    final upTo = flow.indexOf(status);
    final count = s.col('orders').length;
    return s.newRecord('orders', {
      'code': 'MP-${10001 + count}',
      'clinic': clinicId,
      'status': status,
      'pet_name': pet,
      'species': species,
      'breed': breed,
      'age': age,
      'sex': sex,
      'weight': 0,
      'owner_name': owner,
      'file_no': '',
      'sample_type': '',
      'sample_count': 1,
      'urgent': urgent,
      'fasting': false,
      'pickup_address': '',
      'pickup_time': 'همین حالا',
      'clinical_notes': history,
      'history_voice_seconds': 0,
      'location': c,
      'items': items,
      'total': items.fold<int>(0, (a, i) => a + (i['price'] as int)),
      'discount': 0,
      'courier_name': courier ? 'علی محمدی' : '',
      'courier_phone': courier ? '09351234567' : '',
      'results': results,
      'lab_comment': comment,
      'result_files': <String>[],
      'history': [
        for (var i = 0; i <= (upTo < 0 ? 0 : upTo); i++)
          {'status': flow[i], 'at': created0.add(Duration(minutes: i * 35)).toUtc().toIso8601String(), 'note': ''},
      ],
      'ready_at': status == 'ready' ? s.ts(created0.add(const Duration(hours: 4))) : '',
      'paid': status == 'ready',
    }, created: created0);
  }

  Map<String, dynamic> snap(String code, Map<String, String> values, String species) {
    final t = tests[code]!;
    return {
      'test': t['id'],
      'name': t['name'],
      'code': code,
      'category': t['category'],
      'text': '',
      'params': [
        for (final prm in t['parameters'] as List)
          () {
            final ref = (prm['ref'] as Map)[species] ?? (prm['ref'] as Map)['dog'];
            return {
              'key': prm['key'],
              'name': prm['name'],
              'unit': prm['unit'],
              'low': ref == null ? null : ref[0],
              'high': ref == null ? null : ref[1],
              'value': values[prm['key']] ?? '',
            };
          }(),
      ],
    };
  }

  order(
    'democlinic0001',
    'ready',
    pet: 'ملو',
    species: 'cat',
    breed: 'پرشین',
    age: '۳ سال',
    sex: 'female_spayed',
    owner: 'آقای کریمی',
    codes: ['CBC', 'ALT', 'Glu'],
    history: 'استفراغ و بی‌اشتهایی از ۳ روز قبل، تب ۳۹.۸. سابقه واکسیناسیون کامل. مشکوک به عفونت یا درگیری کبدی.',
    created: ago(d: 2, h: 3),
    courier: true,
    results: {
      'tests': [
        snap('CBC', {
          'wbc': '21.4',
          'rbc': '7.9',
          'hgb': '12.1',
          'hct': '36',
          'mcv': '45',
          'mch': '15.3',
          'mchc': '33.6',
          'plt': '250',
          'neut': '82',
          'lymph': '12',
          'mono': '3',
          'eos': '3',
          'baso': '0',
        }, 'cat'),
        snap('ALT', {'alt': '168'}, 'cat'),
        snap('Glu', {'glu': '112'}, 'cat'),
      ],
    },
    comment: 'لکوسیتوز نوتروفیلیک همراه با افزایش خفیف ALT؛ پیشنهاد: بررسی عفونت و تکرار آنزیم‌های کبدی پس از ۲ هفته.',
  );
  order(
    'democlinic0001',
    'courier_assigned',
    pet: 'راکی',
    species: 'dog',
    breed: 'ژرمن شپرد',
    age: '۷ سال',
    sex: 'male',
    owner: 'خانم رحیمی',
    codes: ['AST', 'ALP', 'GGT'],
    history: 'کاهش وزن و پرنوشی در یک ماه اخیر.',
    urgent: true,
    created: ago(h: 1, m: 10),
    courier: true,
  );
  order(
    'democlinic0001',
    'requested',
    pet: 'لونا',
    species: 'cat',
    breed: 'مخلوط',
    age: '۱ سال',
    sex: 'female',
    owner: 'آقای صادقی',
    codes: ['CBC', 'FeLV'],
    history: 'چکاپ قبل از عقیم‌سازی.',
    created: ago(m: 25),
  );
  order(
    'democlinic0002',
    'in_progress',
    pet: 'پیشی',
    species: 'cat',
    age: '۲ سال',
    sex: 'male',
    owner: 'آقای موسوی',
    codes: ['Chol', 'TG', 'BUN', 'Cr'],
    history: 'چاقی و بی‌حالی، ارزیابی چربی و کلیه.',
    created: ago(h: 5),
  );
  order(
    'democlinic0002',
    'requested',
    pet: 'بتی',
    species: 'dog',
    breed: 'گلدن',
    age: '۴ ماهه',
    sex: 'female',
    owner: 'خانم نیک‌نام',
    codes: ['CPV', 'CBC'],
    history: 'اسهال خونی از دیروز.',
    urgent: true,
    created: ago(m: 8),
  );

  // -------------------------------------------------------------------- chat
  final convMehr = s.newRecord('conversations', {
    'clinic': 'democlinic0001',
    'last_text': '',
    'last_at': '',
    'last_sender': '',
    'unread_clinic': 0,
    'unread_admin': 0,
    'clinic_read_at': s.ts(ago(h: 20)),
    'admin_read_at': s.ts(ago(h: 20)),
  });
  Map<String, dynamic> msg(Map<String, dynamic> conv, String sender, String text, DateTime at, {Map<String, dynamic>? replyTo}) {
    final m = s.newRecord('messages', {
      'conversation': conv['id'],
      'sender': sender,
      'kind': 'text',
      'text': text,
      'file_name': '',
      'file_size': 0,
      if (replyTo != null) 'reply_to': replyTo['id'],
      'order_ref': '',
    }, created: at);
    conv['last_text'] = text;
    conv['last_at'] = s.ts(at);
    conv['last_sender'] = sender;
    return m;
  }

  final m1 = msg(convMehr, 'democlinic0001', 'سلام وقت بخیر 🌸 نمونه ملو رو فرستادیم، جوابش کی آماده میشه؟', ago(d: 2, h: 3));
  msg(
    convMehr,
    'demoadmin00001',
    'سلام دکتر احمدی، وقتتون بخیر. نمونه دریافت شد، تا ۲ ساعت دیگه جواب در اپ آپلود میشه.',
    ago(d: 2, h: 2, m: 40),
    replyTo: m1,
  );
  msg(convMehr, 'democlinic0001', 'عالیه، ممنون 🙏', ago(d: 2, h: 2, m: 35));
  msg(convMehr, 'demoadmin00001', 'جواب آماده شد ✅ لطفا بخش سفارش‌ها رو ببینید. ALT کمی بالاست.', ago(d: 2, h: 1));
  convMehr['unread_clinic'] = 1;

  final convSepid = s.newRecord('conversations', {
    'clinic': 'democlinic0002',
    'last_text': '',
    'last_at': '',
    'last_sender': '',
    'unread_clinic': 0,
    'unread_admin': 0,
    'clinic_read_at': s.ts(ago(h: 6)),
    'admin_read_at': s.ts(ago(h: 6)),
  });
  msg(convSepid, 'democlinic0002', 'سلام، برای نمونه‌های فوری تا چه ساعتی پیک دارید؟', ago(m: 14));
  convSepid['unread_admin'] = 1;

  // -------------------------------------------------------------- promotions
  s.newRecord('promotions', {
    'title': '۲۰٪ تخفیف پنل کبدی',
    'body': 'تا پایان آذر، پنل ALT + AST + ALP + GGT با ۲۰٪ تخفیف ویژه همکاران.',
    'discount_percent': 20,
    'code': 'LIVER20',
    'valid_until': s.ts(now.add(const Duration(days: 40))),
    'active': true,
    'notify': true,
    'color': '#F4A6C0',
  }, created: ago(d: 1));
  s.newRecord('promotions', {
    'title': 'پیک رایگان سفارش‌های فوری',
    'body': 'ارسال پیک برای سفارش‌های فوری این هفته رایگان است.',
    'discount_percent': 0,
    'code': '',
    'valid_until': '',
    'active': true,
    'notify': true,
    'color': '#8FD8C8',
  }, created: ago(d: 3));
  s.newRecord('promotions', {
    'title': 'پنل کامل سالانه سگ و گربه',
    'body': 'CBC + بیوشیمی کامل + آنالیز ادرار با قیمت ویژه.',
    'discount_percent': 15,
    'code': 'ANNUAL15',
    'valid_until': '',
    'active': true,
    'notify': false,
    'color': '#C7B5F2',
  }, created: ago(d: 6));

  // ----------------------------------------------------------- notifications
  s.notify(
    user: 'democlinic0001',
    type: 'result',
    title: 'جواب آزمایش آماده شد ✅',
    body: 'سفارش MP-10001 — ملو | برای مشاهده و دریافت PDF وارد شوید.',
    ref: s.col('orders').first['id'],
  );
  s.notify(
    audience: 'clinics',
    type: 'promo',
    title: '🎁 ۲۰٪ تخفیف پنل کبدی',
    body: 'تا پایان آذر، پنل ALT + AST + ALP + GGT با ۲۰٪ تخفیف ویژه همکاران.',
  );
  s.notify(
    audience: 'admins',
    type: 'order',
    title: '🛵 درخواست پیک جدید (فوری)',
    body: 'بیمارستان دامپزشکی سپید | بتی (سگ) | 2 آزمایش | MP-10005',
  );
  s.notify(audience: 'admins', title: 'همکار جدید ثبت‌نام کرد', body: 'کلینیک آریا');
}
