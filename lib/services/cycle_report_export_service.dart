import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../utils/attendance_cycle.dart';

/// Exports the monthly attendance sheet — the same columns HR keeps by hand.
///
/// Both formats come from attendance_cycle_report() in the database rather
/// than being recomputed here, so an export cannot disagree with the screens:
/// lateness, timing exemptions and non-working days are decided in one place.
///
/// CSV is offered alongside PDF because the existing sheet is a spreadsheet.
/// A PDF cannot be pasted into next month's workbook or reconciled against
/// payroll, which is most of what this report is for.
class CycleReportExportService {
  static const _columns = <String, String>{
    'employee_name': 'EMPLOYEE NAME',
    'employee_code': 'EMPLOYEE CODE',
    'department': 'DEPARTMENT',
    'designation': 'DESIGNATIONS',
    'date_of_joining': 'DOJ',
    'total_working_days': 'TOTAL WORKING DAYS',
    'days_worked': 'NO OF DAYS WORKED',
    'leave_taken': 'NO OF LEAVE TAKEN',
    'lop_days': 'NO LOP DAYS',
    'late_count': 'NO OF LATE',
    'permission_count': 'NO OF PERMISSION',
    'pay_days': 'NO OF PAY DAYS',
    'remarks': 'REMARKS',
  };

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  static String _fileStem(DateTime cycleEnd) =>
      'Attendance_${_months[cycleEnd.month - 1]}_${cycleEnd.year}';

  /// Escapes a value for CSV. Names and remarks routinely contain commas, and
  /// an unquoted comma silently shifts every later column by one — the kind of
  /// corruption nobody notices until the totals disagree.
  static String _csvCell(Object? v) {
    final s = (v ?? '').toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String buildCsv(List<Map<String, dynamic>> rows, DateTime cycleEnd) {
    final b = StringBuffer();
    // The period is named in the file itself: a sheet headed only "August" is
    // ambiguous when it actually covers 26 Jul to 25 Aug.
    b.writeln('FOMRA HOUSING - ATTENDANCE');
    b.writeln('Pay cycle,${attendanceCycleRange(cycleEnd)} ${cycleEnd.year}');
    b.writeln();
    b.writeln(_columns.values.map(_csvCell).join(','));
    for (final r in rows) {
      b.writeln(_columns.keys.map((k) => _csvCell(r[k])).join(','));
    }
    return b.toString();
  }

  /// Shares the CSV using the same mechanism as the PDF exports, so behaviour
  /// is consistent across browser and device.
  static Future<String> downloadCsv(
      List<Map<String, dynamic>> rows, DateTime cycleEnd) async {
    final filename = '${_fileStem(cycleEnd)}.csv';
    await Printing.sharePdf(
      bytes: Uint8List.fromList(utf8.encode(buildCsv(rows, cycleEnd))),
      filename: filename,
    );
    return filename;
  }

  static Future<Uint8List> buildPdf(
      List<Map<String, dynamic>> rows, DateTime cycleEnd) async {
    final doc = pw.Document();
    final headers = _columns.values.toList();

    doc.addPage(
      pw.MultiPage(
        // Landscape: thirteen columns do not fit portrait without shrinking
        // the text past readability.
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('FOMRA HOUSING & INFRASTRUCTURE PVT LTD',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(
              'Attendance — ${attendanceCycleRange(cycleEnd)} ${cycleEnd.year}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows
                .map((r) =>
                    _columns.keys.map((k) => (r[k] ?? '').toString()).toList())
                .toList(),
            headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellHeight: 16,
            cellAlignments: {
              // Text left, numbers centred — the same convention as the sheet.
              for (var i = 0; i < headers.length; i++)
                i: i < 5 ? pw.Alignment.centerLeft : pw.Alignment.center,
            },
          ),
        ],
      ),
    );
    return doc.save();
  }

  static Future<String> downloadPdf(
      List<Map<String, dynamic>> rows, DateTime cycleEnd) async {
    final filename = '${_fileStem(cycleEnd)}.pdf';
    await Printing.sharePdf(bytes: await buildPdf(rows, cycleEnd), filename: filename);
    return filename;
  }

  // ── Punctuality detail (selected employees only) ──────────────────────
  // Day-level late-arrival rows for a payroll punctuality review — every
  // instance with date, time, minutes late, and grace vs severe, rather
  // than just the per-employee count the main sheet above gives.

  static const _punctualityColumns = <String, String>{
    'employee_name': 'EMPLOYEE NAME',
    'employee_code': 'EMPLOYEE CODE',
    'date': 'DATE',
    'check_in_time': 'CHECK-IN',
    'scheduled_start': 'SCHEDULED START',
    'minutes_late': 'MINUTES LATE',
    'severity': 'SEVERITY',
  };

  static String _punctualityFileStem(DateTime cycleEnd) =>
      'Punctuality_${_months[cycleEnd.month - 1]}_${cycleEnd.year}';

  static String buildPunctualityCsv(List<Map<String, dynamic>> rows, DateTime cycleEnd) {
    final b = StringBuffer();
    b.writeln('FOMRA HOUSING - PUNCTUALITY DETAIL');
    b.writeln('Pay cycle,${attendanceCycleRange(cycleEnd)} ${cycleEnd.year}');
    b.writeln();
    b.writeln(_punctualityColumns.values.map(_csvCell).join(','));
    for (final r in rows) {
      b.writeln(_punctualityColumns.keys.map((k) => _csvCell(r[k])).join(','));
    }
    return b.toString();
  }

  static Future<String> downloadPunctualityCsv(
      List<Map<String, dynamic>> rows, DateTime cycleEnd) async {
    final filename = '${_punctualityFileStem(cycleEnd)}.csv';
    await Printing.sharePdf(
      bytes: Uint8List.fromList(utf8.encode(buildPunctualityCsv(rows, cycleEnd))),
      filename: filename,
    );
    return filename;
  }

  static Future<Uint8List> buildPunctualityPdf(
      List<Map<String, dynamic>> rows, DateTime cycleEnd) async {
    final doc = pw.Document();
    final headers = _punctualityColumns.values.toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('FOMRA HOUSING & INFRASTRUCTURE PVT LTD',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(
              'Punctuality Detail — ${attendanceCycleRange(cycleEnd)} ${cycleEnd.year}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
        build: (_) => [
          if (rows.isEmpty)
            pw.Text('No late check-ins for the selected employees this cycle.',
                style: const pw.TextStyle(fontSize: 10)),
          if (rows.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows
                  .map((r) => _punctualityColumns.keys.map((k) => (r[k] ?? '').toString()).toList())
                  .toList(),
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellHeight: 16,
              cellAlignments: {
                for (var i = 0; i < headers.length; i++)
                  i: i < 2 ? pw.Alignment.centerLeft : pw.Alignment.center,
              },
            ),
        ],
      ),
    );
    return doc.save();
  }

  static Future<String> downloadPunctualityPdf(
      List<Map<String, dynamic>> rows, DateTime cycleEnd) async {
    final filename = '${_punctualityFileStem(cycleEnd)}.pdf';
    await Printing.sharePdf(bytes: await buildPunctualityPdf(rows, cycleEnd), filename: filename);
    return filename;
  }
}
