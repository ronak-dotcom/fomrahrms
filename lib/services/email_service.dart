import 'dart:convert';
import 'dart:typed_data';
import '../models/app_user.dart';
import '../utils/token_util.dart';
import 'supabase_service.dart';

/// One reusable attachment shape for both the email log and the edge function.
class EmailAttachment {
  final String filename;
  final Uint8List bytes;
  final String contentType;
  const EmailAttachment({
    required this.filename,
    required this.bytes,
    this.contentType = 'application/pdf',
  });

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'contentBase64': base64Encode(bytes),
        'contentType': contentType,
      };
}

/// Subject + HTML body for each transactional email template used by the
/// post-approval recruitment pipeline. `data` keys are template-specific —
/// see each builder below.
typedef _TemplateBuilder = (String subject, String html) Function(Map<String, dynamic> data);

/// The single reusable email entry point the recruitment pipeline uses:
/// `EmailService.sendEmail(templateName: ..., recipient: ..., data: {...})`.
///
/// Every send is logged to `email_logs` before/after the actual SMTP call
/// (via `SupabaseService.sendEmail`, which talks to the `send-email` Edge
/// Function). Swapping SMTP for Microsoft Graph API later only touches that
/// Edge Function — this file and every call site stay the same.
class EmailService {
  static const Map<String, _TemplateBuilder> _templates = {
    'pre_offer': _preOfferTemplate,
    'onboarding_invite': _onboardingInviteTemplate,
    'employee_activation': _employeeActivationTemplate,
    'password_reset': _passwordResetTemplate,
  };

  static Future<String?> sendEmail({
    required String templateName,
    required String recipient,
    required Map<String, dynamic> data,
    List<EmailAttachment> attachments = const [],
    String? relatedCandidateId,
    String? relatedOnboardingId,
  }) async {
    final builder = _templates[templateName];
    if (builder == null) return 'Unknown email template: $templateName';
    final (subject, html) = builder(data);
    final attachmentJson = attachments.map((a) => a.toJson()).toList();

    final logId = await SupabaseService.insertEmailLog({
      'template_name': templateName,
      'recipient': recipient,
      'subject': subject,
      'html_body': html,
      'variables': data,
      'attachments': attachmentJson.map((a) => {'filename': a['filename'], 'contentType': a['contentType']}).toList(),
      'status': 'pending',
      'related_candidate_id': relatedCandidateId,
      'related_onboarding_id': relatedOnboardingId,
    });

    final error = await SupabaseService.sendEmail(
      to: recipient,
      subject: subject,
      body: _stripHtml(html),
      html: html,
      attachments: attachmentJson,
    );

    if (logId != null) {
      await SupabaseService.updateEmailLog(logId, error == null
          ? {'status': 'sent', 'sent_at': DateTime.now().toUtc().toIso8601String()}
          : {'status': 'failed', 'error_message': error});
    }
    return error;
  }

  /// Generates a 24h "Set Your Password" token, locks the account
  /// (active:false) until it's used, and emails the activation link —
  /// shared by every place an account can be switched on for the first
  /// time (Employee Onboarding's Approve, Administration's Onboarding-tab
  /// Approve, and the Activate User toggle in Administration → Users), so
  /// all three stay in sync instead of each having their own copy.
  ///
  /// [personalEmail] is where the mail actually needs to go — a brand-new
  /// employee's @fomrahousing.in address (user.email) is just a login
  /// username at this point, not a provisioned mailbox, so sending there
  /// looks successful (SMTP accepts it) but nothing ever arrives. Falls
  /// back to user.email only if no personal email could be resolved, so
  /// something is still attempted rather than silently skipped.
  static Future<String?> sendEmployeeActivation(AppUser user, {String? personalEmail}) async {
    final recipient = (personalEmail != null && personalEmail.isNotEmpty) ? personalEmail : user.email;
    final token = TokenUtil.generate();
    // setAppUserActivationToken throws if the save didn't actually take
    // effect (see its doc comment) — caught here and returned as an error
    // string so every caller's existing "show $error in a snackbar" code
    // still works, instead of an unhandled exception making the button
    // that triggered this look like it does nothing at all.
    try {
      await SupabaseService.setAppUserActivationToken(
        user.email,
        token: token,
        expiresAt: TokenUtil.expiresInHours(24),
      );
    } catch (e) {
      return e.toString();
    }
    return sendEmail(
      templateName: 'employee_activation',
      recipient: recipient,
      data: {
        'name': user.name,
        'employeeId': user.employeeId,
        'userId': user.email,
        'setPasswordLink': 'https://fomrahrms-zeta.vercel.app/#/set-password/$token',
        'portalUrl': 'https://fomrahrms-zeta.vercel.app/#/login',
      },
    );
  }

