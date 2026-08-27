import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import '../models/appraisal_store.dart' show visibleManagersForPicker;
import '../services/user_store.dart';
import '../services/supabase_service.dart';
import '../services/email_service.dart';
import '../constants/org_lists.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';
import 'employee_onboarding_page.dart' show OnboardingFormReadOnlyBody;

Color get _mgmtColor => AppTheme.sidebarSelectedBg;
Color get _mgmtLight => AppTheme.lightBlue;

// ── Page ──────────────────────────────────────────────────────────────────────

class AdministrationPage extends StatefulWidget {
  const AdministrationPage({super.key});

  @override
  State<AdministrationPage> createState() => _AdministrationPageState();
}

class _AdministrationPageState extends State<AdministrationPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  List<AppUser> _users = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() {}));
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final users = await UserStore.load();
    if (mounted) setState(() => _users = users);
  }

  Future<void> _upsertUser(AppUser u) async {
    if (_saving) return;
    setState(() => _saving = true);
    await UserStore.upsertOne(u);
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _deleteUser(AppUser u) async {
    if (_saving) return;
    setState(() { _users.remove(u); _saving = true; });
    await UserStore.deleteOne(u.email);
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    final hPad = narrow ? 16.0 : 24.0;

    return Material(
      color: null,
      child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header + tabs ────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(hPad, narrow ? 16 : 24, hPad, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const NavBackButton(),
                  const SizedBox(width: 8),
                  if (!narrow) ...[
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: _mgmtLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.admin_panel_settings_rounded,
                          color: _mgmtColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Administration',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _mgmtColor)),
                      if (!narrow)
                        const Text('Management access only',
                            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                    ]),
                  ),
                ]),
                if (!narrow) const SizedBox(height: 20),
                TabBar(
                  controller: _tabs,
                  labelColor: _mgmtColor,
                  unselectedLabelColor: const Color(0xFF6B7280),
                  indicatorColor: _mgmtColor,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(icon: Icon(Icons.how_to_reg_rounded, size: 18), text: 'Onboarding'),
                    Tab(icon: Icon(Icons.group_add_rounded, size: 18), text: 'Users'),
                  ],
                ),
              ],
            ),
          ),

          // ── Tab body ────────────────────────────────────────────────────
          switch (_tabs.index) {
            0 => const _OnboardingTab(),
            _ => _UsersTab(users: _users, onUpsert: _upsertUser, onDelete: _deleteUser),
          },
        ],
      )),
    );
  }
}

// ── Users tab ─────────────────────────────────────────────────────────────────

class _UsersTab extends StatelessWidget {
  final List<AppUser> users;
  final Future<void> Function(AppUser) onUpsert;
  final Future<void> Function(AppUser) onDelete;
  const _UsersTab({required this.users, required this.onUpsert, required this.onDelete});

