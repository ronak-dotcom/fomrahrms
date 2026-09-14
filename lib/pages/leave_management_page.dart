import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/user_session.dart';
import '../models/leave_store.dart';
import '../services/supabase_service.dart';
import '../utils/month_picker.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

class LeaveManagementPage extends StatefulWidget {
  const LeaveManagementPage({super.key});

  @override
  State<LeaveManagementPage> createState() => _LeaveManagementPageState();
}

class _LeaveManagementPageState extends State<LeaveManagementPage> {
  static Color get _accentColor => AppTheme.primaryBlue;

  DateTime? _selectedMonth;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  List<LeaveApplication> get _applications => LeaveStore.applications;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final list = await SupabaseService.fetchLeaveApplications()
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (list.isNotEmpty) {
        LeaveStore.applications
          ..clear()
          ..addAll(list);
        LeaveStore.syncCounter();
      }
      setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  List<LeaveApplication> get _filtered {
    return _applications.where((a) {
      final matchesSearch = _searchQuery.isEmpty ||
          a.employeeName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          a.leaveType.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesMonth = _selectedMonth == null ||
          (a.from.year == _selectedMonth!.year &&
              a.from.month == _selectedMonth!.month);
      return matchesSearch && matchesMonth;
    }).toList();
  }

  List<LeaveApplication> get _leaves =>
      _filtered.where((a) => a.leaveType != 'Permission' && a.leaveType != 'Comp Off').toList();

  List<LeaveApplication> get _permissions =>
      _filtered.where((a) => a.leaveType == 'Permission').toList();

  List<LeaveApplication> get _compOffs =>
      _filtered.where((a) => a.leaveType == 'Comp Off').toList();

  Future<void> _pickMonth() async {
    final picked = await showMonthPicker(context, _selectedMonth);
    if (picked != null && mounted) setState(() => _selectedMonth = picked);
  }

  @override
  Widget build(BuildContext context) {
    final leaves     = _leaves;
    final permissions = _permissions;
    final compOffs   = _compOffs;
    final filtered   = _filtered;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: null,
        body: SingleChildScrollView(child: Column(children: [
          // Fixed top area
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header row
              Row(children: [
                const NavBackButton(),
                const SizedBox(width: 8),
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.beach_access_rounded,
                      color: Theme.of(context).colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('Leave Management',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium),
                ),
                IconButton(
                  icon: Icon(Icons.refresh_rounded,
                      color: Theme.of(context).colorScheme.primary),
                  tooltip: 'Refresh',
                  onPressed: _reload,
                ),
              ]),
              const SizedBox(height: 16),

              // Search + month filter
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search employee or leave type...',
                          prefixIcon: Icon(Icons.search_rounded,
                              color: _accentColor, size: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: _accentColor, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _pickMonth,
                      icon: Icon(
                        _selectedMonth != null
                            ? Icons.calendar_today_rounded
                            : Icons.calendar_month_rounded,
                        size: 16,
                      ),
                      label: Text(_selectedMonth != null
                          ? monthLabel(_selectedMonth!)
                          : 'Month'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            _selectedMonth != null ? _accentColor : null,
                        side: _selectedMonth != null
                            ? BorderSide(color: _accentColor)
                            : null,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    if (_selectedMonth != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _selectedMonth = null),
                        tooltip: 'Clear',
                        color: _accentColor,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              // Status badges (reflect current filter)
              Row(children: [
                _StatusBadge(
                  'Pending',
                  Icons.hourglass_empty_rounded,
                  Colors.orange.shade700,
                  filtered
                      .where((a) =>
                          a.managerStatus == LeaveApprovalStatus.pending)
                      .length,
                ),
                const SizedBox(width: 10),
                _StatusBadge(
                  'Approved',
                  Icons.check_circle_rounded,
                  Colors.green.shade700,
                  filtered
                      .where((a) =>
                          a.managerStatus == LeaveApprovalStatus.approved)
                      .length,
                ),
                const SizedBox(width: 10),
                _StatusBadge(
                  'Denied',
                  Icons.cancel_rounded,
                  Colors.red.shade700,
                  filtered
                      .where((a) =>
                          a.managerStatus == LeaveApprovalStatus.denied)
                      .length,
                ),
              ]),
              const SizedBox(height: 12),

              // Tab bar — Leave / Permission / Comp Off
              TabBar(
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
                indicatorColor: Theme.of(context).colorScheme.primary,
                labelStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(text: 'Leave (${leaves.length})'),
                  Tab(text: 'Permission (${permissions.length})'),
                  Tab(text: 'Comp Off (${compOffs.length})'),
                ],
              ),
            ]),
          ),

          // Tab content — whole page (header, tab bar, and this) scrolls as
          // one via the SingleChildScrollView above, so this shows whichever
          // tab is selected rather than a bounded-height TabBarView.
          Builder(builder: (context) {
            final controller = DefaultTabController.of(context);
            return AnimatedBuilder(
              animation: controller,
              builder: (context, _) => switch (controller.index) {
                0 => _AppList(apps: leaves, emptyMessage: 'No leave applications.'),
                1 => _AppList(apps: permissions, emptyMessage: 'No permission applications.'),
                _ => _AppList(apps: compOffs, emptyMessage: 'No comp off applications.'),
              },
            );
          }),
        ])),
      ),
    );
  }
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// ── Scrollable list of applications ──────────────────────────────────────────

