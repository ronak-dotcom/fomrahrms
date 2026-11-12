import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/payslip_store.dart';

/// Renders a [Payslip] into a downloadable PDF as a single compact, bordered
/// payslip block (company header, employee info grid, earnings/deductions
/// table, net pay, leave details) — dense enough to sit within about half
/// an A4 page.
class PayslipPdfService {
  static const _grey = PdfColor.fromInt(0xFF6B7280);
  static const _border = PdfColor.fromInt(0xFFD1D5DB);
  static const _headerFill = PdfColor.fromInt(0xFFF3F4F6);

  static String _fmtRs(double v) =>
      'Rs. ${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  static String _monthLabel(String monthYear) {
    const months = ['January','February','March','April','May','June',
                     'July','August','September','October','November','December'];
    final p = monthYear.split('-');
    if (p.length != 2) return monthYear;
    final m = int.tryParse(p[1]);
    if (m == null || m < 1 || m > 12) return monthYear;
    return '${months[m - 1]} ${p[0]}';
  }

  // ── Amount in words (Indian lakh/crore numbering) ───────────────────────

  static const _ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
      'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
  static const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

  static String _twoDigits(int n) {
    if (n < 20) return _ones[n];
    final rem = n % 10;
    return '${_tens[n ~/ 10]}${rem != 0 ? ' ${_ones[rem]}' : ''}';
  }

  static String _threeDigits(int n) {
    final h = n ~/ 100;
    final rest = n % 100;
    final parts = <String>[];
    if (h > 0) parts.add('${_ones[h]} Hundred');
    if (rest > 0) parts.add(_twoDigits(rest));
    return parts.join(' ');
  }

  static String _numberToWords(int n) {
    if (n == 0) return 'Zero';
    final crore = n ~/ 10000000; n %= 10000000;
    final lakh = n ~/ 100000; n %= 100000;
    final thousand = n ~/ 1000; n %= 1000;
    final hundred = n;
    final parts = <String>[];
    if (crore > 0) parts.add('${_threeDigits(crore)} Crore');
    if (lakh > 0) parts.add('${_threeDigits(lakh)} Lakh');
    if (thousand > 0) parts.add('${_threeDigits(thousand)} Thousand');
    if (hundred > 0) parts.add(_threeDigits(hundred));
    return parts.join(' ');
  }

  static String _amountInWords(double amount) => 'Rupees ${_numberToWords(amount.round())} Only';

  // ── Cell / table helpers ─────────────────────────────────────────────────

  static pw.Widget _gridCell(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: label.isEmpty
            ? pw.SizedBox()
            : pw.Row(children: [
                pw.Expanded(
                    flex: 5,
                    child: pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _grey))),
                pw.Expanded(
                    flex: 6,
                    child: pw.Text(value,
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
              ]),
      );

  static pw.Widget _th(String text, {bool alignRight = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(text,
            textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _grey)),
      );

  static pw.Widget _td(String text, {bool alignRight = false, bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: pw.Text(text,
            textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  static pw.Widget _infoGrid(Payslip p) {
    final fields = <(String, String)>[
      ('Emp Code', p.employeeId),
      ('Employee Name', p.empName),
      ('Department', p.department),
      ('Designation', p.designation),
      ('Date of Joining', p.dateOfJoining),
      ('Working Days', '${p.workingDays}'),
      ('Days Worked', Payslip.fmtDays(p.daysWorked)),
      ('LOP Days', Payslip.fmtDays(p.lopDays)),
      if (p.band.isNotEmpty) ('Band', p.band),
      ('Gross Pay', _fmtRs(p.grossPay)),
    ];
    final rows = <pw.TableRow>[];
    for (var i = 0; i < fields.length; i += 2) {
      final left = fields[i];
      final right = i + 1 < fields.length ? fields[i + 1] : ('', '');
      rows.add(pw.TableRow(children: [_gridCell(left.$1, left.$2), _gridCell(right.$1, right.$2)]));
    }
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1)},
      children: rows,
    );
  }

  static pw.Widget _earningsDeductions(Payslip p) {
    final earnings = <(String, double)>[
      ('Basic', p.basic),
      if (p.da > 0) ('Dearness Allowance', p.da),
      ('House Rent Allowance', p.hra),
      ('Educational Allowance', p.educationalAllowance),
      ('LTA', p.lta),
      ('Other Allowance', p.otherAllowance),
      ('Conveyance Allowance', p.conveyanceAllowance),
      if (p.specialAllowance > 0) ('Special Allowance', p.specialAllowance),
    ];
    final deductions = <(String, double)>[
      ('EPF', p.epf),
      if (p.esi > 0) ('ESI', p.esi),
      ('Professional Tax', p.professionalTax),
      ('TDS', p.tds),
      ('Late Deductions', p.lateDeductions),
      if (p.excessLeaveDeduction > 0) ('Excess Leave Deduction', p.excessLeaveDeduction),
      if (p.cug > 0) ('CUG', p.cug),
    ];
    final rowCount = earnings.length > deductions.length ? earnings.length : deductions.length;

    final rows = <pw.TableRow>[
      pw.TableRow(decoration: const pw.BoxDecoration(color: _headerFill), children: [
        _th('EARNINGS'), _th('AMOUNT', alignRight: true), _th('DEDUCTIONS'), _th('AMOUNT', alignRight: true),
      ]),
    ];
    for (var i = 0; i < rowCount; i++) {
      final e = i < earnings.length ? earnings[i] : null;
      final d = i < deductions.length ? deductions[i] : null;
      rows.add(pw.TableRow(children: [
        _td(e?.$1 ?? ''), _td(e != null ? _fmtRs(e.$2) : '', alignRight: true),
        _td(d?.$1 ?? ''), _td(d != null ? _fmtRs(d.$2) : '', alignRight: true),
      ]));
    }
    rows.add(pw.TableRow(decoration: const pw.BoxDecoration(color: _headerFill), children: [
      _td('Actual Gross Pay', bold: true), _td(_fmtRs(p.actualGrossPay), alignRight: true, bold: true),
      _td('Total Deductions', bold: true), _td(_fmtRs(p.totalDeductions), alignRight: true, bold: true),
    ]));

    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.6), 1: pw.FlexColumnWidth(1.6),
        2: pw.FlexColumnWidth(2.6), 3: pw.FlexColumnWidth(1.6),
      },
      children: rows,
    );
  }

  static pw.Widget _netPayBar(Payslip p) => pw.Column(children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFEEF2FF),
            border: pw.Border.all(color: _border, width: 0.5),
          ),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('NET PAY', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text(_fmtRs(p.netPay), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text('(${_amountInWords(p.netPay)})',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, fontStyle: pw.FontStyle.italic)),
        ),
      ]);

  static Future<Uint8List> build(Payslip p) async {
    final doc = pw.Document();
    final logoBytes = (await rootBundle.load('assets/images/fomra_logo.png')).buffer.asUint8List();
    final logo = pw.MemoryImage(logoBytes);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _border, width: 1)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Image(logo, height: 44),
              pw.SizedBox(height: 6),
              pw.Text('Pay Slip - ${_monthLabel(p.monthYear)}', style: const pw.TextStyle(fontSize: 9, color: _grey)),
              pw.SizedBox(height: 10),
              _infoGrid(p),
              pw.SizedBox(height: 10),
              _earningsDeductions(p),
              pw.SizedBox(height: 10),
              _netPayBar(p),
            ],
          ),
        ),
      ),
    );

    return doc.save();
  }

  /// Generates and triggers a browser/OS download of the payslip PDF.
  static Future<void> download(Payslip p) async {
    final bytes = await build(p);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Payslip-${_monthLabel(p.monthYear).replaceAll(' ', '-')}.pdf',
    );
  }
}
