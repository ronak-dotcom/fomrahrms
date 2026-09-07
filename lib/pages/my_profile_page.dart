import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import '../models/candidate_store.dart';
import '../models/payslip_store.dart';
import '../models/user_session.dart';
import '../services/notification_service.dart';
import '../services/payslip_pdf_service.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../utils/tenure.dart';
import '../widgets/attendance_shortcut_card.dart' show showHelpCenterDialog;
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  static Color get _color => AppTheme.accentBlue;
  AppUser? _user;
  Payslip? _latestPayslip;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  bool _downloadingPayslip = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFE53935) : null,
    ));
  }

  Future<void> _editPhoto() async {
    final empId = UserSession.employeeId;
    if (empId.isEmpty) {
      _showMessage('No employee ID on this account — cannot upload a photo.', error: true);
      return;
    }
    if (_uploadingPhoto) return;

    XFile? picked;
    try {
      picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    } catch (e) {
      _showMessage('Could not open the photo picker: $e', error: true);
      return;
    }
    if (picked == null) return; // user cancelled the picker

    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await SupabaseService.updateCurrentUserPhoto(
          empId, bytes, picked.name, picked.mimeType ?? '');
      if (url != null) {
        if (mounted) setState(() => UserSession.photoUrl = url);
        _showMessage('Profile photo updated.');
      } else {
        _showMessage('Upload failed — please try again.', error: true);
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _load() async {
    final results = await Future.wait([
      UserStore.load(),
      SupabaseService.fetchPayslips(UserSession.employeeId),
    ]);
    final users = results[0] as List<AppUser>;
    final payslips = results[1] as List<Payslip>;
    final match = users.where((u) => u.name == UserSession.name).toList();
    if (mounted) {
      setState(() {
        _user = match.isNotEmpty ? match.first : null;
        _latestPayslip = payslips.isNotEmpty ? payslips.first : null;
        _loading = false;
      });
    }
  }

  Future<void> _downloadPayslip() async {
    final p = _latestPayslip;
    if (p == null || _downloadingPayslip) return;
    setState(() => _downloadingPayslip = true);
    try {
      await PayslipPdfService.download(p);
    } catch (e) {
      _showMessage('Could not generate payslip PDF: $e', error: true);
    } finally {
      if (mounted) setState(() => _downloadingPayslip = false);
    }
  }

  Future<void> _requestOnRoll() async {
    final user = _user;
    if (user == null) return;
    setState(() => _saving = true);
    user.onrollRequestedAt = DateTime.now().toIso8601String();
    await UserStore.upsertOne(user);

    // Verified rather than assumed. One employee raised this and the request
    // date came back blank afterwards, so nobody was ever notified and she
    // believed it had been sent. Reading the row back is the only way to know
    // the write actually landed.
    final saved = await SupabaseService.userByName(UserSession.name);
    final ok = saved != null;
    if (!mounted) return;
    setState(() => _saving = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(
            'Could not send the request. Please try again, or ask HR to raise '
            'it for you.'),
        backgroundColor: Colors.red.shade700,
      ));
      return;
    }

    NotificationService.onrollRequested(
      employeeName: UserSession.name,
      reportingManagerName: UserSession.reportingManager,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Confirmation request sent to your manager and HR.'),
      ));
    }
  }

  /// Resubmits after a denial: resets all 3 review stages back to pending.
  Future<void> _resubmitOnRoll() async {
    final user = _user;
    if (user == null) return;
    setState(() => _saving = true);
    user.onrollRequestedAt = DateTime.now().toIso8601String();
    user.onrollHrStatus = 'pending';
    user.onrollHrComment = '';
    user.onrollHrDecidedAt = '';
    user.onrollManagerStatus = 'pending';
    user.onrollManagerComment = '';
    user.onrollManagerDecidedAt = '';
    user.onrollManagementStatus = 'pending';
    user.onrollManagementComment = '';
    user.onrollManagementDecidedAt = '';
    await UserStore.upsertOne(user);
    NotificationService.onrollRequested(
      employeeName: UserSession.name,
      reportingManagerName: UserSession.reportingManager,
    );
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _openMyInterviewForm(BuildContext context) async {
    try {
      final db    = Supabase.instance.client;
      final email = UserSession.email.trim();
      final name  = UserSession.name.trim();

      List<dynamic> rows = [];
      if (email.isNotEmpty) {
        rows = await db
            .from('candidate_applications')
            .select()
            .eq('email', email)
            .order('submitted_at', ascending: false)
            .limit(1);
      }
      if (rows.isEmpty && name.isNotEmpty) {
        rows = await db
            .from('candidate_applications')
            .select()
            .ilike('name', '%$name%')
            .order('submitted_at', ascending: false)
            .limit(1);
      }

      if (rows.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No interview application found for your account.'),
            backgroundColor: Colors.orange,
          ));
        }
        return;
      }

      CandidateStore.selected = Map<String, dynamic>.from(rows.first as Map);
      if (context.mounted) context.go('${_rolePrefix()}/interview-form');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not load your interview application: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // dateOfJoining/dateOfBirth are stored as either ISO or dd/MM/yyyy (see
  // tenure.dart's parseFlexibleDate) — normalize to dd/MM/yyyy for display,
  // falling back to the raw value if it doesn't parse rather than hiding it.
  String _fmtDate(String value) {
    if (value.isEmpty) return '';
    final d = parseFlexibleDate(value);
    if (d == null) return value;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _grossPayLabel(AppUser? user) {
    if (user == null || user.grossPay <= 0) return 'Not set';
    final base = '₹${user.grossPay.toStringAsFixed(0)}/month';
    if (user.hasPendingGrossPayChange) {
      return '$base (change to ₹${user.grossPayPending.toStringAsFixed(0)} pending approval)';
    }
    return base;
  }

  String _resubmitDate(String deniedAtIso) {
    try {
      final d = DateTime.parse(deniedAtIso).add(const Duration(days: 7));
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildOnRollCard(AppUser user) {
    final months = fullMonthsSince(user.dateOfJoining);

    final Color bg, fg;
    final IconData icon;
    final String text;
    Widget? action;

    if (months < 6) {
      bg = Colors.grey.shade100;
      fg = Colors.grey.shade700;
      icon = Icons.hourglass_top_rounded;
      final left = 6 - months;
      text = 'You can request On-Roll confirmation after completing 6 months '
          '($left ${left == 1 ? 'month' : 'months'} to go).';
    } else {
      switch (user.onrollStage) {
        case 'not_requested':
          bg = Colors.green.shade50;
          fg = const Color(0xFF15803D);
          icon = Icons.verified_rounded;
          text = "You've completed 6 months and are eligible for On-Roll confirmation.";
          action = SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _requestOnRoll,
              icon: _saving
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 16),
              label: const Text('Request On-Roll Confirmation'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
            ),
          );
          break;
        case 'pending_both':
          bg = Colors.orange.shade50;
          fg = const Color(0xFF7B4F00);
          icon = Icons.pending_actions_rounded;
          text = 'On-Roll confirmation requested — awaiting review from HR '
              'and your Reporting Manager.';
          break;
        case 'pending_manager':
          bg = Colors.orange.shade50;
          fg = const Color(0xFF7B4F00);
          icon = Icons.pending_actions_rounded;
          text = 'HR has accepted your On-Roll request — awaiting review from '
              'your Reporting Manager.';
          break;
        case 'pending_hr':
          bg = Colors.orange.shade50;
          fg = const Color(0xFF7B4F00);
          icon = Icons.pending_actions_rounded;
          text = 'Your Reporting Manager has accepted your On-Roll request — '
              'awaiting review from HR.';
          break;
        case 'awaiting_management':
          bg = Colors.blue.shade50;
          fg = const Color(0xFF1D4ED8);
          icon = Icons.hourglass_top_rounded;
          text = 'HR and your Reporting Manager have approved your On-Roll '
              'request — awaiting final approval from Management.';
          break;
        case 'denied':
          bg = Colors.red.shade50;
          fg = const Color(0xFFB91C1C);
          icon = Icons.cancel_rounded;
          final comment = user.onrollDeniedComment;
          final base = 'Your On-Roll request was denied by ${user.onrollDeniedBy}'
              '${comment.isNotEmpty ? ': "$comment"' : '.'}';
          if (user.onrollCanResubmit) {
            text = base;
            action = SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _resubmitOnRoll,
                icon: _saving
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 16),
                label: const Text('Request Again'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
              ),
            );
          } else {
            text = '$base You can request again on ${_resubmitDate(user.onrollDeniedAt)}.';
          }
          break;
        case 'confirmed':
        default:
          bg = Colors.green.shade50;
          fg = const Color(0xFF15803D);
          icon = Icons.verified_rounded;
          text = 'On-Roll confirmed — you now receive 1 Casual Leave + '
              '1 Medical Leave every month.';
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
          ),
        ]),
        if (action != null) ...[
          const SizedBox(height: 12),
          action,
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: null,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Header
                Row(children: [
                  const NavBackButton(),
                  const SizedBox(width: 8),
                  Icon(Icons.person_rounded, color: _color, size: 22),
                  const SizedBox(width: 10),
                  Text('My Profile', style: Theme.of(context).textTheme.headlineMedium),
                ]),
                const SizedBox(height: 16),

                // Info banner — HR-managed notice + Contact HR shortcut
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.08),
                    border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.warning,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.info_rounded, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Your profile is managed by HR. Contact HR to update any details.',
                          style: TextStyle(
                              color: AppTheme.warning.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () => showHelpCenterDialog(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.warning,
                        side: BorderSide(color: AppTheme.warning.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Contact HR', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 12),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),

                // Avatar + name + quick-stat strip
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final avatarBlock = Row(children: [
                        Stack(clipBehavior: Clip.none, children: [
                          ValueListenableBuilder<String>(
                            valueListenable: UserSession.photoUrlNotifier,
                            builder: (context, photoUrl, _) => CircleAvatar(
                              radius: 32,
                              backgroundColor: const Color(0xFF111827),
                              backgroundImage: photoUrl.isNotEmpty
                                  ? NetworkImage(photoUrl)
                                  : null,
                              child: _uploadingPhoto
                                  ? const SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : (photoUrl.isNotEmpty
                                      ? null
                                      : Text(
                                          (_user?.name.isNotEmpty == true)
                                              ? _user!.name[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                                        )),
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: GestureDetector(
                              onTap: _editPhoto,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: _color,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt_rounded,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(width: 16),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            _user?.name.isEmpty != false ? 'Employee' : _user!.name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _user?.designation.isEmpty != false ? '—' : _user!.designation,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                          ),
                          if (_user?.role.isNotEmpty == true) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF111827).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(_user!.role,
                                  style: const TextStyle(
                                      color: Color(0xFF111827), fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ]),
                      ]);

                      final statCells = [
                        _MiniStat(Icons.badge_rounded,           'Employee ID',       _user?.employeeId ?? ''),
                        _MiniStat(Icons.apartment_rounded,       'Department',        _user?.department ?? ''),
                        _MiniStat(Icons.manage_accounts_rounded, 'Reporting Manager', _user?.reportingManager ?? ''),
                        _MiniStat(Icons.calendar_today_rounded,  'Date of Joining',   _user?.dateOfJoining ?? ''),
                      ];

                      if (constraints.maxWidth > 800) {
                        return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                          avatarBlock,
                          const SizedBox(width: 28),
                          Container(width: 1, height: 48, color: AppTheme.borderSubtle),
                          const SizedBox(width: 28),
                          Expanded(
                            child: Row(children: [
                              for (final cell in statCells) ...[
                                Expanded(child: cell),
                              ],
                            ]),
                          ),
                        ]);
                      }
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        avatarBlock,
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 20,
                          runSpacing: 16,
                          children: [for (final cell in statCells) SizedBox(width: 160, child: cell)],
                        ),
                      ]);
                    }),
                  ),
                ),
                const SizedBox(height: 16),

                // Details card + payslip summary side-by-side on wide screens
                LayoutBuilder(builder: (context, constraints) {
                  final detailsCard = Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(children: [
                            _Row(Icons.badge_rounded,      'Employee ID', _user?.employeeId ?? ''),
                            _Row(Icons.email_rounded,      'Login ID',    _user?.email ?? ''),
                            _Row(Icons.alternate_email_rounded, 'Company Mail', _user?.companyEmail ?? ''),
                            _Row(Icons.phone_rounded,      'Phone Number', _user?.mobile ?? ''),
                            _Row(Icons.work_rounded,       'Designation', _user?.designation ?? ''),
                            _Row(Icons.apartment_rounded,  'Department',  _user?.department ?? ''),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(children: [
                            _Row(Icons.manage_accounts_rounded,  'Reporting Manager', _user?.reportingManager ?? ''),
                            _Row(Icons.calendar_today_rounded,   'Date of Joining',   _fmtDate(_user?.dateOfJoining ?? '')),
                            _Row(Icons.hourglass_bottom_rounded, 'Time with Company', tenureLabel(_user?.dateOfJoining ?? '')),
                            _Row(Icons.cake_rounded,             'Date of Birth',     _fmtDate(_user?.dateOfBirth ?? '')),
                            _Row(Icons.home_rounded,             'Address',           _user?.address ?? ''),
                            _Row(Icons.currency_rupee_rounded,   'Gross Pay',         _grossPayLabel(_user)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                  final payslipCard = _ProfilePayslipCard(
                    payslip: _latestPayslip,
                    downloading: _downloadingPayslip,
                    onDownload: _downloadPayslip,
                    onViewAll: () => context.push(_payslipsRoute()),
                  );

                  if (constraints.maxWidth > 700) {
                    return IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(flex: 3, child: detailsCard),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: payslipCard),
                      ]),
                    );
                  }
                  return Column(children: [
                    detailsCard,
                    const SizedBox(height: 16),
                    payslipCard,
                  ]);
                }),
                const SizedBox(height: 16),

                // Forms section
                Row(children: [
                  Expanded(
                    child: _FormCard(
                      icon: Icons.assignment_ind_rounded,
                      title: 'Interview Form',
                      subtitle: 'View your interview details and status',
                      color: AppTheme.accentBlue,
                      onTap: () => _openMyInterviewForm(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FormCard(
                      icon: Icons.how_to_reg_rounded,
                      title: 'Onboarding Form',
                      subtitle: 'View your onboarding details and status',
                      color: const Color(0xFF15803D),
                      onTap: () => context.go('${_rolePrefix()}/employee-onboarding'),
                    ),
                  ),
                ]),

                // Employment status / on-roll request
                if (_user != null) ...[
                  const SizedBox(height: 16),
                  _buildOnRollCard(_user!),
                ],
              ]),
            ),
    );
  }
}

