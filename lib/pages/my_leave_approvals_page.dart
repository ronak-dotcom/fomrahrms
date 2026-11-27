import 'package:flutter/material.dart';
import '../models/leave_store.dart';
import '../models/user_session.dart';
import '../services/supabase_service.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

class MyLeaveApprovalsPage extends StatefulWidget {
  const MyLeaveApprovalsPage({super.key});

  @override
  State<MyLeaveApprovalsPage> createState() => _MyLeaveApprovalsPageState();
}

class _MyLeaveApprovalsPageState extends State<MyLeaveApprovalsPage> {
  static Color get _color => AppTheme.accentBlue;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final fresh = await SupabaseService.fetchLeaveApplications()
          .timeout(const Duration(seconds: 8));
      if (fresh.isNotEmpty) {
        LeaveStore.applications
          ..clear()
          ..addAll(fresh);
        LeaveStore.syncCounter();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // Only show applications for the currently logged-in employee
  List<LeaveApplication> get _apps => LeaveStore.applications
      .where((a) => a.employeeName == UserSession.name)
      .toList();

  int get _pending  => _apps.where((a) => a.effectiveStatus == LeaveApprovalStatus.pending).length;
  int get _approved => _apps.where((a) => a.effectiveStatus == LeaveApprovalStatus.approved).length;
  int get _denied   => _apps.where((a) => a.effectiveStatus == LeaveApprovalStatus.denied).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const NavBackButton(),
              const SizedBox(width: 8),
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.approval_rounded,
                    color: _color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text('Leave History',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: Icon(Icons.refresh_rounded, color: _color),
                onPressed: _loadData,
              ),
            ]),
            const SizedBox(height: 24),

            // Status summary row
            Row(children: [
              _StatusChip('Pending',  Icons.hourglass_empty_rounded,
                  Colors.orange.shade700, _pending),
              const SizedBox(width: 10),
              _StatusChip('Approved', Icons.check_circle_rounded,
                  Colors.green.shade700, _approved),
              const SizedBox(width: 10),
              _StatusChip('Denied',   Icons.cancel_rounded,
                  Colors.red.shade700, _denied),
            ]),
            const SizedBox(height: 20),

            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(),
              ))
            else if (_apps.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Column(children: [
                      Icon(Icons.inbox_rounded,
                          size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 10),
                      Text('No leave history yet',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('Leaves you apply will appear here with their approval status.',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 12)),
                    ]),
                  ),
                ),
              )
            else
              ..._apps.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AppCard(app: a),
                  )),
          ],
        ),
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  final LeaveApplication app;
  const _AppCard({required this.app});

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Color _statusColor(LeaveApprovalStatus s) => switch (s) {
        LeaveApprovalStatus.approved => Colors.green.shade700,
        LeaveApprovalStatus.denied   => Colors.red.shade700,
        LeaveApprovalStatus.pending  => Colors.orange.shade700,
      };

  IconData _statusIcon(LeaveApprovalStatus s) => switch (s) {
        LeaveApprovalStatus.approved => Icons.check_circle_rounded,
        LeaveApprovalStatus.denied   => Icons.cancel_rounded,
        LeaveApprovalStatus.pending  => Icons.hourglass_empty_rounded,
      };

  String _statusLabel(LeaveApprovalStatus s) => switch (s) {
        LeaveApprovalStatus.approved => 'Approved',
        LeaveApprovalStatus.denied   => 'Denied',
        LeaveApprovalStatus.pending  => 'Pending',
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Align(
              alignment: Alignment.centerRight,
              child: Text(app.id,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ),
            const SizedBox(height: 6),

            Wrap(spacing: 16, runSpacing: 6, children: [
              _InfoChip(Icons.calendar_today_rounded,
                  '${_fmt(app.from)} → ${_fmt(app.to)}'),
              _InfoChip(Icons.numbers_rounded,
                  app.durationLabel),
              _InfoChip(Icons.access_time_rounded,
                  'Applied: ${_fmt(app.appliedOn)}'),
              if (app.reason.isNotEmpty)
                _InfoChip(Icons.notes_rounded, app.reason),
            ]),
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 10),

            // Approval status — employees see final status only, no names
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Status',
                  style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              _StatusPill(
                _statusLabel(app.effectiveStatus),
                _statusColor(app.effectiveStatus),
                _statusIcon(app.effectiveStatus),
              ),
              // Show rejection reason (without name) so employee understands why
              if (app.effectiveStatus == LeaveApprovalStatus.denied &&
                  app.effectiveComment.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 13, color: Colors.red.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          app.effectiveComment,
                          style: TextStyle(
                              fontSize: 12, color: Colors.red.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusPill(this.label, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
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
      Icon(icon, size: 12, color: const Color(0xFF6B7280)),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
    ]);
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int count;
  const _StatusChip(this.label, this.icon, this.color, this.count);

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
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}
