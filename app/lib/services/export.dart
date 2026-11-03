import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pocketbase/pocketbase.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/format.dart';
import '../utils/results.dart';
import 'api.dart';

/// PDF + Excel export of lab results.
class Export {
  static pw.Font? _reg, _bold;

  static Future<void> _fonts() async {
    _reg ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf'));
  }

  static const _pink = PdfColor.fromInt(0xFFD9668F);
  static const _pinkSoft = PdfColor.fromInt(0xFFFCE4EC);
  static const _grey = PdfColor.fromInt(0xFF6B5B66);

  /// Builds the result report.
  /// [letterhead] — when set, the image fills the whole A4 page as background
  /// and content is placed between [topMm] and [bottomMm] margins.
  static Future<Uint8List> resultPdf({
    required RecordModel order,
    RecordModel? clinic,
    Uint8List? letterhead,
    double topMm = 45,
    double bottomMm = 25,
    String labName = 'آزمایشگاه دامپزشکی ملوپت',
    String technicalManager = '',
  }) async {
    await _fonts();
    final theme = pw.ThemeData.withFont(base: _reg!, bold: _bold!);
    final results = parseResults(order.data['results']);
    pw.MemoryImage? img;
    if (letterhead != null) {
      try {
        img = pw.MemoryImage(letterhead);
      } catch (_) {
        img = null; // unreadable image → fall back to the Melopet header
      }
    }
    final created = parseDate(order.getStringValue('created'));
    final ready = parseDate(order.getStringValue('ready_at'));

    final doc = pw.Document(title: 'Melopet ${order.getStringValue('code')}', author: labName);
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          theme: theme,
          textDirection: pw.TextDirection.rtl,
          margin: pw.EdgeInsets.fromLTRB(
            14 * PdfPageFormat.mm,
            (img != null ? topMm : 14) * PdfPageFormat.mm,
            14 * PdfPageFormat.mm,
            (img != null ? bottomMm : 14) * PdfPageFormat.mm,
          ),
          buildBackground: img == null ? null : (ctx) => pw.FullPage(ignoreMargins: true, child: pw.Image(img!, fit: pw.BoxFit.fill)),
        ),
        header: img != null ? null : (ctx) => _defaultHeader(labName, ctx),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'صفحه ${faNum(ctx.pageNumber)} از ${faNum(ctx.pagesCount)}  •  تهیه شده توسط $labName',
            style: const pw.TextStyle(fontSize: 8, color: _grey),
          ),
        ),
        build: (ctx) => [
          pw.Center(
            child: pw.Text(
              'گزارش نتایج آزمایش',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _pink),
            ),
          ),
          pw.SizedBox(height: 8),
          _infoBox([
            ['کد پذیرش', order.getStringValue('code')],
            ['تاریخ پذیرش', jDate(created)],
            ['تاریخ جواب', jDate(ready ?? DateTime.now())],
            ['نام حیوان', order.getStringValue('pet_name')],
            ['گونه', speciesLabels[order.getStringValue('species')] ?? '-'],
            ['نژاد', order.getStringValue('breed')],
            ['سن', order.getStringValue('age')],
            ['جنس', sexLabels[order.getStringValue('sex')] ?? '-'],
            ['صاحب حیوان', order.getStringValue('owner_name')],
            ['شماره پرونده', order.getStringValue('file_no')],
            ['مرکز ارجاع‌دهنده', clinic?.getStringValue('clinic_name') ?? ''],
            ['دامپزشک', clinic?.getStringValue('doctor_name') ?? ''],
          ]),
          pw.SizedBox(height: 10),
          if (order.getStringValue('clinical_notes').isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: 'تاریخچه: ',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _grey),
                    ),
                    pw.TextSpan(
                      text: order.getStringValue('clinical_notes'),
                      style: const pw.TextStyle(fontSize: 9, color: _grey),
                    ),
                  ],
                ),
              ),
            ),
          for (final t in results) ..._testBlock(t),
          if (order.getStringValue('lab_comment').isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(color: _pinkSoft, borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('تفسیر / توضیحات آزمایشگاه', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 3),
                  pw.Text(order.getStringValue('lab_comment'), style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ],
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('H = بالاتر از محدوده مرجع   L = پایین‌تر از محدوده مرجع', style: const pw.TextStyle(fontSize: 8, color: _grey)),
              if (technicalManager.isNotEmpty)
                pw.Column(
                  children: [
                    pw.Text('مسئول فنی آزمایشگاه', style: const pw.TextStyle(fontSize: 9, color: _grey)),
                    pw.Text(technicalManager, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _defaultHeader(String labName, pw.Context ctx) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        gradient: const pw.LinearGradient(colors: [PdfColor.fromInt(0xFFF9B8CF), PdfColor.fromInt(0xFFC7B5F2)]),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                labName,
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF3D1630)),
              ),
              pw.Text(
                'Melopet Veterinary Diagnostic Laboratory',
                textDirection: pw.TextDirection.ltr,
                style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF3D1630)),
              ),
            ],
          ),
          pw.Text(
            'MELOPET',
            textDirection: pw.TextDirection.ltr,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoBox(List<List<String>> pairs) {
    final cells = pairs.where((p) => p[1].trim().isNotEmpty && p[1] != '-').toList();
    final rows = <pw.TableRow>[];
    for (var i = 0; i < cells.length; i += 3) {
      rows.add(
        pw.TableRow(
          children: [
            for (var j = i; j < i + 3; j++)
              j < cells.length
                  ? pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            pw.TextSpan(
                              text: '${cells[j][0]}: ',
                              style: const pw.TextStyle(fontSize: 9, color: _grey),
                            ),
                            pw.TextSpan(
                              text: cells[j][1],
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    )
                  : pw.SizedBox(),
          ],
        ),
      );
    }
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFEBC6D4)),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.all(4),
      child: pw.Table(children: rows),
    );
  }

  static List<pw.Widget> _testBlock(TestResult t) {
    final out = <pw.Widget>[
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: pw.BoxDecoration(color: _pinkSoft, borderRadius: pw.BorderRadius.circular(5)),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(t.name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            pw.Text(
              categoryInfo(t.category).en,
              textDirection: pw.TextDirection.ltr,
              style: const pw.TextStyle(fontSize: 9, color: _grey),
            ),
          ],
        ),
      ),
    ];
    if (t.params.isNotEmpty) {
      final header = ['Parameter', 'Result', 'Flag', 'Unit', 'Reference Range'];
      out.add(
        pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pw.Table(
            border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColor.fromInt(0xFFF1DCE4), width: .6)),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.4),
              1: const pw.FlexColumnWidth(1.4),
              2: const pw.FlexColumnWidth(.7),
              3: const pw.FlexColumnWidth(1.3),
              4: const pw.FlexColumnWidth(1.8),
            },
            children: [
              pw.TableRow(
                children: [
                  for (final h in header)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        h,
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _pink),
                      ),
                    ),
                ],
              ),
              for (final p in t.params.where((p) => p.value.trim().isNotEmpty))
                pw.TableRow(
                  children: [
                    _cell(p.name),
                    _cell(p.value, bold: p.flag == Flag.high || p.flag == Flag.low),
                    _cell(
                      p.flag == Flag.high
                          ? 'H'
                          : p.flag == Flag.low
                          ? 'L'
                          : '',
                      color: p.flag == Flag.high
                          ? PdfColors.red700
                          : p.flag == Flag.low
                          ? PdfColors.blue700
                          : null,
                      bold: true,
                    ),
                    _cell(p.unit),
                    _cell(p.range),
                  ],
                ),
            ],
          ),
        ),
      );
    }
    if (t.text.trim().isNotEmpty) {
      out.add(
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text(t.text, style: const pw.TextStyle(fontSize: 10)),
        ),
      );
    }
    return out;
  }

  static pw.Widget _cell(String s, {bool bold = false, PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Text(
      s,
      style: pw.TextStyle(fontSize: 9.5, fontWeight: bold ? pw.FontWeight.bold : null, color: color),
    ),
  );

  /// Downloads the clinic's letterhead (if any) and builds the PDF.
  static Future<Uint8List> resultPdfFor(RecordModel order, RecordModel? clinic, {bool useLetterhead = true, RecordModel? settings}) async {
    Uint8List? lh;
    if (useLetterhead && clinic != null && clinic.getStringValue('letterhead').isNotEmpty) {
      try {
        lh = Uint8List.fromList(await Api.download(Api.fileUrl(clinic, 'letterhead')));
      } catch (_) {}
    }
    double mm(String f, double d) {
      final v = clinic?.getDoubleValue(f) ?? 0;
      return v > 0 ? v : d;
    }

    return resultPdf(
      order: order,
      clinic: clinic,
      letterhead: lh,
      topMm: mm('letterhead_top', 45),
      bottomMm: mm('letterhead_bottom', 25),
      labName: settings?.getStringValue('lab_name').isNotEmpty == true ? settings!.getStringValue('lab_name') : 'آزمایشگاه دامپزشکی ملوپت',
      technicalManager: settings?.getStringValue('technical_manager') ?? '',
    );
  }

  /// Excel workbook with patient info + all results.
  static Uint8List resultExcel(RecordModel order, RecordModel? clinic) {
    final book = xl.Excel.createExcel();
    final first = book.getDefaultSheet() ?? 'Sheet1';
    book.rename(first, 'Results');
    final s = book['Results'];
    s.isRTL = false;

    xl.CellValue t(String v) => xl.TextCellValue(v);
    final bold = xl.CellStyle(bold: true, backgroundColorHex: xl.ExcelColor.fromHexString('#FCE4EC'));

    void row(List<xl.CellValue?> cells, {bool header = false}) {
      s.appendRow(cells);
      if (header) {
        final r = s.maxRows - 1;
        for (var c = 0; c < cells.length; c++) {
          s.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).cellStyle = bold;
        }
      }
    }

    row([t('Melopet Veterinary Laboratory — آزمایشگاه دامپزشکی ملوپت')], header: true);
    row([t('Order code'), t(order.getStringValue('code'))]);
    row([t('Clinic'), t(clinic?.getStringValue('clinic_name') ?? '')]);
    row([t('Veterinarian'), t(clinic?.getStringValue('doctor_name') ?? '')]);
    row([t('Pet name'), t(order.getStringValue('pet_name'))]);
    row([t('Species'), t(speciesLabels[order.getStringValue('species')] ?? '')]);
    row([t('Breed'), t(order.getStringValue('breed'))]);
    row([t('Age'), t(order.getStringValue('age'))]);
    row([t('Sex'), t(sexLabels[order.getStringValue('sex')] ?? '')]);
    row([t('Owner'), t(order.getStringValue('owner_name'))]);
    row([t('Date'), t(jDate(parseDate(order.getStringValue('ready_at')) ?? DateTime.now(), persian: false))]);
    row([]);
    row([t('Test'), t('Parameter'), t('Result'), t('Flag'), t('Unit'), t('Reference Range')], header: true);
    for (final r in parseResults(order.data['results'])) {
      for (final p in r.params.where((p) => p.value.trim().isNotEmpty)) {
        final v = double.tryParse(p.value);
        row([
          t(r.code.isNotEmpty ? r.code : r.name),
          t(p.name),
          v != null ? xl.DoubleCellValue(v) : t(p.value),
          t(
            p.flag == Flag.high
                ? 'H'
                : p.flag == Flag.low
                ? 'L'
                : '',
          ),
          t(p.unit),
          t(p.range),
        ]);
      }
      if (r.text.trim().isNotEmpty) row([t(r.code.isNotEmpty ? r.code : r.name), t('Report'), t(r.text)]);
    }
    if (order.getStringValue('lab_comment').isNotEmpty) {
      row([]);
      row([t('Comment'), t(order.getStringValue('lab_comment'))]);
    }
    s.setColumnWidth(0, 22);
    s.setColumnWidth(1, 22);
    s.setColumnWidth(2, 14);
    s.setColumnWidth(5, 20);
    return Uint8List.fromList(book.encode() ?? []);
  }

  /// Excel list of orders (admin / clinic history).
  static Uint8List ordersExcel(List<RecordModel> orders) {
    final book = xl.Excel.createExcel();
    final first = book.getDefaultSheet() ?? 'Sheet1';
    book.rename(first, 'Orders');
    final s = book['Orders'];
    s.isRTL = true;
    xl.CellValue t(String v) => xl.TextCellValue(v);
    s.appendRow([t('کد'), t('تاریخ'), t('مرکز'), t('حیوان'), t('گونه'), t('آزمایش‌ها'), t('مبلغ'), t('وضعیت')]);
    for (final o in orders) {
      final clinic = o.get<RecordModel?>('expand.clinic');
      final items = (o.data['items'] as List? ?? []).map((e) => (e as Map)['code'] ?? e['name']).join(', ');
      s.appendRow([
        t(o.getStringValue('code')),
        t(jDate(parseDate(o.getStringValue('created')), persian: false)),
        t(clinic?.getStringValue('clinic_name') ?? ''),
        t(o.getStringValue('pet_name')),
        t(speciesLabels[o.getStringValue('species')] ?? ''),
        t(items),
        xl.DoubleCellValue(o.getDoubleValue('total')),
        t(statusInfo(o.getStringValue('status')).label),
      ]);
    }
    return Uint8List.fromList(book.encode() ?? []);
  }

  static Future<void> share(Uint8List bytes, String name, String mime, {String? text}) async {
    if (kIsWeb && mime == 'application/pdf') {
      await Printing.sharePdf(bytes: bytes, filename: name);
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: name, mimeType: mime)],
        fileNameOverrides: [name],
        text: text,
      ),
    );
  }

  static Future<void> printPdf(Uint8List bytes, String name) => Printing.layoutPdf(onLayout: (_) async => bytes, name: name);

  static const pdfMime = 'application/pdf';
  static const xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
}
