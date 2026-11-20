import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

/// Management-only queue: confirmations HR has recommended (or that
/// Management has already decided on). Since 19 Nov 2026 confirmation is
/// decided by HR and Management only; older requests also passed the
/// reporting manager. Requests denied before Management never reach this page.
class OnrollApprovalsPage extends StatefulWidget {
  const OnrollApprovalsPage({super.key});

  @override
  State<OnrollApprovalsPage> createState() => _OnrollApprovalsPageState();
}

class _OnrollApprovalsPageState extends State<OnrollApprovalsPage> {
  static Color get _color => AppTheme.sidebarSelectedBg;
  List<AppUser> _all = [];
  bool _loading = true;
  String _search = '';
  String? _filterStatus; // 'pending' | 'accepted' | 'denied'

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _loading = true);
    final users = await UserStore.load();
    if (mounted) setState(() { _all = users; _loading = false; });
  }

  List<AppUser> get _requests => _all
      .where((u) => u.onrollAwaitingManagement || u.onrollManagementStatus != 'pending')
      .toList();

  String _effectiveStatus(AppUser u) =>
      u.onrollAwaitingManagement ? 'pending' : u.onrollManagementStatus;

  bool _matchesFilter(AppUser u) {
    final matchSearch =
        _search.isEmpty || u.name.toLowerCase().contains(_search.toLowerCase());
    final matchStatus = _filterStatus == null || _effectiveStatus(u) == _filterStatus;
    return matchSearch && matchStatus;
  }

  List<AppUser> get _filtered => _requests.where(_matchesFilter).toList();

  int get _pendingCount  => _requests.where((u) => _effectiveStatus(u) == 'pending').length;
  int get _approvedCount => _requests.where((u) => _effectiveStatus(u) == 'accepted').length;
  int get _deniedCount   => _requests.where((u) => _effectiveStatus(u) == 'denied').length;

  Future<void> _approve(AppUser u) async {
    setState(() {
      u.onrollManagementStatus = 'accepted';
      u.onrollManagementComment = '';
      u.onrollManagementDecidedAt = DateTime.now().toIso8601String();
      u.onrollConfirmedAt = DateTime.now().toIso8601String();
    });
    await UserStore.upsertOne(u);
    NotificationService.onrollFinalDecided(employeeEmail: u.email, approved: true);
  }

  Future<void> _deny(AppUser u) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Deny On-Roll Request',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Reason for denial (optional):',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'e.g. Performance concerns',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            child: const Text('Deny'),
          ),
        ],
      ),
    );
    if (ok != true) { ctrl.dispose(); return; }
    final comment = ctrl.text.trim();
    ctrl.dispose();
    setState(() {
      u.onrollManagementStatus = 'denied';
      u.onrollManagementComment = comment;
      u.onrollManagementDecidedAt = DateTime.now().toIso8601String();
    });
    await UserStore.upsertOne(u);
    NotificationService.onrollFinalDecided(employeeEmail: u.email, approved: false);
  }

  Future<void> _undo(AppUser u) async {
    setState(() {
      u.onrollManagementStatus = 'pending';
      u.onrollManagementComment = '';
      u.onrollManagementDecidedAt = '';
      u.onrollConfirmedAt = '';
    });
    await UserStore.upsertOne(u);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Builder(builder: (context) {
            final narrow = MediaQuery.of(context).size.width < 600;
            return Row(children: [
              const NavBackButton(),
              SizedBox(width: narrow ? 4 : 8),
              if (!narrow) ...[
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: _color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.verified_user_rounded, color: _color, size: 26),
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('On-Roll Approvals',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium),
                  if (!narrow)
                    const Text('Confirmations recommended by HR',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                ]),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: Icon(Icons.refresh_rounded, color: _color),
                onPressed: _loadData,
              ),
            ]);
          }),
          const SizedBox(height: 24),

          Row(children: [
            _SummaryChip(
              label: 'Pending', count: _pendingCount, icon: Icons.hourglass_empty_rounded,
              color: Colors.orange.shade700,
              active: _filterStatus == 'pending',
              onTap: () => setState(() => _filterStatus = _filterStatus == 'pending' ? null : 'pending'),
            ),
            const SizedBox(width: 10),
            _SummaryChip(
              label: 'Approved', count: _approvedCount, icon: Icons.check_circle_rounded,
              color: Colors.green.shade700,
              active: _filterStatus == 'accepted',
              onTap: () => setState(() => _filterStatus = _filterStatus == 'accepted' ? null : 'accepted'),
            ),
            const SizedBox(width: 10),
            _SummaryChip(
              label: 'Denied', count: _deniedCount, icon: Icons.cancel_rounded,
              color: Colors.red.shade700,
              active: _filterStatus == 'denied',
              onTap: () => setState(() => _filterStatus = _filterStatus == 'denied' ? null : 'denied'),
            ),
          ]),
          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Search employee...',
                  prefixIcon: Icon(Icons.search_rounded, color: _color, size: 20),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => setState(() => _search = ''))
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_loading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: CircularProgressIndicator()))
          else if (_requests.isEmpty)
            _emptyCard(
              icon: Icons.inbox_rounded,
              title: 'No requests awaiting Management yet',
              subtitle: 'Confirmations appear here once HR has recommended them.',
            )
          else if (filtered.isEmpty)
            _emptyCard(icon: Icons.search_off_rounded, title: 'No results match your search', subtitle: '')
          else
            ...filtered.map((u) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _OnrollRequestCard(
                    user: u,
                    onApprove: () => _approve(u),
                    onDeny: () => _deny(u),
                    onUndo: () => _undo(u),
                  ),
                )),
        ]),
      ),
    );
  }

  Widget _emptyCard({required IconData icon, required String title, required String subtitle}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Center(
          child: Column(children: [
            Icon(icon, size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            ],
          ]),
        ),
      ),
    );
  }
}