String _rolePrefix() {
  switch (UserSession.role) {
    case UserRole.hr:         return '/hr';
    case UserRole.reportingManager: return '/manager';
    default:                  return '/employee';
  }
}

String _payslipsRoute() {
  switch (UserSession.role) {
    case UserRole.hr:               return '/hr/my-payslips';
    case UserRole.reportingManager: return '/manager/my-payslips';
    case UserRole.management:       return '/management/my-payslips';
    default:                        return '/employee/payslips';
  }
}

const _months = ['January', 'February', 'March', 'April', 'May', 'June',
                  'July', 'August', 'September', 'October', 'November', 'December'];

String? _monthLabel(String monthYear) {
  final p = monthYear.split('-');
  if (p.length != 2) return null;
  final m = int.tryParse(p[1]);
  if (m == null || m < 1 || m > 12) return null;
  return '${_months[m - 1]} ${p[0]}';
}

// ── Payslip summary card (profile-page variant with download + illustration) ──
class _ProfilePayslipCard extends StatelessWidget {
  final Payslip? payslip;
  final bool downloading;
  final VoidCallback onDownload;
  final VoidCallback onViewAll;
  const _ProfilePayslipCard({
    required this.payslip,
    required this.downloading,
    required this.onDownload,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final p = payslip;
    final monthLabel = p != null ? _monthLabel(p.monthYear) : null;
    final amountLabel = p != null ? '₹${p.netPay.round()}' : '—';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.receipt_long_rounded, color: AppTheme.warning, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('My Payslips', style: AppTheme.cardHeading)),
            InkWell(
              onTap: onViewAll,
              borderRadius: BorderRadius.circular(6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('View All',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.warning)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 14, color: AppTheme.warning),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.06),
              border: Border.all(color: AppTheme.warning.withValues(alpha: 0.15)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(children: [
              Positioned(
                right: -8, bottom: -8,
                child: Icon(Icons.receipt_long_rounded,
                    size: 84, color: AppTheme.warning.withValues(alpha: 0.10)),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text('Latest Payslip',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppTheme.textSecondary)),
                  ),
                  if (p != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle_rounded, size: 12, color: AppTheme.success),
                        const SizedBox(width: 4),
                        Text('Available',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppTheme.success)),
                      ]),
                    ),
                ]),
                const SizedBox(height: 2),
                Text(monthLabel ?? 'None yet',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const SizedBox(height: 14),
                Text('Amount',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppTheme.textSecondary)),
                const SizedBox(height: 2),
                Text(amountLabel,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.warning)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: p == null || downloading ? null : onDownload,
                      icon: downloading
                          ? const SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Download', style: TextStyle(fontSize: 12.5)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.warning,
                        side: BorderSide(color: AppTheme.warning.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onViewAll,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: AppTheme.borderSubtle),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                        const Text('View Details', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 11),
                      ]),
                    ),
                  ),
                ]),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Compact icon+label+value cell used in the avatar strip ──────────────────
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MiniStat(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFF111827).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF111827), size: 16),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
          const SizedBox(height: 2),
          Text(value.isEmpty ? '—' : value,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
        ]),
      ),
    ]);
  }
}

class _FormCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _FormCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
            ]),
          ),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: color.withValues(alpha: 0.6)),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Row(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF111827).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF111827), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
            const SizedBox(height: 3),
            Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF111827)),
            ),
          ]),
        ),
      ]),
    );
  }
}