  /// "Forgot Password" for an already-active account.
  ///
  /// This originally required companyEmail and refused outright when it was
  /// blank ("No company mail on file"), on the assumption that companyEmail
  /// was a separate Microsoft/365 mailbox distinct from the login address.
  /// In practice HR enters the same @fomrahousing.in address in both fields —
  /// where companyEmail is populated at all it is byte-identical to email —
  /// so that assumption only ever produced a dead end: 3 of 5 live accounts
  /// had a blank companyEmail and could not reset their password at all.
  ///
  /// Falls back to the login email so a reset is always possible. Doesn't
  /// touch `active`, so the old password keeps working until the employee
  /// actually completes the reset.
  static Future<String?> sendPasswordReset(AppUser user) async {
    final recipient =
        user.companyEmail.trim().isNotEmpty ? user.companyEmail.trim() : user.email.trim();
    if (recipient.isEmpty) {
      return 'No email address on file for this account — contact HR.';
    }
    final token = TokenUtil.generate();
    // Throws if the save didn't affect any row, rather than sending a reset
    // link that could never work — same guard as the activation flow.
    try {
      await SupabaseService.setPasswordResetToken(
        user.email,
        token: token,
        expiresAt: TokenUtil.expiresInHours(24),
      );
    } catch (e) {
      return 'Could not start the password reset: $e';
    }
    return sendEmail(
      templateName: 'password_reset',
      recipient: recipient,
      data: {
        'name': user.name,
        'resetLink': 'https://fomrahrms-zeta.vercel.app/#/reset-password/$token',
      },
    );
  }

  /// Forgot-password entry point for the login screen, where nobody is signed
  /// in yet.
  ///
  /// [sendPasswordReset] above takes an AppUser, which the login screen could
  /// only get by reading app_users — a table whose policies are granted to
  /// `authenticated` only. Logged out, that read came back empty and the
  /// dialog reported "No account found with that email" for every employee.
  /// This variant hands the identifier to a SECURITY DEFINER RPC that does
  /// the lookup and the token write together.
  ///
  /// Returns null on success, or a message to show the employee.
  static Future<String?> sendPasswordResetByIdentifier(String identifier) async {
    final token = TokenUtil.generate();
    final res = await SupabaseService.requestPasswordReset(
      identifier,
      token: token,
      expiresAt: TokenUtil.expiresInHours(24),
    );
    switch (res.status) {
      case 'ok':
        break;
      case 'inactive':
        return 'This account is no longer active. Please contact HR.';
      case 'not_found':
        return 'No account found with that email, employee ID or mobile number.';
      default:
        return 'Could not start the password reset — please try again.';
    }
    final recipient = (res.recipient ?? '').trim();
    if (recipient.isEmpty) {
      return 'No email address on file for this account — contact HR.';
    }
    return sendEmail(
      templateName: 'password_reset',
      recipient: recipient,
      data: {
        'name': res.name ?? '',
        'resetLink': 'https://fomrahrms-zeta.vercel.app/#/reset-password/$token',
      },
    );
  }

  /// Re-sends a previously logged email using its stored template/data/attachments.
  static Future<String?> resend(String emailLogId) async {
    final log = await SupabaseService.fetchEmailLog(emailLogId);
    if (log == null) return 'Email log not found';
    final templateName = (log['template_name'] as String?) ?? '';
    final recipient = (log['recipient'] as String?) ?? '';
    final data = log['variables'] is Map ? Map<String, dynamic>.from(log['variables'] as Map) : <String, dynamic>{};
    final builder = _templates[templateName];
    if (builder == null) return 'Unknown email template: $templateName';
    final (subject, html) = builder(data);

    final storedAttachments = (log['attachments'] as List?) ?? [];
    final error = await SupabaseService.sendEmail(
      to: recipient,
      subject: subject,
      body: _stripHtml(html),
      html: html,
      attachments: storedAttachments.isEmpty
          ? null
          : List<Map<String, dynamic>>.from(storedAttachments),
    );

    final retryCount = ((log['retry_count'] as num?)?.toInt() ?? 0) + 1;
    await SupabaseService.updateEmailLog(emailLogId, error == null
        ? {'status': 'sent', 'sent_at': DateTime.now().toUtc().toIso8601String(), 'retry_count': retryCount}
        : {'status': 'failed', 'error_message': error, 'retry_count': retryCount});
    return error;
  }

  static String _stripHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  // ── Templates ──────────────────────────────────────────────────────────