class _AppList extends StatelessWidget {
  final List<LeaveApplication> apps;
  final String emptyMessage;
  const _AppList({required this.apps, required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    if (apps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inbox_rounded, size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text(emptyMessage,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final app in apps)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ApplicationCard(app: app),
          ),
      ]),
    );
  }
}

// ── Leave card ────────────────────────────────────────────────────────────────

class _ApplicationCard extends StatelessWidget {
  final LeaveApplication app;
  const _ApplicationCard({required this.app});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.person_rounded,
                color: AppTheme.primaryBlue, size: 20),
            const SizedBox(width: 8),
            Text(app.employeeName,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 16, runSpacing: 6, children: [
            _InfoChip(Icons.calendar_today_rounded,
                '${_fmt(app.from)} → ${_fmt(app.to)}'),
            _InfoChip(
                Icons.numbers_rounded,
                app.isHalfDay
                    ? '½ day'
                    : '${app.days} day${app.days == 1 ? '' : 's'}'),
            if (app.reason.isNotEmpty)
              _InfoChip(Icons.notes_rounded, app.reason),
          ]),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 10),
          _DecisionRow(
            status: app.managerStatus,
            decidedBy: app.decidedBy,
            comment: app.rejectionComment,
          ),
        ]),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon,
          size: 13,
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.55)),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6))),
    ]);
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int count;
  const _StatusBadge(this.label, this.icon, this.color, this.count);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text('$count $label',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color)),
      ]),
    );
  }
}

class _DecisionRow extends StatelessWidget {
  final LeaveApprovalStatus status;
  final String decidedBy;
  final String comment;
  const _DecisionRow({
    required this.status,
    required this.decidedBy,
    required this.comment,
  });

  Color _color() => switch (status) {
        LeaveApprovalStatus.approved => Colors.green.shade700,
        LeaveApprovalStatus.denied   => Colors.red.shade700,
        LeaveApprovalStatus.pending  => Colors.orange.shade700,
      };

  String _label() => switch (status) {
        LeaveApprovalStatus.approved => 'Approved',
        LeaveApprovalStatus.denied   => 'Denied',
        LeaveApprovalStatus.pending  => 'Pending',
      };

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.manage_accounts_rounded,
              size: 13, color: Color(0xFF6B7280)),
          const SizedBox(width: 5),
          Text(
            status == LeaveApprovalStatus.pending
                ? 'Pending decision'
                : '${_label()} by ${decidedBy.isEmpty ? 'Manager' : decidedBy}',
            style: TextStyle(
                fontSize: 11, color: c, fontWeight: FontWeight.w700),
          ),
          // This screen lists requests but cannot decide them, and people
          // arriving from a notification reasonably expected to act here —
          // several concluded approvals had stopped working. Points at the
          // screen that does, rather than leaving them to find it.
          if (status == LeaveApprovalStatus.pending &&
              (UserSession.role == UserRole.hr ||
               UserSession.role == UserRole.management ||
               UserSession.isReportingManager)) ...[
            const Spacer(),
            TextButton(
              onPressed: () => context.push(switch (UserSession.role) {
                UserRole.management => '/management/leave/team-approvals',
                UserRole.hr => '/hr/leave/team-approvals',
                _ => '/manager/leave/team-approvals',
              }),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Approve / Reject',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
        if (status == LeaveApprovalStatus.denied && comment.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('"$comment"',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.red.shade700,
                  fontStyle: FontStyle.italic)),
        ],
      ]),
    );
  }
}