  Color _roleColor(String role) {
    switch (role) {
      case 'HR':         return const Color(0xFF2563EB);
      case 'Manager':    return const Color(0xFF111827);
      case 'Management': return _mgmtColor;
      default:           return const Color(0xFF22C55E);
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    final hPad = narrow ? 16.0 : 24.0;

    return Padding(
      padding: EdgeInsets.all(hPad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Add user button ──────────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('All Users (${users.length})',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _mgmtColor)),
          ElevatedButton.icon(
            onPressed: () => _showUserDialog(context, null),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Create User'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _mgmtColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
        ]),
        const SizedBox(height: 16),

        // ── Empty state ──────────────────────────────────────────────────
        if (users.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.group_off_rounded, size: 56, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text('No users added yet',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                Text('Click "Create User" to add the first user.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
              ]),
            ),
          ),

        // ── User cards ───────────────────────────────────────────────────
        ...users.map((u) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _roleColor(u.role).withValues(alpha: 0.15),
                child: Text(
                  u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                  style: TextStyle(
                      color: _roleColor(u.role),
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(u.name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    if (!u.active)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text('Inactive',
                            style: TextStyle(fontSize: 10, color: Colors.red.shade600)),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(u.email,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                  const SizedBox(height: 4),
                  Row(children: [
                    if (u.designation.isNotEmpty) ...[
                      _Chip(label: u.designation, color: const Color(0xFF6B7280)),
                      const SizedBox(width: 6),
                    ],
                    _Chip(label: u.role, color: _roleColor(u.role)),
                  ]),
                  if (['Employee', 'Manager', 'HR'].contains(u.role) && u.reportingManager.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      const Icon(Icons.manage_accounts_rounded, size: 11, color: Color(0xFF6B7280)),
                      const SizedBox(width: 4),
                      Text('Reports to: ${u.reportingManager}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                    ]),
                  ],
                ]),
              ),
              const SizedBox(width: 8),
              // Action buttons
              Column(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Edit User',
                  onPressed: () => _showUserDialog(context, u),
                  icon: Icon(Icons.edit_rounded, size: 18, color: _mgmtColor),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: u.active ? 'Deactivate User' : 'Activate User',
                  onPressed: () async {
                    // Activating a brand-new account (never logged in, no
                    // password set yet) sends the secure Set Password link
                    // instead of just flipping active on — same flow as
                    // Employee Onboarding's Management approval (see
                    // EmailService.sendEmployeeActivation). Re-activating an
                    // existing employee who already has a password is just
                    // a plain toggle, no email needed.
                    if (!u.active && !u.hasPassword) {
                      final personalEmail = await SupabaseService.fetchCandidatePersonalEmail(
                        name: u.name,
                        mobile: u.mobile,
                      );
                      final error = await EmailService.sendEmployeeActivation(u, personalEmail: personalEmail);
                      if (context.mounted && error != null) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Failed to send activation email: $error'),
                          backgroundColor: Colors.red.shade700,
                        ));
                        return;
                      }
                      u.active = false; // stays locked until the token is used
                    } else {
                      u.active = !u.active;
                    }
                    onUpsert(u);
                  },
                  icon: Icon(
                    u.active ? Icons.person_off_rounded : Icons.person_rounded,
                    size: 18,
                    color: u.active ? Colors.red.shade400 : Colors.green.shade600,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                if (!u.active && !u.hasPassword)
                  IconButton(
                    tooltip: 'Resend Activation Email',
                    onPressed: () async {
                      final personalEmail = await SupabaseService.fetchCandidatePersonalEmail(
                        name: u.name,
                        mobile: u.mobile,
                      );
                      final error = await EmailService.sendEmployeeActivation(u, personalEmail: personalEmail);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(error == null
                              ? 'Activation email resent to ${personalEmail ?? u.email}'
                              : 'Failed to resend: $error'),
                          backgroundColor: error == null ? Colors.green.shade700 : Colors.red.shade700,
                        ));
                      }
                    },
                    icon: Icon(Icons.forward_to_inbox_rounded, size: 18, color: _mgmtColor),
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  tooltip: 'Delete User',
                  onPressed: () => _confirmDelete(context, u, onDelete),
                  icon: const Icon(Icons.delete_rounded, size: 18, color: Color(0xFFB91C1C)),
                  visualDensity: VisualDensity.compact,
                ),
              ]),
            ]),
          ),
        )),
      ]),
    );
  }

  static const _domain = '@fomrahousing.in';
  static const _mobileLoginDomain = '@login.fomrahousing.internal';

  // Strip domain to get just the username prefix for editing
  static String _emailPrefix(String? email) {
    if (email == null) return '';
    return email.endsWith(_domain)
        ? email.substring(0, email.length - _domain.length)
        : email;
  }

  void _showUserDialog(BuildContext context, AppUser? existing) {
    final nameCtrl  = TextEditingController(text: existing?.name ?? '');
    final emailCtrl = TextEditingController(text: _emailPrefix(existing?.email));
    final mobileCtrl = TextEditingController(text: existing?.mobile ?? '');
    final empIdCtrl = TextEditingController(text: existing?.employeeId ?? '');
    final desigCtrl = TextEditingController(text: existing?.designation ?? '');
    String selectedRole = existing?.role ?? 'Employee';
    String selectedManager = existing?.reportingManager ?? '';
    // Staff without a real email — housekeeping, support — log in with just
    // their mobile number and a password. The `email` column still needs
    // SOME value (it's the primary key, and Supabase Auth session minting
    // needs an email-shaped string), so a synthetic, never-shown address is
    // generated from the mobile number instead; the person never sees it.
    bool mobileOnlyLogin = existing != null && existing.email.endsWith(_mobileLoginDomain);
    final roleNames = ['Employee', 'Manager', 'HR', 'Management'];
    // This dialog is Management-only (route-gated) and Management is the
    // ultimate RM-change approver, so edits here save directly with no
    // pending-approval step, unlike the HR-facing edit dialog.
    final managerNames = visibleManagersForPicker(users).map((u) => u.name).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            existing == null ? 'Create User' : 'Edit User',
            style: TextStyle(color: _mgmtColor, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _DialogField(controller: nameCtrl, label: 'Full Name', icon: Icons.person_rounded),
              const SizedBox(height: 12),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: mobileOnlyLogin,
                title: const Text('Mobile-only login (no email)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: const Text('For housekeeping / support staff — they sign in with mobile number + password.',
                    style: TextStyle(fontSize: 11)),
                onChanged: (v) => setS(() => mobileOnlyLogin = v ?? false),
              ),
              const SizedBox(height: 8),
              if (mobileOnlyLogin)
                _DialogField(controller: mobileCtrl, label: 'Mobile Number (used to log in)',
                    icon: Icons.phone_android_rounded, keyboardType: TextInputType.phone)
              else ...[
                // Email with fixed @fomrahousing.in domain
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.email_rounded, color: _mgmtColor, size: 20),
                    suffix: Text('@fomrahousing.in',
                        style: TextStyle(color: _mgmtColor, fontWeight: FontWeight.w600, fontSize: 13)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _mgmtColor, width: 2),
                    ),
                    filled: true, fillColor: Colors.white,
                    labelStyle: const TextStyle(color: Color(0xFF6B7280)),
                  ),
                ),
                const SizedBox(height: 12),
                _DialogField(controller: mobileCtrl, label: 'Mobile Number (optional)',
                    icon: Icons.phone_android_rounded, keyboardType: TextInputType.phone),
              ],
              const SizedBox(height: 12),
              _DialogField(controller: empIdCtrl, label: 'Employee ID (e.g. EMP001)', icon: Icons.badge_rounded),
              const SizedBox(height: 12),
              _DialogField(controller: desigCtrl, label: 'Designation', icon: Icons.work_rounded),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.shield_rounded, color: _mgmtColor, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _mgmtColor, width: 2),
                  ),
                  filled: true, fillColor: Colors.white,
                ),
                items: roleNames.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) { if (v != null) setS(() => selectedRole = v); },
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _mgmtLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: _mgmtColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _roleDashboardNote(selectedRole),
                      style: TextStyle(fontSize: 11, color: _mgmtColor),
                    ),
                  ),
                ]),
              ),
              if (['Employee', 'Manager', 'HR'].contains(selectedRole) && managerNames.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: managerNames.contains(selectedManager) ? selectedManager : null,
                  decoration: InputDecoration(
                    labelText: 'Reporting Manager',
                    prefixIcon: Icon(Icons.manage_accounts_rounded, color: _mgmtColor, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _mgmtColor, width: 2),
                    ),
                    filled: true, fillColor: Colors.white,
                  ),
                  hint: const Text('None assigned'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('None')),
                    ...managerNames.map((m) => DropdownMenuItem(value: m, child: Text(m))),
                  ],
                  onChanged: (v) => setS(() => selectedManager = v ?? ''),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            ElevatedButton(
              onPressed: () {
                final prefix = emailCtrl.text.trim();
                final mobile = mobileCtrl.text.trim();
                if (nameCtrl.text.trim().isEmpty) return;
                if (mobileOnlyLogin && mobile.isEmpty) return;
                if (!mobileOnlyLogin && prefix.isEmpty) return;
                final fullEmail = mobileOnlyLogin ? '$mobile$_mobileLoginDomain' : '$prefix$_domain';
                final AppUser target;
                final now = DateTime.now();
                final todayStr =
                    '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

                if (existing == null) {
                  target = AppUser(
                    name:             nameCtrl.text.trim(),
                    email:            fullEmail,
                    mobile:           mobile,
                    employeeId:       empIdCtrl.text.trim(),
                    designation:      desigCtrl.text.trim(),
                    role:             selectedRole,
                    reportingManager: ['Employee', 'Manager', 'HR'].contains(selectedRole) ? selectedManager : '',
                    // The date the ACCOUNT is created is not the date the
                    // employee joined. Nirmal joined 01/04/2026 and his
                    // account was made on 29/07/2026, so the system recorded
                    // 14 days of service instead of four months — which feeds
                    // probation, confirmation and earned leave.
                    //
                    // Left blank rather than stamped with today: an empty date
                    // is visibly missing and gets filled in, whereas a
                    // plausible wrong one is never questioned. HR sets it on
                    // the employee record, or it arrives from the onboarding
                    // form's Date of Joining.
                    dateOfJoining:    '',
                  );
                  users.add(target);
                } else {
                  existing.name             = nameCtrl.text.trim();
                  existing.email            = fullEmail;
                  existing.mobile           = mobile;
                  existing.employeeId       = empIdCtrl.text.trim();
                  existing.designation      = desigCtrl.text.trim();
                  existing.role             = selectedRole;
                  existing.reportingManager = ['Employee', 'Manager', 'HR'].contains(selectedRole) ? selectedManager : '';
                  if (existing.dateOfJoining.isEmpty) existing.dateOfJoining = todayStr;
                  target = existing;
                }
                onUpsert(target);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _mgmtColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(existing == null ? 'Create' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppUser u, Future<void> Function(AppUser) onDelete) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User',
            style: TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.bold)),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            children: [
              const TextSpan(text: 'Are you sure you want to permanently delete '),
              TextSpan(
                text: u.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const TextSpan(text: '? This action cannot be undone.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete(u);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _roleDashboardNote(String role) {
    switch (role) {
      case 'Employee':   return 'This user will access the Employee Dashboard.';
      case 'Manager':    return 'This user will access the Manager Dashboard.';
      case 'HR':         return 'This user will access the HR Admin Dashboard.';
      case 'Management': return 'This user will access the Management Dashboard with full access.';
      default:           return '';
    }
  }
}

// ── Onboarding tab ────────────────────────────────────────────────────────────

class _OnboardingTab extends StatefulWidget {
  const _OnboardingTab();

  @override
  State<_OnboardingTab> createState() => _OnboardingTabState();
}

class _OnboardingTabState extends State<_OnboardingTab> {
  List<Map<String, dynamic>> _forms = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await Supabase.instance.client
          .from('onboarding_forms')
          .select()
          .inFilter('status', ['hr_approved', 'mgmt_approved', 'mgmt_denied', 'access_granted'])
          .order('submitted_at', ascending: false);
      setState(() { _forms = List<Map<String, dynamic>>.from(data); _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // Reports failures via SnackBar rather than the page-level `_error` —
  // that field drives the full-page "Could not load submissions" view, and
  // a failed status update on an already-loaded list isn't a load failure;
  // hijacking the whole screen for it hid the (already-loaded) list behind
  // a misleading "run the SQL to add the status column" message.
  Future<void> _updateStatus(BuildContext context, String id, String status) async {
    try {
      await Supabase.instance.client
          .from('onboarding_forms')
          .update({'status': status})
          .eq('id', id);
      await _load();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  Future<void> _resendActivation(BuildContext context, Map<String, dynamic> form) async {
    final email = (form['assigned_email'] as String?) ?? '';
    if (email.isEmpty) return;
    final user = AppUser(
      name:        (form['name']            as String?) ?? '',
      email:       email,
      employeeId:  (form['assigned_emp_id'] as String?) ?? '',
      designation: (form['designation']     as String?) ?? '',
      role:        'Employee',
    );
    final personalEmail = await SupabaseService.fetchCandidatePersonalEmail(
      candidateApplicationId: form['candidate_application_id'] as String?,
      name: (form['name'] as String?) ?? '',
      mobile: (form['phone_number'] as String?) ?? '',
    );
    final error = await EmailService.sendEmployeeActivation(user, personalEmail: personalEmail);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error == null ? 'Activation email resent to $email' : 'Failed to resend: $error'),
        backgroundColor: error == null ? Colors.green.shade700 : Colors.red.shade700,
      ));
    }
  }

  Future<void> _approve(BuildContext context, Map<String, dynamic> form) async {
    final email   = (form['assigned_email']   as String?) ?? '';
    final empId   = (form['assigned_emp_id']  as String?) ?? '';
    final manager = (form['assigned_manager'] as String?) ?? '';
    final role    = (form['assigned_role']    as String?)?.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No email assigned. Ask HR to re-forward this submission.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    try {
      // Only name/phone_number/designation are ever written top-level at
      // submit time (see onboarding_form_page.dart) — everything else the
      // candidate filled in (DOB, address, ...) lives inside 'form_data'.
      // Reading straight off `form` for those silently returned '' before this.
      final fd = form['form_data'];
      final formData = fd is Map ? Map<String, dynamic>.from(fd) : <String, dynamic>{};
      final user = AppUser(
        name:             (form['name']          as String?) ?? '',
        email:            email,
        employeeId:       empId,
        designation:      (form['assigned_designation'] as String?) ?? (form['designation'] as String?) ?? '',
        department:       (form['assigned_department']  as String?) ?? '',
        role:             (role != null && role.isNotEmpty) ? role : 'Employee',
        active:           true,
        reportingManager: manager,
        // Left blank here deliberately — this only fires when the account is
        // *created* and the activation email goes out, which can be days
        // before the employee actually gets in. The real "date of joining"
        // is stamped in SupabaseService.completeAccountActivation() at the
        // moment they actually set their password and gain access.
        dateOfBirth:      (formData['date_of_birth'] as String?) ?? '',
        mobile:           (form['phone_number'] as String?) ?? '',
        address:          ((formData['permanent_address'] as String?)?.isNotEmpty ?? false)
                              ? formData['permanent_address'] as String
                              : (formData['postal_address'] as String?) ?? '',
      );
      await UserStore.upsertOne(user);
      await Supabase.instance.client
          .from('onboarding_forms')
          .update({'status': 'access_granted'})
          .eq('id', form['id'].toString());
      final personalEmail = await SupabaseService.fetchCandidatePersonalEmail(
        candidateApplicationId: form['candidate_application_id'] as String?,
        name: (form['name'] as String?) ?? '',
        mobile: (form['phone_number'] as String?) ?? '',
      );
      final emailError = await EmailService.sendEmployeeActivation(user, personalEmail: personalEmail);
      await _load();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(emailError == null
              ? 'Account created for ${user.name} (${user.email}) — activation email sent'
              : 'Account created for ${user.name}, but activation email failed: $emailError'),
          backgroundColor: emailError == null ? Colors.green.shade700 : Colors.orange.shade700,
          duration: Duration(seconds: emailError == null ? 4 : 8),
        ));
      }
    } catch (e) {
      // Reported via SnackBar only — setting the page-level `_error` here
      // used to flip the whole tab over to the full-page "Could not load
      // submissions" view even though the list itself loaded fine; a failed
      // approve action isn't a load failure.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 8),
        ));
      }
    }
  }

  Future<void> _editAssigned(BuildContext context, Map<String, dynamic> form) async {
    final emailCtrl   = TextEditingController(text: (form['assigned_email']   as String? ?? '').replaceAll('@fomrahousing.in', ''));
    final empIdCtrl   = TextEditingController(text: form['assigned_emp_id']   as String? ?? '');
    final managerCtrl = TextEditingController(text: form['assigned_manager']  as String? ?? '');
    const roleOptions = ['Employee', 'Manager', 'HR'];
    final existingRole = (form['assigned_role'] as String?)?.trim() ?? '';
    String selectedRole = roleOptions.contains(existingRole) ? existingRole : 'Employee';
    final existingDept = (form['assigned_department'] as String?)?.trim() ?? '';
    final existingDesig = (form['assigned_designation'] as String?)?.trim() ?? '';
    String? selectedDepartment = kDepartments.contains(existingDept) ? existingDept : null;
    String? selectedDesignation = kDesignations.contains(existingDesig) ? existingDesig : null;

    // Load managers list for dropdown
    List<String> managers = [];
    try {
      final users = await UserStore.load();
      managers = visibleManagersForPicker(users).map((u) => u.name).toList();
    } catch (_) {}
    String selectedManager = managerCtrl.text.isNotEmpty ? managerCtrl.text : (managers.isNotEmpty ? managers.first : '');

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Edit Account Details', style: TextStyle(color: _mgmtColor, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: emailCtrl,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.email_rounded, color: _mgmtColor, size: 20),
                  suffix: Text('@fomrahousing.in',
                      style: TextStyle(color: _mgmtColor, fontWeight: FontWeight.w600, fontSize: 13)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true, fillColor: Colors.white,
                  labelStyle: const TextStyle(color: Color(0xFF6B7280)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: empIdCtrl,
                decoration: InputDecoration(
                  labelText: 'Employee ID',
                  prefixIcon: Icon(Icons.badge_rounded, color: _mgmtColor, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true, fillColor: Colors.white,
                  labelStyle: const TextStyle(color: Color(0xFF6B7280)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedDepartment,
                hint: const Text('Select department'),
                decoration: InputDecoration(
                  labelText: 'Department',
                  prefixIcon: Icon(Icons.account_tree_rounded, color: _mgmtColor, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true, fillColor: Colors.white,
                ),
                items: kDepartments.map((dep) => DropdownMenuItem(value: dep, child: Text(dep))).toList(),
                onChanged: (v) => setS(() => selectedDepartment = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedDesignation,
                hint: const Text('Select designation'),
                decoration: InputDecoration(
                  labelText: 'Designation',
                  prefixIcon: Icon(Icons.work_rounded, color: _mgmtColor, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true, fillColor: Colors.white,
                ),
                items: kDesignations.map((des) => DropdownMenuItem(value: des, child: Text(des))).toList(),
                onChanged: (v) => setS(() => selectedDesignation = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: InputDecoration(
                  labelText: 'User Type',
                  prefixIcon: Icon(Icons.badge_outlined, color: _mgmtColor, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true, fillColor: Colors.white,
                ),
                items: roleOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => setS(() => selectedRole = v ?? 'Employee'),
              ),
              const SizedBox(height: 12),
              if (managers.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: managers.contains(selectedManager) ? selectedManager : null,
                  decoration: InputDecoration(
                    labelText: 'Reporting Manager',
                    prefixIcon: Icon(Icons.manage_accounts_rounded, color: _mgmtColor, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true, fillColor: Colors.white,
                  ),
                  items: managers.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => setS(() => selectedManager = v ?? ''),
                )
              else
                TextField(
                  controller: managerCtrl,
                  decoration: InputDecoration(
                    labelText: 'Reporting Manager',
                    prefixIcon: Icon(Icons.manage_accounts_rounded, color: _mgmtColor, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true, fillColor: Colors.white,
                    labelStyle: const TextStyle(color: Color(0xFF6B7280)),
                  ),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _mgmtColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final newEmail   = '${emailCtrl.text.trim()}@fomrahousing.in';
                final newEmpId   = empIdCtrl.text.trim();
                final newManager = managers.isNotEmpty ? selectedManager : managerCtrl.text.trim();
                Navigator.pop(ctx);
                try {
                  await Supabase.instance.client
                      .from('onboarding_forms')
                      .update({
                        'assigned_email':       newEmail,
                        'assigned_emp_id':      newEmpId,
                        'assigned_manager':     newManager,
                        'assigned_role':        selectedRole,
                        'assigned_department':  selectedDepartment ?? '',
                        'assigned_designation': selectedDesignation ?? '',
                      })
                      .eq('id', form['id'].toString());
                  await _load();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Save failed: $e'),
                      backgroundColor: Colors.red.shade700,
                    ));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewDetails(BuildContext context, Map<String, dynamic> form) async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _mgmtColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(children: [
                Expanded(child: Text(
                  form['name'] ?? 'Onboarding Details',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                )),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildDetails(form),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // Only name/phone_number/designation are ever written top-level at submit
  // time (see onboarding_form_page.dart) — everything else the candidate
  // filled in (family, education, emergency contact, attachments, ...)
  // lives inside 'form_data'. Reading straight off the row silently showed
  // near-empty sections before this.
  Widget _buildDetails(Map<String, dynamic> d) {
    final fd = d['form_data'];
    final formData = fd is Map ? Map<String, dynamic>.from(fd) : <String, dynamic>{};
    return OnboardingFormReadOnlyBody(data: {...d, ...formData});
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    if (_loading) return Center(child: CircularProgressIndicator(color: _mgmtColor));
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
        const SizedBox(height: 12),
        const Text('Could not load submissions.', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('Make sure you ran the SQL to add the status column\n(see Supabase setup guide).',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(backgroundColor: _mgmtColor, foregroundColor: Colors.white),
        ),
      ]));
    }
    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(narrow ? 16 : 24, narrow ? 12 : 16, narrow ? 16 : 24, 0),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('HR Forwarded (${_forms.length})',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _mgmtColor)),
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh_rounded, color: _mgmtColor),
            onPressed: _load,
          ),
        ]),
      ),
      if (_forms.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.how_to_reg_rounded, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No HR-forwarded submissions yet', style: TextStyle(color: Colors.grey.shade500)),
          ])),
        )
      else
        Padding(
                padding: EdgeInsets.all(narrow ? 16 : 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (int i = 0; i < _forms.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _buildFormCard(context, _forms[i]),
                  ],
                ]),
        ),
    ]);
  }

  Widget _buildFormCard(BuildContext context, Map<String, dynamic> f) {
                  final status = (f['status'] as String?) ?? '';
                  final id = f['id'].toString();
                  Color statusColor;
                  String statusLabel;
                  if (status == 'mgmt_approved') { statusColor = const Color(0xFF22C55E); statusLabel = 'Approved'; }
                  else if (status == 'mgmt_denied') { statusColor = const Color(0xFFB91C1C); statusLabel = 'Denied'; }
                  else if (status == 'access_granted') { statusColor = const Color(0xFF2563EB); statusLabel = 'Active'; }
                  else { statusColor = const Color(0xFF3B82F6); statusLabel = 'Awaiting Review'; }

                  return Card(
                    elevation: 0,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: statusColor.withValues(alpha: 0.3))),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: _mgmtColor.withValues(alpha: 0.12),
                            child: Text(
                              ((f['name'] as String?) ?? '?')[0].toUpperCase(),
                              style: TextStyle(color: _mgmtColor, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text((f['name'] as String?) ?? '—',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF111827))),
                            Text('${f['designation'] ?? ''}  ·  ${f['phone_number'] ?? ''}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(statusLabel,
                                style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                        // Show pre-assigned account details (set by HR) — editable by Management
                        if ((f['assigned_email'] as String? ?? '').isNotEmpty ||
                            status == 'hr_approved') ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                            decoration: BoxDecoration(
                              color: AppTheme.lightBlue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Account details (set by HR):',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _mgmtColor)),
                                const SizedBox(height: 5),
                                _DetailRow(Icons.email_rounded,           'Email',    f['assigned_email']   as String? ?? '—'),
                                _DetailRow(Icons.badge_rounded,           'Emp ID',   f['assigned_emp_id']  as String? ?? '—'),
                                _DetailRow(Icons.badge_outlined,          'User Type',
                                    (f['assigned_role'] as String?)?.trim().isNotEmpty == true ? f['assigned_role'] as String : 'Employee'),
                                _DetailRow(Icons.manage_accounts_rounded, 'Manager',  f['assigned_manager'] as String? ?? '—'),
                              ])),
                              if (status == 'hr_approved')
                                IconButton(
                                  tooltip: 'Edit details',
                                  icon: Icon(Icons.edit_rounded, size: 16, color: _mgmtColor),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _editAssigned(context, f),
                                ),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.visibility_rounded, size: 15),
                            label: const Text('View Details', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _mgmtColor,
                              side: BorderSide(color: _mgmtColor),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => _viewDetails(context, f),
                          ),
                          if (status == 'hr_approved') ...[
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.close_rounded, size: 15),
                              label: const Text('Deny', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => _updateStatus(context, id, 'mgmt_denied'),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.check_rounded, size: 15),
                              label: const Text('Approve', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _mgmtColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => _approve(context, f),
                            ),
                          ],
                          if (status == 'access_granted') ...[
                            const SizedBox(width: 10),
                            const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF2563EB)),
                            const SizedBox(width: 4),
                            const Text('Account active', style: TextStyle(fontSize: 12, color: Color(0xFF2563EB))),
                            const SizedBox(width: 10),
                            TextButton.icon(
                              onPressed: () => _resendActivation(context, f),
                              icon: const Icon(Icons.forward_to_inbox_rounded, size: 14),
                              label: const Text('Resend Activation Email', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                foregroundColor: _mgmtColor,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ]),
                      ]),
                    ),
                  );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        Icon(icon, size: 12, color: _mgmtColor),
        const SizedBox(width: 5),
        Text('$label: ', style: TextStyle(fontSize: 11, color: _mgmtColor, fontWeight: FontWeight.w600)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 11, color: Color(0xFF111827)))),
      ]),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _DialogField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  const _DialogField({
    required this.controller,
    required this.label,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _mgmtColor, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _mgmtColor, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: Color(0xFF6B7280)),
      ),
    );
  }
}
