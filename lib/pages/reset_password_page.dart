import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../utils/token_util.dart';
import '../theme/app_theme.dart';

/// Public, unauthenticated page at /reset-password/{token}. Reached from
/// the "Forgot Password" flow on the login page — unlike SetPasswordPage
/// (new account activation), this never touches `active`, since the
/// employee's existing password keeps working until they finish resetting.
class ResetPasswordPage extends StatefulWidget {
  final String token;
  const ResetPasswordPage({super.key, required this.token});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  bool _loading = true;
  bool _saving = false;
  bool _done = false;
  Map<String, dynamic>? _user;
  String? _error;
  final _newPassCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showNewPass = false;
  bool _showConfirmPass = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // True when the server could not be reached at all. This used to show as
  // an invalid link, which sent people back to HR for a new email that
  // failed the same way (Johnsi R, 25 Nov 2026).
  bool _netError = false;

  Future<void> _load() async {
    // Only on a retry: setState is not allowed while initState is running.
    if (_netError) setState(() { _loading = true; _netError = false; });
    try {
      final row = await SupabaseService.fetchAppUserByResetToken(widget.token);
      if (mounted) setState(() { _user = row; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _netError = true; });
    }
  }

  bool get _expired {
    final expiresAt = (_user?['reset_password_token_expires_at'] as String?) ?? '';
    return TokenUtil.isExpired(expiresAt);
  }

  Future<void> _submit() async {
    final u = _user;
    if (u == null) return;
    if (_newPassCtrl.text.isEmpty) {
      setState(() => _error = 'Please enter a password.');
      return;
    }
    if (_newPassCtrl.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (_newPassCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final email = await SupabaseService.completePasswordReset(
        widget.token,
        password: _newPassCtrl.text,
      );
      if (!mounted) return;
      if (email == null) {
        setState(() { _saving = false; _error = 'This link is no longer valid. Please request a new password reset.'; });
        return;
      }
      setState(() { _saving = false; _done = true; });
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _card(_buildBody()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_netError) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        _message(
          icon: Icons.wifi_off_rounded,
          title: 'Could Not Reach the Server',
          body: 'Your link may be fine, but this phone or computer could not connect to the '
              'HRMS server. Please switch between Wi-Fi and mobile data (or try another '
              'network, or open the link in Chrome), then tap Try again.',
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(onPressed: _load, child: const Text('Try again')),
        ),
      ]);
    }
    if (_user == null) {
      return _message(
        icon: Icons.link_off_rounded,
        title: 'Invalid Reset Link',
        body: 'This link is not valid. Please request a new password reset from the login page.',
      );
    }
    if (_expired) {
      return _message(
        icon: Icons.timer_off_rounded,
        title: 'Password Reset Link Expired',
        body: 'This link has expired. Please request a new password reset from the login page.',
      );
    }
    if (_done) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded, size: 48, color: Color(0xFF16A34A)),
        const SizedBox(height: 16),
        const Text('Password Reset Successfully!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
        const SizedBox(height: 8),
        const Text('You can now sign in with your new password.',
            textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => context.go('/login'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Go to Login'),
          ),
        ),
      ]);
    }

    final name = (_user!['name'] as String?) ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.lock_reset_rounded, color: AppTheme.primaryBlue, size: 32),
      const SizedBox(height: 12),
      Text('Reset Your Password',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
      const SizedBox(height: 4),
      Text('Hi${name.isNotEmpty ? ', $name' : ''}. Choose a new password below.',
          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
      const SizedBox(height: 20),
      TextField(
        controller: _newPassCtrl,
        obscureText: !_showNewPass,
        decoration: InputDecoration(
          labelText: 'New Password',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(
            icon: Icon(_showNewPass ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
            onPressed: () => setState(() => _showNewPass = !_showNewPass),
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _confirmCtrl,
        obscureText: !_showConfirmPass,
        decoration: InputDecoration(
          labelText: 'Confirm Password',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(
            icon: Icon(_showConfirmPass ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
            onPressed: () => setState(() => _showConfirmPass = !_showConfirmPass),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
      ],
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _saving ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Reset Password'),
        ),
      ),
    ]);
  }

  Widget _message({required IconData icon, required String title, required String body}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: const Color(0xFF9CA3AF)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
        ],
      );

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: child,
      );
}
