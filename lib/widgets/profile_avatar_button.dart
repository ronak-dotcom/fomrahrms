import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_session.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'change_password_dialog.dart';
import 'logout_action.dart';

/// Circular avatar + name/ID that opens a profile dropdown on tap.
/// Use [large] = true for the welcome banner (bigger avatar, vertical layout).
class ProfileAvatarButton extends StatefulWidget {
  final bool large;
  final double avatarRadius;
  // Radius of the circle in the compact (non-large) top-bar variant.
  final double compactAvatarRadius;
  // When true, renders the compact variant for a light/white background
  // (dark text, tinted-primary avatar) instead of the default white-on-blue.
  final bool light;
  const ProfileAvatarButton({
    super.key,
    this.large = false,
    this.avatarRadius = 52,
    this.compactAvatarRadius = 16,
    this.light = false,
  });

  @override
  State<ProfileAvatarButton> createState() => _ProfileAvatarButtonState();
}

class _ProfileAvatarButtonState extends State<ProfileAvatarButton> {
  final _key = GlobalKey();
  bool _uploadingPhoto = false;

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

  Future<void> _deletePhoto() async {
    final empId = UserSession.employeeId;
    if (empId.isEmpty || UserSession.photoUrl.isEmpty || _uploadingPhoto) return;

    setState(() => _uploadingPhoto = true);
    try {
      final ok = await SupabaseService.deleteCurrentUserPhoto(empId);
      if (ok) {
        if (mounted) setState(() => UserSession.photoUrl = '');
        _showMessage('Profile photo deleted.');
      } else {
        _showMessage('Could not delete photo — please try again.', error: true);
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _openMenu() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos    = box.localToGlobal(Offset.zero);
    final size   = box.size;
    final screen = MediaQuery.of(context).size;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      builder: (_) => Stack(
        children: [
          Positioned(
            top:   pos.dy + size.height + 6,
            right: screen.width - pos.dx - size.width,
            child: _ProfileDropdown(
              onNavigate: (route) {
                Navigator.of(context).pop();
                context.go(route);
              },
              onChangePassword: () {
                Navigator.of(context).pop();
                showChangePasswordDialog(context);
              },
              onSignOut: () {
                Navigator.of(context).pop();
                performLogout(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: UserSession.photoUrlNotifier,
      builder: (context, photoUrl, _) => _buildContent(context, photoUrl),
    );
  }

  Widget _buildContent(BuildContext context, String photoUrl) {
    final name      = UserSession.name;
    final initial   = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    if (widget.large) {
      // ── Banner variant: avatar + camera menu + dropdown chevron ──────
      return GestureDetector(
        key: _key,
        onTap: _openMenu,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            CircleAvatar(
              radius: widget.avatarRadius,
              backgroundColor: Colors.white.withValues(alpha: 0.20),
              backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
              child: _uploadingPhoto
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : (photoUrl.isEmpty
                      ? Text(initial,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: widget.avatarRadius * 0.73))
                      : null),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: PopupMenuButton<String>(
                tooltip: 'Edit photo',
                onSelected: (value) {
                  if (value == 'edit') _editPhoto();
                  if (value == 'delete') _deletePhoto();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.camera_alt_rounded, size: 18),
                      title: Text('Edit Profile Photo', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  if (photoUrl.isNotEmpty)
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFE53935)),
                        title: Text('Delete Photo', style: TextStyle(fontSize: 13, color: Color(0xFFE53935))),
                      ),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      size: 14, color: Colors.white),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.white.withValues(alpha: 0.70), size: 18),
        ]),
      );
    }

    // ── Top-bar variant: icon only ───────────────────────────────────────
    final light = widget.light;
    final avatarBg = light ? AppTheme.primaryBlue.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.20);
    final avatarFg = light ? AppTheme.primaryBlue : Colors.white;

    final r = widget.compactAvatarRadius;
    return GestureDetector(
      key: _key,
      onTap: _openMenu,
      child: CircleAvatar(
        radius: r,
        backgroundColor: avatarBg,
        backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
        child: photoUrl.isEmpty
            ? Text(initial,
                style: TextStyle(
                    color: avatarFg,
                    fontWeight: FontWeight.bold,
                    fontSize: r * 0.875))
            : null,
      ),
    );
  }
}

/// Each role's own pages, for the profile menu. Staff have theirs in the
/// menu and bottom bar already.
List<(IconData, String, String)> get _personalLinks => switch (UserSession.role) {
      UserRole.management => const [
          (Icons.calendar_month_rounded, 'My attendance & leave', '/management/attendance-leaves'),
          (Icons.account_balance_wallet_rounded, 'My leave balance', '/management/leave/balance'),
          (Icons.receipt_long_rounded, 'My payslips', '/management/my-payslips'),
        ],
      UserRole.hr => const [
          (Icons.calendar_month_rounded, 'My attendance & leave', '/hr/attendance-leaves'),
          (Icons.account_balance_wallet_rounded, 'My leave balance', '/leave/balance'),
          (Icons.timer_outlined, 'Apply permission', '/leave/permission'),
          (Icons.swap_horiz_rounded, 'Apply comp off', '/leave/compoff'),
          (Icons.task_alt_rounded, 'My tasks', '/hr/my-tasks'),
          (Icons.receipt_long_rounded, 'My payslips', '/hr/my-payslips'),
          (Icons.fact_check_rounded, 'My appraisal', '/hr/appraisal'),
          (Icons.build_rounded, 'Maintenance requests', '/hr/maintenance-management'),
        ],
      UserRole.reportingManager => const [
          (Icons.calendar_month_rounded, 'My attendance & leave', '/manager/attendance-leaves'),
          (Icons.account_balance_wallet_rounded, 'My leave balance', '/manager/leave/balance'),
          (Icons.timer_outlined, 'Apply permission', '/manager/leave/permission'),
          (Icons.swap_horiz_rounded, 'Apply comp off', '/manager/leave/compoff'),
          (Icons.work_history_rounded, 'Apply on duty (BTL / site)', '/manager/on-duty'),
          (Icons.report_problem_rounded, 'Attendance issue', '/manager/attendance-confirmation'),
          (Icons.receipt_long_rounded, 'My payslips', '/manager/my-payslips'),
          (Icons.fact_check_rounded, 'My appraisal', '/manager/appraisal'),
          (Icons.build_rounded, 'Maintenance requests', '/manager/maintenance-management'),
        ],
      UserRole.employee => const [],
    };

// ── Dropdown card ─────────────────────────────────────────────────────────────
class _ProfileDropdown extends StatelessWidget {
  final void Function(String route) onNavigate;
  final VoidCallback onChangePassword;
  final VoidCallback onSignOut;

