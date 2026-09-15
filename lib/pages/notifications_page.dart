import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/leave_store.dart';
import '../models/notification_category.dart';
import '../models/notification_store.dart';
import '../models/user_session.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/back_button.dart';
import '../widgets/filter_panel.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;
  // null = "All" — the view filter only narrows what's currently shown,
  // it doesn't change what the user receives (that's the mute preference).
  String? _viewFilter;
  // Default view is the last 24h (matches the unread badge); nothing is
  // ever deleted — flip to "All time" to see everything, still further
  // narrowable by the category chips below.
  bool _showAll = false;

  // Anchors the preferences dropdown to the tune button at the top-left so
  // it opens as a small anchored card instead of a full bottom sheet.
  final LayerLink _prefsLink = LayerLink();
  OverlayEntry? _prefsOverlay;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _prefsOverlay?.remove();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final list = await SupabaseService.fetchNotifications();
    NotificationStore.all
      ..clear()
      ..addAll(list);
    NotificationStore.recomputeUnread();
    if (mounted) setState(() => _loading = false);
  }

  /// Whether this notification announces a leave request the viewer can
  /// decide. Restricted to leave because that is where the request id is
  /// carried; other processes still open their screen.
  bool _canDecide(AppNotification n) {
    if (n.type != 'leave_submitted' || n.sourceId.isEmpty) return false;
    if (UserSession.role == UserRole.employee) return false;
    // Already decided ones stay in the list as a record, so the buttons must
    // not reappear on them.
    final app = LeaveStore.applications
        .where((a) => a.id == n.sourceId)
        .firstOrNull;
    return app != null && app.managerStatus == LeaveApprovalStatus.pending;
  }

  Future<void> _decide(AppNotification n, String action) async {
    final app = LeaveStore.applications
        .where((a) => a.id == n.sourceId)
        .firstOrNull;
    if (app == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That request could not be found — it may have been '
              'withdrawn.')));
      return;
    }

    // A reason is required to refuse or escalate, and optional to approve:
    // the person affected needs to know why, and an escalation without one
    // gives Management nothing to act on.
    String reason = '';
    if (action != 'approve') {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(action == 'reject' ? 'Reject request' : 'Escalate to Management'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${app.employeeName} — ${app.leaveType}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Reason', border: OutlineInputBorder()),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      if (ctrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('A reason is needed.')));
        return;
      }
      reason = ctrl.text.trim();
    }

    String? err;
    if (action == 'escalate') {
      err = await SupabaseService.escalateToManagement(
          table: 'leave_applications', id: app.id, reason: reason);
      if (err == null) {
        NotificationService.escalated(
          process: app.leaveType,
          employeeName: app.employeeName,
          escalatedBy: UserSession.name,
          reason: reason,
        );
      }
    } else {
      final approved = action == 'approve';
      final newStatus =
          approved ? LeaveApprovalStatus.approved : LeaveApprovalStatus.denied;
      // Management's decision is written to its own columns so a manager's is
      // never overwritten; using the manager path for Management would put the
      // decision in the wrong place and leave it looking undecided.
      if (UserSession.role == UserRole.management) {
        await SupabaseService.updateLeaveManagementStatus(app.id, newStatus,
            decidedBy: UserSession.name, rejectionComment: reason);
      } else {
        await SupabaseService.updateLeaveManagerStatus(app.id, newStatus,
            decidedBy: UserSession.name, rejectionComment: reason);
      }
      app.managerStatus = newStatus;
      app.decidedBy = UserSession.name;
      app.rejectionComment = reason;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err == null
          ? '${app.employeeName}\u2019s ${app.leaveType} — $action done.'
          : 'Could not complete: $err'),
      backgroundColor: err == null ? Colors.teal.shade700 : Colors.red.shade700,
    ));
    if (err == null) setState(() {});
  }

  Future<void> _open(AppNotification n) async {
    await NotificationService.markRead(n);
    if (!mounted) return;
    setState(() {});
    // Only navigate if the route actually resolves to a registered page —
    // a stale/misrouted notification should do nothing rather than land on
    // the router's "Page not found" screen.
    // Resolved against THIS user's role. The prefix cannot be decided when the
    // notification is written, because that lookup runs as the sender and RLS
    // often stops them reading the recipient's row — the role comes back null
    // and the link points at a prefix the recipient's role cannot open.
    final route = NotificationService.resolveRoute(n.route);
    if (route.isNotEmpty &&
        !GoRouter.of(context).configuration.findMatch(route).isError) {
      context.go(route);
    }
  }

  void _togglePreferences() {
    if (_prefsOverlay != null) {
      _closePreferences();
    } else {
      _openPreferences();
    }
  }

  void _openPreferences() {
    final overlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closePreferences,
            ),
          ),
          CompositedTransformFollower(
            link: _prefsLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 44),
            child: _PreferencesDropdown(onClose: _closePreferences),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(overlay);
    _prefsOverlay = overlay;
  }

  void _closePreferences() {
    _prefsOverlay?.remove();
    _prefsOverlay = null;
    if (mounted) setState(() {}); // muted categories may have changed
  }

  @override
  Widget build(BuildContext context) {
    final all = NotificationStore.forCurrentUser();
    final scoped = _showAll ? all : all.where((n) => n.isRecent).toList();
    final items = _viewFilter == null
        ? scoped
        : scoped.where((n) => categoryFor(n.type).id == _viewFilter).toList();
    final unread = items.where((n) => !n.isReadBy(UserSession.email)).toList();
    final presentCategoryIds = scoped.map((n) => categoryFor(n.type).id).toSet();
    final presentCategories = notificationCategories
        .where((c) => presentCategoryIds.contains(c.id))
        .toList();
    final hasOlder = !_showAll && all.length > scoped.length;

    final narrow = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(narrow ? 12 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const NavBackButton(),
                SizedBox(width: narrow ? 2 : 8),
                CompositedTransformTarget(
                  link: _prefsLink,
                  child: IconButton(
                    onPressed: _togglePreferences,
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: 'Notification preferences',
                  ),
                ),
                if (!narrow) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.lightBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.notifications_rounded,
                        color: AppTheme.primaryBlue, size: 26),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Text('Notifications',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium),
                ),
                if (unread.isNotEmpty)
                  narrow
                      ? IconButton(
                          tooltip: 'Mark all read',
                          onPressed: () async {
                            await NotificationService.markAllRead(items);
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.done_all_rounded, size: 20),
                        )
                      : TextButton.icon(
                          onPressed: () async {
                            await NotificationService.markAllRead(items);
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.done_all_rounded, size: 18),
                          label: const Text('Mark all read'),
                        ),
                IconButton(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilterTriggerButton(
              hasActiveFilters: _showAll || _viewFilter != null,
              onTap: () {
                bool showAllDraft = _showAll;
                String? viewFilterDraft = _viewFilter;
                showFilterPanel(
                  context,
                  title: 'Filters',
                  onReset: () { showAllDraft = false; viewFilterDraft = null; },
                  onApply: () => setState(() { _showAll = showAllDraft; _viewFilter = viewFilterDraft; }),
                  builder: (context, setPanelState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FilterChipGroup<bool>(
                      label: 'Time range',
                      value: showAllDraft ? true : null,
                      options: const [true],
                      labelOf: (_) => 'All time',
                      onChanged: (v) => setPanelState(() => showAllDraft = v ?? false),
                    ),
                    if (presentCategories.length > 1)
                      FilterChipGroup<String>(
                        label: 'Category',
                        value: viewFilterDraft,
                        options: presentCategories.map((c) => c.id).toList(),
                        labelOf: (id) => presentCategories.firstWhere((c) => c.id == id).label,
                        onChanged: (v) => setPanelState(() => viewFilterDraft = v),
                      ),
                  ]),
                );
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? _EmptyState(
                          filtered: _viewFilter != null,
                          hasOlder: hasOlder,
                          onShowAll: () => setState(() => _showAll = true),
                        )
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _NotificationTile(
                              notification: items[i],
                              onTap: () => _open(items[i]),
                              onDecide: _canDecide(items[i])
                                  ? (action) => _decide(items[i], action)
                                  : null,
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dropdown card, anchored below the tune button at the page's top-left,
/// where the user picks which categories of notification they want to
/// receive at all — distinct from the page's view filter, which only
/// changes what's shown right now.
class _PreferencesDropdown extends StatefulWidget {
  final VoidCallback onClose;
  const _PreferencesDropdown({required this.onClose});

  @override
  State<_PreferencesDropdown> createState() => _PreferencesDropdownState();
}

class _PreferencesDropdownState extends State<_PreferencesDropdown> {
  late Set<String> _muted = {...NotificationStore.mutedCategories};
  late final String _roleLabel = currentRoleLabel();
  late final List<NotificationCategory> _categories = categoriesForRole(_roleLabel);
  bool _saving = false;

  // [_muted] holds both category ids ("mute this whole bucket") and
  // individual type strings ("mute just this one kind") — see
  // NotificationStore.isForCurrentUser, which checks both the same way.
  Future<void> _toggleCategory(String categoryId, bool getNotified) async {
    setState(() {
      if (getNotified) {
        _muted.remove(categoryId);
      } else {
        _muted.add(categoryId);
      }
      _saving = true;
    });
    await _persist();
  }

  Future<void> _toggleType(String type, bool getNotified) async {
    setState(() {
      if (getNotified) {
        _muted.remove(type);
      } else {
        _muted.add(type);
      }
      _saving = true;
    });
    await _persist();
  }

  Future<void> _persist() async {
    NotificationStore.mutedCategories = _muted;
    NotificationStore.recomputeUnread();
    await SupabaseService.setMutedCategories(UserSession.email, _muted.toList());
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final width = (screenSize.width - 32).clamp(0, 340).toDouble();
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: width,
          constraints: BoxConstraints(maxHeight: screenSize.height * 0.65),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Notification preferences',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (_saving)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Choose which kinds of notifications you want to get — tap a '
                  'row to fine-tune the individual kinds inside it.',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final c in _categories) _CategoryTile(
                      category: c,
                      roleLabel: _roleLabel,
                      muted: _muted,
                      onToggleCategory: _toggleCategory,
                      onToggleType: _toggleType,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final NotificationCategory category;
  final String roleLabel;
  final Set<String> muted;
  final void Function(String categoryId, bool getNotified) onToggleCategory;
  final void Function(String type, bool getNotified) onToggleType;
  const _CategoryTile({
    required this.category,
    required this.roleLabel,
    required this.muted,
    required this.onToggleCategory,
    required this.onToggleType,
  });

  @override
  Widget build(BuildContext context) {
    final categoryMuted = muted.contains(category.id);
    // Only the sub-types this role can actually be sent — e.g. Management
    // never gets personal check-in/out notices, so there's no point in
    // showing a toggle for them.
    final subTypes = subTypesForRole(category, roleLabel);
    // Always render as a dropdown — even single-subtype categories — so the
    // master switch lands at the same x position on every row instead of
    // jumping right when there's no chevron to make room for.
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      leading: Icon(category.icon, color: AppTheme.primaryBlue, size: 22),
      title: Row(children: [
        Expanded(
          child: Text(category.label, style: const TextStyle(fontSize: 14)),
        ),
        Switch(
          value: !categoryMuted,
          onChanged: (v) => onToggleCategory(category.id, v),
          activeColor: AppTheme.primaryBlue,
        ),
      ]),
      children: [
        for (final st in subTypes)
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(st.label,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: categoryMuted
                          ? AppTheme.textSecondary.withValues(alpha: 0.5)
                          : AppTheme.textSecondary)),
              value: !categoryMuted && !muted.contains(st.type),
              onChanged: categoryMuted ? null : (v) => onToggleType(st.type, v),
              activeColor: AppTheme.primaryBlue,
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool filtered;
  final bool hasOlder;
  final VoidCallback? onShowAll;
  const _EmptyState({this.filtered = false, this.hasOlder = false, this.onShowAll});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.lightBlue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
                filtered ? Icons.filter_alt_off_rounded : Icons.notifications_none_rounded,
                color: AppTheme.primaryBlue, size: 40),
          ),
          const SizedBox(height: 16),
          Text(filtered ? 'Nothing in this category' : 'You\'re all caught up',
              style: Theme.of(context).textTheme.headlineSmall),
          if (hasOlder) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onShowAll,
              child: const Text('Show older notifications'),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  /// Non-null only where this notification announces something the viewer can
  /// actually decide — an approver seeing buttons they cannot use is worse
  /// than none at all.
  final void Function(String action)? onDecide;
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    this.onDecide,
  });

  static Widget _act(String label, Color color, VoidCallback onPressed) =>
      SizedBox(
        height: 30,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(label,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
        ),
      );

  IconData get _icon => categoryFor(notification.type).icon;

  String get _relativeTime {
    final diff = DateTime.now().difference(notification.createdAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final d = notification.createdAt;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isReadBy(UserSession.email);
    return Material(
      color: unread
          ? AppTheme.lightBlue.withValues(alpha: 0.35)
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon, color: AppTheme.primaryBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(notification.body,
                          style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
                    ],
                    const SizedBox(height: 4),
                    Text(_relativeTime,
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    // Decided here rather than by navigating. Two similarly
                    // named leave screens meant people repeatedly landed on
                    // the view-only one and concluded approvals were broken;
                    // the decision belongs where the request is announced.
                    if (onDecide != null) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        _act('Approve', Colors.green.shade700,
                            () => onDecide!('approve')),
                        const SizedBox(width: 6),
                        _act('Reject', Colors.red.shade700,
                            () => onDecide!('reject')),
                        const SizedBox(width: 6),
                        _act('Escalate', Colors.indigo.shade600,
                            () => onDecide!('escalate')),
                      ]),
                    ],
                  ],
                ),
              ),
              if (unread)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: AppTheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
