import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A small writer for Excel workbooks (.xlsx), enough for the reports HR
/// downloads: text and numbers, a few fixed styles, merged headings, column
/// widths, frozen header rows, SUM totals and landscape printing.
///
/// Written here rather than with a spreadsheet package because the one
/// available would have pulled older versions of the image and archive
/// libraries the app already uses.
class Xlsx {
  Xlsx._();

  // Style indexes into styles.xml (cellXfs), in the order written below.
  static const int plain = 0;
  static const int title = 1;
  static const int header = 2;
  static const int text = 3;
  static const int money = 4;
  static const int number = 5;
  static const int totalMoney = 6;
  static const int totalText = 7;
  static const int note = 8;
  static const int moneyBold = 9;
  static const int totalNumber = 10;
  static const int flagged = 11;
  static const int group = 12;
  static const int subtitle = 13;

  /// Column letters for a 0-based index: 0 → A, 25 → Z, 26 → AA.
  static String col(int index) {
    var n = index + 1;
    var s = '';
    while (n > 0) {
      s = String.fromCharCode(65 + (n - 1) % 26) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  /// A1-style reference for 0-based [row] and [column].
  static String ref(int row, int column) => '${col(column)}${row + 1}';

  /// Escapes text for XML, dropping control characters Excel rejects.
  static String escape(String s) {
    final b = StringBuffer();
    for (final c in s.runes) {
      if (c == 0x26) {
        b.write('&amp;');
      } else if (c == 0x3C) {
        b.write('&lt;');
      } else if (c == 0x3E) {
        b.write('&gt;');
      } else if (c == 0x22) {
        b.write('&quot;');
      } else if (c < 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) {
        // not allowed in XML 1.0
      } else {
        b.writeCharCode(c);
      }
    }
    return b.toString();
  }

  /// Builds the workbook. Sheet names are trimmed to Excel's 31 characters.
  static Uint8List build(List<XlsxSheet> sheets) {
    final archive = Archive();
    void add(String name, String content) => archive.addFile(ArchiveFile.string(name, content));

    add('[Content_Types].xml', _contentTypes(sheets.length));
    add('_rels/.rels', _rootRels);
    add('xl/workbook.xml', _workbook(sheets));
    add('xl/_rels/workbook.xml.rels', _workbookRels(sheets.length));
    add('xl/styles.xml', _styles);
    for (var i = 0; i < sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', sheets[i]._xml());
    }
    return ZipEncoder().encodeBytes(archive);
  }

  static String _sheetName(String n) {
    final cleaned = n.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ').trim();
    return cleaned.length > 31 ? cleaned.substring(0, 31) : cleaned;
  }

  static String _contentTypes(int n) {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
      ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
      ..write('<Default Extension="xml" ContentType="application/xml"/>')
      ..write('<Override PartName="/xl/workbook.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
      ..write('<Override PartName="/xl/styles.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
    for (var i = 1; i <= n; i++) {
      b.write('<Override PartName="/xl/worksheets/sheet$i.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    }
    b.write('</Types>');
    return b.toString();
  }

  static const _rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="xl/workbook.xml"/>'
      '</Relationships>';

  static String _workbook(List<XlsxSheet> sheets) {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
      ..write('<sheets>');
    for (var i = 0; i < sheets.length; i++) {
      b.write('<sheet name="${escape(_sheetName(sheets[i].name))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
    }
    b.write('</sheets></workbook>');
    return b.toString();
  }

  static String _workbookRels(int n) {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (var i = 1; i <= n; i++) {
      b.write('<Relationship Id="rId$i" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
          'Target="worksheets/sheet$i.xml"/>');
    }
    b.write('<Relationship Id="rId${n + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
        'Target="styles.xml"/>');
    b.write('</Relationships>');
    return b.toString();
  }

  // numFmtId 4 is Excel's built-in "#,##0.00"; 0 is General.
  static const _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="5">'
      '<font><sz val="10"/><name val="Calibri"/><family val="2"/></font>'
      '<font><b/><sz val="14"/><name val="Calibri"/><family val="2"/></font>'
      '<font><b/><sz val="10"/><name val="Calibri"/><family val="2"/></font>'
      '<font><i/><sz val="9"/><color rgb="FF5F6B7A"/><name val="Calibri"/><family val="2"/></font>'
      '<font><sz val="11"/><color rgb="FF3D4A5C"/><name val="Calibri"/><family val="2"/></font>'
      '</fonts>'
      '<fills count="5">'
      '<fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFE8EEF7"/><bgColor indexed="64"/></patternFill></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFFFF4D6"/><bgColor indexed="64"/></patternFill></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFD6E2F3"/><bgColor indexed="64"/></patternFill></fill>'
      '</fills>'
      '<borders count="2">'
      '<border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border>'
      '<left style="thin"><color rgb="FFBFC7D2"/></left>'
      '<right style="thin"><color rgb="FFBFC7D2"/></right>'
      '<top style="thin"><color rgb="FFBFC7D2"/></top>'
      '<bottom style="thin"><color rgb="FFBFC7D2"/></bottom>'
      '<diagonal/></border>'
      '</borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="14">'
      // 0 plain
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      // 1 title
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      // 2 header
      '<xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" '
      'applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      // 3 text
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>'
      // 4 money
      '<xf numFmtId="4" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'
      // 5 number (General)
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1">'
      '<alignment horizontal="right"/></xf>'
      // 6 total money
      '<xf numFmtId="4" fontId="2" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" '
      'applyFill="1" applyBorder="1"/>'
      // 7 total text
      '<xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>'
      // 8 note
      '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      // 9 money bold
      '<xf numFmtId="4" fontId="2" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" '
      'applyBorder="1"/>'
      // 10 total number
      '<xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" '
      'applyBorder="1" applyAlignment="1"><alignment horizontal="right"/></xf>'
      // 11 flagged text
      '<xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyFill="1" applyBorder="1"/>'
      // 12 group heading
      '<xf numFmtId="0" fontId="2" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" '
      'applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      // 13 subtitle
      '<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';
}

/// A cell: text, a number, or a [XlsxFormula]; null leaves it blank but
/// still draws the style (borders).
class XlsxCell {
  final Object? value;
  final int style;
  const XlsxCell(this.value, [this.style = Xlsx.plain]);
}

/// A formula with the value Excel shows before it recalculates.
class XlsxFormula {
  final String formula;
  final num cached;
  const XlsxFormula(this.formula, this.cached);
}

class XlsxSheet {
  final String name;
  final List<List<XlsxCell?>> rows = [];
  final List<String> _merges = [];
  final Map<int, double> _widths = {};
  final Map<int, double> _heights = {};
  int freezeRows = 0;
  int freezeColumns = 0;
  bool landscape = false;

  XlsxSheet(this.name);

  /// Appends a row and returns its 0-based index.
  int addRow(List<XlsxCell?> cells, {double? height}) {
    rows.add(cells);
    if (height != null) _heights[rows.length - 1] = height;
    return rows.length - 1;
  }

  void merge(int row, int fromColumn, int toColumn, {int? toRow}) {
    if (toColumn <= fromColumn && (toRow ?? row) == row) return;
    _merges.add('${Xlsx.ref(row, fromColumn)}:${Xlsx.ref(toRow ?? row, toColumn)}');
  }

  void width(int column, double chars) => _widths[column] = chars;

  String _xml() {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    if (landscape) b.write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>');
    b.write('<sheetViews><sheetView workbookViewId="0"');
    if (freezeRows > 0 || freezeColumns > 0) {
      b.write('>');
      final top = Xlsx.ref(freezeRows, freezeColumns);
      final pane = freezeRows > 0 && freezeColumns > 0
          ? 'bottomRight'
          : (freezeRows > 0 ? 'bottomLeft' : 'topRight');
      b.write('<pane');
      if (freezeColumns > 0) b.write(' xSplit="$freezeColumns"');
      if (freezeRows > 0) b.write(' ySplit="$freezeRows"');
      b.write(' topLeftCell="$top" activePane="$pane" state="frozen"/>');
      b.write('<selection pane="$pane" activeCell="$top" sqref="$top"/>');
      b.write('</sheetView>');
    } else {
      b.write('/>');
    }
    b.write('</sheetViews>');
    b.write('<sheetFormatPr defaultRowHeight="15"/>');
    if (_widths.isNotEmpty) {
      b.write('<cols>');
      final keys = _widths.keys.toList()..sort();
      for (final k in keys) {
        b.write('<col min="${k + 1}" max="${k + 1}" width="${_widths[k]}" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < rows.length; r++) {
      final h = _heights[r];
      b.write('<row r="${r + 1}"${h == null ? '' : ' ht="$h" customHeight="1"'}>');
      final cells = rows[r];
      for (var c = 0; c < cells.length; c++) {
        final cell = cells[c];
        if (cell == null) continue;
        final at = Xlsx.ref(r, c);
        final v = cell.value;
        final s = cell.style == Xlsx.plain ? '' : ' s="${cell.style}"';
        if (v == null) {
          b.write('<c r="$at"$s/>');
        } else if (v is XlsxFormula) {
          b.write('<c r="$at"$s><f>${Xlsx.escape(v.formula)}</f><v>${_num(v.cached)}</v></c>');
        } else if (v is num) {
          b.write('<c r="$at"$s><v>${_num(v)}</v></c>');
        } else {
          b.write('<c r="$at"$s t="inlineStr"><is><t xml:space="preserve">${Xlsx.escape(v.toString())}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (_merges.isNotEmpty) {
      b.write('<mergeCells count="${_merges.length}">');
      for (final m in _merges) {
        b.write('<mergeCell ref="$m"/>');
      }
      b.write('</mergeCells>');
    }
    b.write('<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>');
    if (landscape) b.write('<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/>');
    b.write('</worksheet>');
    return b.toString();
  }

  static String _num(num v) {
    if (v is int || v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    // Two decimals is all money and days ever need; avoids 0.30000000000000004.
    var s = v.toStringAsFixed(4);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }
}
