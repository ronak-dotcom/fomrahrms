import 'package:flutter/material.dart';
import '../multi_select_filter_field.dart';
import '../../utils/attendance_cycle.dart';
import '../../theme/app_theme.dart';
import '../filter_panel.dart';

enum QuickRange { today, thisWeek, payCycle, thisMonth, custom }

extension QuickRangeLabel on QuickRange {
  String get label => switch (this) {
        QuickRange.today => 'Today',
        QuickRange.thisWeek => 'This Week',
        // The period people are actually paid and assessed on. Offered
        // alongside the calendar month rather than replacing it, so a
        // calendar view is still one tap away.
        QuickRange.payCycle => 'Pay Cycle (26–25)',
        QuickRange.thisMonth => 'Calendar Month',
        QuickRange.custom => 'Custom',
      };
}

DateTimeRange rangeFor(QuickRange q) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (q) {
    case QuickRange.today:
      return DateTimeRange(start: today, end: today);
    case QuickRange.thisWeek:
      final start = today.subtract(Duration(days: today.weekday - 1));
      return DateTimeRange(start: start, end: today);
    case QuickRange.payCycle:
      return DateTimeRange(
        start: attendanceCycleStart(today),
        end: attendanceCycleEnd(today),
      );
    case QuickRange.thisMonth:
      return DateTimeRange(start: DateTime(today.year, today.month, 1), end: today);
    case QuickRange.custom:
      return DateTimeRange(start: today, end: today);
  }
}

/// Header for the Reports & Analytics page: title/subtitle, date-range
/// trigger + quick-range chips (the first real date-range picker in this
/// app — showDateRangePicker wrapped in a styled pill), Department/
/// Location/Role filter dropdowns (reusing FilterDropdownField), refresh,
/// and Export Report.
class ReportsHeader extends StatelessWidget {
  final DateTimeRange range;
  final QuickRange quickRange;
  final ValueChanged<QuickRange> onQuickRange;
  final ValueChanged<DateTimeRange> onCustomRange;

  final String? department;
  final List<String> departmentOptions;
  final ValueChanged<String?> onDepartmentChanged;
  /// Several employees at once, not one or all. Empty means everyone.
  final Set<String> employees;
  final List<String> employeeOptions;
  final ValueChanged<Set<String>> onEmployeesChanged;

  /// Several departments at once, for comparing two teams side by side.
  final Set<String> departments;
  final ValueChanged<Set<String>> onDepartmentsChanged;

  final String? location;
  final List<String> locationOptions;
  final ValueChanged<String?> onLocationChanged;

  final String? role;
  final List<String> roleOptions;
  final ValueChanged<String?> onRoleChanged;

  final VoidCallback onRefresh;
  final bool refreshing;
  final VoidCallback onExport;
  final VoidCallback? onExportCycleCsv;
  final VoidCallback? onExportCyclePdf;
  final VoidCallback? onExportPunctualityCsv;
  final VoidCallback? onExportPunctualityPdf;
  final bool punctualityEnabled;
  final bool exporting;

  const ReportsHeader({
    super.key,
    required this.range,
    required this.quickRange,
    required this.onQuickRange,
    required this.onCustomRange,
    required this.department,
    required this.departmentOptions,
    required this.onDepartmentChanged,
    this.employees = const {},
    this.employeeOptions = const [],
    required this.onEmployeesChanged,
    this.departments = const {},
    required this.onDepartmentsChanged,
    required this.location,
    required this.locationOptions,
    required this.onLocationChanged,
    required this.role,
    required this.roleOptions,
    required this.onRoleChanged,
    required this.onRefresh,
    required this.refreshing,
    required this.onExport,
    this.onExportCycleCsv,
    this.onExportCyclePdf,
    this.onExportPunctualityCsv,
    this.onExportPunctualityPdf,
    this.punctualityEnabled = false,
    required this.exporting,
  });