  static (String, String) _preOfferTemplate(Map<String, dynamic> data) {
    final name = (data['name'] ?? '').toString();
    final designation = (data['designation'] ?? '').toString();
    final department = (data['department'] ?? '').toString();
    final acceptLink = (data['acceptLink'] ?? '').toString();
    final subject = 'Offer Letter – Fomra Housing & Infrastructure Pvt Ltd';
    final html = '''
      <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;color:#111827;">
        <h2 style="color:#1e3a8a;">Welcome to Fomra Housing & Infrastructure</h2>
        <p>Dear $name,</p>
        <p>Congratulations! We are pleased to offer you the position of
        <strong>$designation</strong>${department.isNotEmpty ? ' in the <strong>$department</strong> department' : ''}
        at Fomra Housing & Infrastructure Pvt Ltd.</p>
        <p>Please find your Pre-Offer Letter attached to this email as a PDF.</p>
        <p style="text-align:center;margin:28px 0;">
          <a href="$acceptLink" style="background:#2563eb;color:#fff;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;">
            Accept Offer
          </a>
        </p>
        <p>This offer is valid for 3 days from the date of this email.</p>
        <p>Warm regards,<br/>HR Team<br/>Fomra Housing & Infrastructure Pvt Ltd</p>
      </div>
    ''';
    return (subject, html);
  }

  static (String, String) _onboardingInviteTemplate(Map<String, dynamic> data) {
    final name = (data['name'] ?? '').toString();
    final formLink = (data['formLink'] ?? '').toString();
    const subject = 'Complete Your Onboarding Form – Fomra Housing & Infrastructure';
    final html = '''
      <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;color:#111827;">
        <h2 style="color:#1e3a8a;">You're almost there, $name!</h2>
        <p>Thank you for accepting our offer. Please complete your onboarding / joining form
        using the secure link below before your date of joining.</p>
        <p style="text-align:center;margin:28px 0;">
          <a href="$formLink" style="background:#2563eb;color:#fff;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;">
            Complete Onboarding Form
          </a>
        </p>
        <p>If the button doesn't work, copy and paste this link into your browser:<br/>$formLink</p>
        <p>Warm regards,<br/>HR Team<br/>Fomra Housing & Infrastructure Pvt Ltd</p>
      </div>
    ''';
    return (subject, html);
  }

  static (String, String) _employeeActivationTemplate(Map<String, dynamic> data) {
    final name = (data['name'] ?? '').toString();
    final employeeId = (data['employeeId'] ?? '').toString();
    final userId = (data['userId'] ?? '').toString();
    final setPasswordLink = (data['setPasswordLink'] ?? '').toString();
    final portalUrl = (data['portalUrl'] ?? '').toString();
    const subject = 'Welcome to Fomra Housing – Activate Your Employee Account';
    final html = '''
      <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;color:#111827;">
        <h2 style="color:#1e3a8a;">Welcome to Fomra Housing, $name!</h2>
        <p>Your employee account has been created. Here are your account details:</p>
        <table style="width:100%;border-collapse:collapse;margin:16px 0;">
          <tr><td style="padding:6px 0;color:#6b7280;">Employee ID</td><td style="padding:6px 0;font-weight:600;">$employeeId</td></tr>
          <tr><td style="padding:6px 0;color:#6b7280;">User ID</td><td style="padding:6px 0;font-weight:600;">$userId</td></tr>
        </table>
        <p>For your security, please set your own password using the link below.
        This link expires in 24 hours.</p>
        <p style="text-align:center;margin:28px 0;">
          <a href="$setPasswordLink" style="background:#2563eb;color:#fff;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;">
            Set Your Password
          </a>
        </p>
        <p>Once your password is set, sign in at: <a href="$portalUrl">$portalUrl</a></p>
        <p>Warm regards,<br/>HR Team<br/>Fomra Housing & Infrastructure Pvt Ltd</p>
      </div>
    ''';
    return (subject, html);
  }

  static (String, String) _passwordResetTemplate(Map<String, dynamic> data) {
    final name = (data['name'] ?? '').toString();
    final resetLink = (data['resetLink'] ?? '').toString();
    const subject = 'Reset Your Fomra HRMS Password';
    final html = '''
      <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;color:#111827;">
        <h2 style="color:#1e3a8a;">Password Reset Request</h2>
        <p>Hi $name,</p>
        <p>We received a request to reset your Fomra HRMS password. Click the button below to
        set a new one. This link expires in 24 hours.</p>
        <p style="text-align:center;margin:28px 0;">
          <a href="$resetLink" style="background:#2563eb;color:#fff;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;">
            Set New Password
          </a>
        </p>
        <p>If you didn't request this, you can safely ignore this email — your current password
        will keep working.</p>
        <p>Warm regards,<br/>HR Team<br/>Fomra Housing & Infrastructure Pvt Ltd</p>
      </div>
    ''';
    return (subject, html);
  }
}