// ── Request card ─────────────────────────────────────────────────────────────

class _OnrollRequestCard extends StatefulWidget {
  final AppUser user;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback onUndo;

  const _OnrollRequestCard({
    required this.user,
    required this.onApprove,
    required this.onDeny,
    required this.onUndo,
  });

  @override
  State<_OnrollRequestCard> createState() => _OnrollRequestCardState();
}

class _OnrollRequestCardState extends State<_OnrollRequestCard> {
  static const _undoWindow = Duration(minutes: 10);
  Timer? _timer;

  bool get _canUndo {
    final ts = widget.user.onrollManagementDecidedAt;
    if (ts.isEmpty) return false;
    try {
      return DateTime.now().difference(DateTime.parse(ts)) < _undoWindow;
    } catch (_) { return false; }
  }

  String get _countdown {
    final ts = widget.user.onrollManagementDecidedAt;
    if (ts.isEmpty) return '';
    try {
      final remaining = _undoWindow - DateTime.now().difference(DateTime.parse(ts));
      if (remaining.isNegative) return '';
      final m = remaining.inMinutes;
      final s = remaining.inSeconds % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  @override
  void initState() {
    super.initState();
    _maybeStartTimer();
  }

  @override
  void didUpdateWidget(covariant _OnrollRequestCard old) {
    super.didUpdateWidget(old);
    _timer?.cancel();
    _maybeStartTimer();
  }

  void _maybeStartTimer() {
    if (!_canUndo) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (!_canUndo) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final status = u.onrollAwaitingManagement ? 'pending' : u.onrollManagementStatus;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.sidebarSelectedBg.withValues(alpha: 0.1),
              child: Text(
                u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                style: TextStyle(
                    color: AppTheme.sidebarSelectedBg, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                if (u.designation.isNotEmpty)
                  Text(u.designation, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ]),
            ),
            _statusPill(status),
          ]),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.sidebarSelectedBg.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.sidebarSelectedBg.withValues(alpha: 0.08)),
            ),
            child: Column(children: [
              _detailRow(Icons.badge_rounded, 'Employee ID', u.employeeId),
              const SizedBox(height: 8),
              _detailRow(Icons.calendar_today_rounded, 'Date of Joining', u.dateOfJoining),
              const SizedBox(height: 8),
              _detailRow(Icons.verified_user_rounded, 'HR Decision',
                  'Accepted${u.onrollHrComment.isNotEmpty ? ' — "${u.onrollHrComment}"' : ''}'),
              // Older requests also went through the reporting manager; new
              // ones are decided by HR and Management only.
              if (u.onrollManagerComment != SupabaseService.onrollManagerNotRequired) ...[
                const SizedBox(height: 8),
                _detailRow(Icons.manage_accounts_rounded, 'Manager Decision',
                    'Accepted${u.onrollManagerComment.isNotEmpty ? ' — "${u.onrollManagerComment}"' : ''}'),
              ],
            ]),
          ),
          const SizedBox(height: 14),

          if (status == 'pending')
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onDeny,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Deny'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade400,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.onApprove,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ])
          else
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (status == 'accepted' ? Colors.green : Colors.red).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(status == 'accepted' ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 16,
                      color: status == 'accepted' ? Colors.green.shade700 : Colors.red.shade700),
                  const SizedBox(width: 6),
                  Text(status == 'accepted' ? 'Approved' : 'Denied',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: status == 'accepted' ? Colors.green.shade700 : Colors.red.shade700)),
                ]),
              ),
              const Spacer(),
              if (_canUndo)
                TextButton.icon(
                  onPressed: widget.onUndo,
                  icon: const Icon(Icons.undo_rounded, size: 15),
                  label: Text('Undo ($_countdown)', style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey.shade500),
                ),
            ]),

          if (status == 'denied' && u.onrollManagementComment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(u.onrollManagementComment,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _statusPill(String status) {
    final color = status == 'accepted'
        ? Colors.green.shade700
        : status == 'denied' ? Colors.red.shade700 : Colors.orange.shade700;
    final label = status == 'accepted' ? 'Approved' : status == 'denied' ? 'Denied' : 'Pending';
    final icon = status == 'accepted'
        ? Icons.check_circle_rounded
        : status == 'denied' ? Icons.cancel_rounded : Icons.hourglass_empty_rounded;
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
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: Colors.grey.shade500),
      const SizedBox(width: 8),
      Text('$label: ',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
      Expanded(
        child: Text(value,
            style: TextStyle(
                fontSize: 12, color: AppTheme.sidebarSelectedBg, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

// ── Summary chip ─────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _SummaryChip({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? color : color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: active ? Colors.white : color),
          const SizedBox(width: 6),
          Text('$count $label',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : color)),
        ]),
      ),
    );
  }
}