  static String _fmt(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: range,
    );
    if (picked != null) onCustomRange(picked);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 900;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Reports & Analytics', style: AppTheme.pageHeading),
              const SizedBox(height: 4),
              const Text('Real-time insights and comprehensive analytics across your organization.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ]),
          ),
          if (!narrow) ...[
            const SizedBox(width: 16),
            _refreshButton(),
            const SizedBox(width: 8),
            _exportButton(),
          ],
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _dateRangeButton(context),
          for (final q in [QuickRange.today, QuickRange.thisWeek, QuickRange.payCycle, QuickRange.thisMonth])
            _quickChip(q),
          // Multi-select, not single. The old dropdowns could express
          // "everyone", "one department" or "one person" — but not "Ronak,
          // Sijo and Jose", so comparing an arbitrary handful meant looking at
          // each in turn and holding the numbers in your head.
          SizedBox(
            width: 210,
            child: MultiSelectFilterField(
              label: 'Employees',
              selected: employees,
              options: employeeOptions,
              allLabel: 'All Employees',
              onChanged: onEmployeesChanged,
            ),
          ),
          SizedBox(
            width: 200,
            child: MultiSelectFilterField(
              label: 'Departments',
              selected: departments,
              options: departmentOptions,
              allLabel: 'All Departments',
              icon: Icons.apartment_rounded,
              onChanged: onDepartmentsChanged,
            ),
          ),
          SizedBox(
            width: 170,
            child: FilterDropdownField<String>(
              label: 'Location',
              value: location,
              options: locationOptions,
              labelOf: (o) => o,
              allLabel: 'All Locations',
              onChanged: onLocationChanged,
            ),
          ),
          SizedBox(
            width: 170,
            child: FilterDropdownField<String>(
              label: 'Employee Type',
              value: role,
              options: roleOptions,
              labelOf: (o) => o,
              allLabel: 'All Types',
              onChanged: onRoleChanged,
            ),
          ),
          if (narrow) ...[
            _refreshButton(),
            _exportButton(),
          ],
        ]),
      ]);
    });
  }

  Widget _dateRangeButton(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _pickCustomRange(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_today_rounded, size: 15, color: AppTheme.textSecondary),
            const SizedBox(width: 8),
            Text('${_fmt(range.start)} - ${_fmt(range.end)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppTheme.textSecondary),
          ]),
        ),
      );

  Widget _quickChip(QuickRange q) {
    final selected = quickRange == q;
    return GestureDetector(
      onTap: () => onQuickRange(q),
      child: AnimatedContainer(
        duration: AppTheme.fastAnim,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppTheme.primaryBlue : AppTheme.borderSubtle),
        ),
        child: Text(q.label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppTheme.textPrimary)),
      ),
    );
  }

  Widget _refreshButton() => Tooltip(
        message: 'Refresh',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: refreshing ? null : onRefresh,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: refreshing
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.textPrimary),
          ),
        ),
      );

  /// Export offers three formats rather than one: the KPI summary that
  /// already existed, plus the monthly attendance sheet as CSV or PDF. The
  /// sheet is what HR reconciles against payroll, so CSV matters more than
  /// PDF — a PDF cannot be pasted into next month's workbook.
  Widget _exportButton() => PopupMenuButton<String>(
        enabled: !exporting,
        tooltip: 'Export',
        onSelected: (v) {
          switch (v) {
            case 'summary':
              onExport();
            case 'sheet_csv':
              onExportCycleCsv?.call();
            case 'sheet_pdf':
              onExportCyclePdf?.call();
            case 'punctuality_csv':
              onExportPunctualityCsv?.call();
            case 'punctuality_pdf':
              onExportPunctualityPdf?.call();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'sheet_csv',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.table_chart_outlined, size: 18),
              title: const Text('Attendance sheet (Excel/CSV)'),
              subtitle: Text(employees.isEmpty
                  ? 'Pay cycle, all employees'
                  : 'Pay cycle, ${employees.length} selected'),
            ),
          ),
          PopupMenuItem(
            value: 'sheet_pdf',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              title: const Text('Attendance sheet (PDF)'),
              subtitle: Text(employees.isEmpty
                  ? 'Pay cycle, all employees'
                  : 'Pay cycle, ${employees.length} selected'),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'punctuality_csv',
            enabled: punctualityEnabled,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.schedule_rounded, size: 18,
                  color: punctualityEnabled ? null : AppTheme.textSecondary.withValues(alpha: 0.4)),
              title: const Text('Punctuality detail (CSV)'),
              subtitle: Text(punctualityEnabled
                  ? 'Every late check-in, ${employees.length} selected'
                  : 'Select employees above first'),
            ),
          ),
          PopupMenuItem(
            value: 'punctuality_pdf',
            enabled: punctualityEnabled,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.schedule_rounded, size: 18,
                  color: punctualityEnabled ? null : AppTheme.textSecondary.withValues(alpha: 0.4)),
              title: const Text('Punctuality detail (PDF)'),
              subtitle: Text(punctualityEnabled
                  ? 'Every late check-in, ${employees.length} selected'
                  : 'Select employees above first'),
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'summary',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.insert_chart_outlined, size: 18),
              title: Text('Summary report (PDF)'),
              subtitle: Text('Headline figures for the range'),
            ),
          ),
        ],
        // IgnorePointer: a disabled ElevatedButton still absorbs the tap, so
        // without this the popup would never open. The face is decoration
        // only; PopupMenuButton handles the gesture.
        child: IgnorePointer(child: _exportButtonFace()),
      );

  Widget _exportButtonFace() => ElevatedButton.icon(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: exporting
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.file_download_outlined, size: 18),
        label: const Text('Export Report',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );
}