  const _ProfileDropdown({
    required this.onNavigate,
    required this.onChangePassword,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: UserSession.photoUrlNotifier,
      builder: (context, photoUrl, _) => _buildContent(context, photoUrl),
    );
  }

  Widget _buildContent(BuildContext context, String photoUrl) {
    final name       = UserSession.name;
    final empId      = UserSession.employeeId;
    final designation= UserSession.designation;
    final manager    = UserSession.reportingManager;
    final initial    = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 260,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Header ───────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryBlueDark,
                  Color.lerp(AppTheme.primaryBlueDark, AppTheme.primaryBlue, 0.55)!,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                borderRadius: BorderRadius.circular(32),
                onTap: () => onNavigate(UserSession.profileRoute),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white24,
                  backgroundImage:
                      photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: photoUrl.isEmpty
                      ? Text(initial,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold))
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name.isEmpty ? 'User' : name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
              if (empId.isNotEmpty)
                Text(
                  empId,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 11),
                ),
            ]),
          ),

          // ── Details ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(children: [
              if (designation.isNotEmpty)
                _InfoRow(Icons.work_outline_rounded, 'Designation', designation),
              if (manager.isNotEmpty)
                _InfoRow(Icons.manage_accounts_rounded, 'Reporting Manager', manager),
            ]),
          ),

          const Divider(height: 1),

          // ── My Profile ───────────────────────────────────────────────
          ListTile(
            dense: true,
            leading: Icon(Icons.person_rounded, size: 18,
                color: AppTheme.primaryBlue),
            title: const Text('My Profile',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            onTap: () => onNavigate(UserSession.profileRoute),
          ),

          const Divider(height: 1),

          // Management's, HR's and managers' own pages live here rather than
          // in the menu, which is kept for running the company (20-21 Nov
          // 2026). Not for oversight accounts, which have no attendance,
          // leave or payslips.
          if (!UserSession.oversightOnly)
            for (final (icon, label, route) in _personalLinks) ...[
              ListTile(
                dense: true,
                leading: Icon(icon, size: 18, color: AppTheme.primaryBlue),
                title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                onTap: () => onNavigate(route),
              ),
              const Divider(height: 1),
            ],

          // ── Change Password ─────────────────────────────────────────────
          ListTile(
            dense: true,
            leading: Icon(Icons.lock_outline_rounded, size: 18,
                color: AppTheme.primaryBlue),
            title: const Text('Change Password',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            onTap: onChangePassword,
          ),

          const Divider(height: 1),

          // ── Sign Out ─────────────────────────────────────────────────
          ListTile(
            dense: true,
            leading: const Icon(Icons.logout_rounded, size: 18,
                color: Color(0xFFE53935)),
            title: const Text('Sign Out',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFE53935))),
            onTap: onSignOut,
          ),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: const Color(0xFF607D8B)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500)),
            Text(value,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF6B7280)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}
