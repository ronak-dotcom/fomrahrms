import '../models/app_user.dart';
import '../models/notification_store.dart';
import '../models/office_timing.dart';
import '../models/task_store.dart';
import '../models/user_session.dart';
import '../utils/checkin_status.dart';
import '../utils/tenure.dart';
import 'supabase_service.dart';
import 'user_store.dart';

/// Creates notification rows for every event the app can raise, and keeps
/// the in-memory [NotificationStore] in sync so the bell badge / feed update
/// immediately instead of waiting for the next periodic refresh.
///
/// Every method takes its target explicitly (email / reporting-manager name)
/// rather than looking it up itself — callers already have the relevant
/// AppUser/employee record in scope wherever these are invoked.
class NotificationService {
  /// Shared '' / '/employee' / '/manager' / '/management' route-prefix
  /// mapping — several call sites already duplicated this switch inline.
  static String routePrefixForRole(UserRole role) => switch (role) {
        UserRole.hr => '/hr',
        UserRole.employee => '/employee',
        UserRole.reportingManager => '/manager',
        UserRole.management => '/management',
      };

  /// The "My Profile" route per role — unlike most pages this isn't just
  /// `prefix + '/profile'` (see UserSession.profileRoute, which is the same
  /// mapping for the *current* session; this is for looking up someone
  /// else's route from their AppUser.role string).
  /// The "My Tasks" route for a role's route prefix — irregular for
  /// employees, whose tasks page is `/employee/tasks`, not `/employee/my-tasks`
  /// like every other role.
  static String _myTasksRoute(String routePrefix) =>
      routePrefix == '/employee' ? '/employee/tasks' : '$routePrefix/my-tasks';

  static String profileRouteForRole(UserRole role) => switch (role) {
        UserRole.hr => '/hr/my-profile',
        UserRole.reportingManager => '/manager/my-profile',
        UserRole.management => '/management/my-profile',
        UserRole.employee => '/employee/profile',
      };

  static Future<void> _create({
    required String type,
    required String title,
    String body = '',
    String route = '',
    String targetEmail = '',
    String targetRole = '',
    String targetReportingManager = '',
    String sourceId = '',
  }) async {
    await SupabaseService.insertNotification(
      type: type, title: title, body: body, route: route,
      targetEmail: targetEmail, targetRole: targetRole,
      targetReportingManager: targetReportingManager, sourceId: sourceId,
    );
    NotificationStore.all.insert(0, AppNotification(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      createdAt: DateTime.now(),
      type: type, title: title, body: body, route: route,
      targetEmail: targetEmail, targetRole: targetRole,
      targetReportingManager: targetReportingManager, sourceId: sourceId,
    ));
    NotificationStore.recomputeUnread();
  }

  static Future<void> markRead(AppNotification n) async {
    if (n.isReadBy(UserSession.email)) return;
    n.readBy.add(UserSession.email);
    NotificationStore.recomputeUnread();
    // Local placeholders are inserted so a new notification appears at once,
    // before the row comes back from the server. Their ids are not real —
    // sending one to the database produced "invalid input syntax for type
    // uuid: local-1788584075634000" on every read. Marked read locally only;
    // the real row is marked when it arrives on the next refresh.
    if (n.id.startsWith('local-')) return;
    await SupabaseService.markNotificationRead(n.id, n.readBy);
  }

  static Future<void> markAllRead(List<AppNotification> notifications) async {
    for (final n in notifications) {
      if (!n.isReadBy(UserSession.email)) {
        n.readBy.add(UserSession.email);
        // Same placeholder guard as markRead().
        if (n.id.startsWith('local-')) continue;
        await SupabaseService.markNotificationRead(n.id, n.readBy);
      }
    }
    NotificationStore.recomputeUnread();
  }

  // ── Leave & attendance ───────────────────────────────────────────────

  // Notifies the employee's Reporting Manager (existing), plus HR and
  // Management (broadcast) — the RM approves it, but HR/Management still
  // want visibility into every request as it comes in.
  /// Raised when a device could not verify a check-in and the employee is
  /// asking their manager to confirm presence instead.
  ///
  /// Only the reporting manager is told at this point. Notifying HR and
  /// Management simultaneously meant everyone saw a request none of them
  /// could act on yet — the manager has to confirm first — and three inboxes
  /// filled with items that were not anyone's turn.
  static Future<void> attendanceConfirmationRequested({
    required String employeeName,
    required String dateLabel,
    required String reportingManagerName,
  }) async {
    if (reportingManagerName.isNotEmpty) {
      // The route must match the RECIPIENT's shell, not the sender's. A
      // reporting manager can hold any role — Devaraj's is Management — and
      // _guard() confines each role to its own prefix, so a hardcoded
      // '/manager/approvals' bounced him to his dashboard: the notification
      // arrived and tapping it appeared to do nothing.
      final mgr = await SupabaseService.userByName(reportingManagerName);
      final prefix = switch ((mgr?['role'] as String?)?.toLowerCase()) {
        'management' => '/management',
        'hr' => '/hr',
        _ => '/manager',
      };
      await _create(
        type: 'attendance_confirmation_requested',
        title: 'Attendance confirmation needed',
        body: '$employeeName could not check in on $dateLabel and has asked '
            'you to confirm they were present',
        route: '$prefix/approvals',
        targetReportingManager: reportingManagerName,
      );
    } else {
      // No reporting manager on file, so nobody would ever see it. HR is the
      // fallback rather than letting the request sit unseen.
      await _create(
        type: 'attendance_confirmation_requested',
        title: 'Attendance confirmation raised',
        body: '$employeeName could not check in on $dateLabel '
            '(no reporting manager on file)',
        route: '/hr/approvals',
        targetRole: 'HR',
      );
    }
  }

  /// The manager has confirmed; it is now HR's turn to approve.
  static Future<void> attendanceConfirmationManagerDecided({
    required String employeeName,
    required String dateLabel,
    required String managerName,
    required bool confirmed,
  }) async {
    // A rejected request stops here — there is nothing for HR to approve, and
    // telling them would only add an item they must dismiss.
    if (!confirmed) return;
    await _create(
      type: 'attendance_confirmation_manager_confirmed',
      title: 'Attendance confirmation to approve',
      body: '$managerName confirmed $employeeName was present on $dateLabel',
      route: '/hr/approvals',
      targetRole: 'HR',
    );
  }

  /// HR has approved. Management is told only now, once both signatures are
  /// in and the day has actually become attendance.
  static Future<void> attendanceConfirmationHrApproved({
    required String employeeName,
    required String employeeEmail,
    required String dateLabel,
    required String hrName,
  }) async {
    await _create(
      type: 'attendance_confirmation_approved',
      title: 'Vouched attendance recorded',
      body: '$hrName approved $employeeName\u2019s attendance for $dateLabel '
          '(no GPS or selfie — confirmed by manager)',
      route: '/management/approvals',
      targetRole: 'Management',
    );
    // The employee is told too: they raised it and otherwise would not know
    // it had gone through. Skipped when no address is known rather than
    // sending with an empty target, which matches nobody.
    if (employeeEmail.isNotEmpty) {
      await _create(
        type: 'attendance_confirmation_approved',
        title: 'Your attendance was confirmed',
        body: 'Your attendance for $dateLabel has been approved',
        route: '/employee/attendance-confirmation',
        targetEmail: employeeEmail,
      );
    }
  }

  static Future<void> leaveSubmitted({
    required String employeeName,
    required String leaveType,
    required String reportingManagerName,
  }) async {
    if (reportingManagerName.isNotEmpty) {
      await _create(
        type: 'leave_submitted',
        title: 'New leave request',
        body: '$employeeName requested $leaveType',
        route: '/manager/leave/team-approvals',
        targetReportingManager: reportingManagerName,
      );
    }
    await _create(
      type: 'leave_submitted',
      title: 'New leave request',
      body: '$employeeName requested $leaveType',
      route: '/leave-management',
      targetRole: 'HR',
    );
    await _create(
      type: 'leave_submitted',
      title: 'New leave request',
      body: '$employeeName requested $leaveType',
      route: '/management/leave-management',
      targetRole: 'Management',
    );
  }

  static Future<void> leaveDecided({
    required String employeeEmail,
    required String leaveType,
    required bool approved,
    required String employeeRoutePrefix, // '', '/employee', '/manager', '/management'
    String employeeName = '',
  }) async {
    await _create(
      type: 'leave_decided',
      title: approved ? 'Leave approved' : 'Leave rejected',
      body: leaveType,
      route: '$employeeRoutePrefix/attendance-leaves',
      targetEmail: employeeEmail,
    );

    // HR and Management both get a copy. HR was previously left out entirely,
    // so leave could be approved by a reporting manager without HR ever
    // knowing — while HR is the function that has to act on it for attendance
    // and payroll.
    //
    // The employee's NAME is included in the copy. Without it the notification
    // read "Leave approved by Sharad — Casual Leave", which does not say whose
    // leave, and the recipient had to open the queue to find out.
    if (UserSession.name.isNotEmpty) {
      final who = employeeName.isNotEmpty ? '$employeeName — ' : '';
      final title = 'Leave ${approved ? 'approved' : 'rejected'} by ${UserSession.name}';

      await _create(
        type: 'leave_decided',
        title: title,
        body: '$who$leaveType',
        route: '/leave-management',
        targetRole: 'HR',
      );
      await _create(
        type: 'leave_decided',
        title: title,
        body: '$who$leaveType',
        route: '/management/leave-management',
        targetRole: 'Management',
      );
    }
  }

  static Future<void> attendanceRegularized({
    required String employeeEmail,
    required bool approved,
    required String employeeRoutePrefix,
  }) => _create(
        type: 'attendance_regularized',
        title: approved ? 'Attendance regularization approved' : 'Attendance regularization rejected',
        route: '$employeeRoutePrefix/attendance-leaves',
        targetEmail: employeeEmail,
      );

  // ── On-roll confirmation (3-stage) ──────────────────────────────────

  static Future<void> onrollRequested({
    required String employeeName,
    required String reportingManagerName,
  }) async {
    await _create(
      type: 'onroll_hr_pending',
      title: 'On-roll confirmation pending',
      body: '$employeeName requested on-roll confirmation',
      route: '/employee-management',
      targetRole: 'HR',
    );
    await _create(
      type: 'onroll_manager_pending',
      title: 'On-roll confirmation pending',
      body: '$employeeName requested on-roll confirmation',
      route: '/manager/employee-management',
      targetReportingManager: reportingManagerName,
    );
  }

  static Future<void> onrollStageDecided({
    required String employeeEmail,
    required String stage, // 'HR' | 'Manager'
    required bool accepted,
  }) => _create(
        type: 'onroll_stage_decided',
        title: '$stage ${accepted ? 'accepted' : 'denied'} your on-roll request',
        route: '/employee/profile',
        targetEmail: employeeEmail,
      );

  static Future<void> onrollReachedManagement({required String employeeName}) => _create(
        type: 'onroll_management_pending',
        title: 'On-roll confirmation awaiting final approval',
        body: '$employeeName — HR and Manager both accepted',
        route: '/management/onroll-approvals',
        targetRole: 'Management',
      );

  /// Fired once, on the exact day an employee crosses the 6-month mark and
  /// hasn't already requested on-roll confirmation — see [checkDailyReminders].
  static Future<void> onrollEligible({
    required String employeeEmail,
    required String profileRoute,
    required String sourceId,
  }) => _create(
        type: 'onroll_eligible',
        title: 'You\'re eligible to request On-Roll confirmation',
        route: profileRoute,
        targetEmail: employeeEmail,
        sourceId: sourceId,
      );

  static Future<void> onrollFinalDecided({
    required String employeeEmail,
    required bool approved,
  }) => _create(
        type: 'onroll_final_decided',
        title: approved ? 'On-roll confirmation approved' : 'On-roll confirmation denied',
        route: '/employee/profile',
        targetEmail: employeeEmail,
      );

  // ── Tasks ────────────────────────────────────────────────────────────

  // Notifies the assignee (existing), plus HR and Management (broadcast) —
  // they want visibility into every task handed out, not just their own.
  static Future<void> taskAssigned({
    required String taskName,
    required String assigneeEmail,
    required String assigneeRoutePrefix,
  }) async {
    await _create(
      type: 'task_assigned',
      title: 'New task assigned',
      body: taskName,
      route: _myTasksRoute(assigneeRoutePrefix),
      targetEmail: assigneeEmail,
    );
    await _create(
      type: 'task_assigned',
      title: 'New task assigned',
      body: taskName,
      route: '/task-management',
      targetRole: 'HR',
    );
    await _create(
      type: 'task_assigned',
      title: 'New task assigned',
      body: taskName,
      route: '/management/task-management',
      targetRole: 'Management',
    );
  }

  static Future<void> taskCompleted({
    required String taskName,
    required String reportingManagerName,
  }) => _create(
        type: 'task_completed',
        title: 'Task completed',
        body: taskName,
        route: '/manager/task-management',
        targetReportingManager: reportingManagerName,
      );

  /// An employee requested a new appraisal — notify HR to set it up.
  static Future<void> appraisalRequested({required String employeeName}) => _create(
        type: 'appraisal_requested',
        title: 'Appraisal requested',
        body: '$employeeName requested a new appraisal',
        route: '/appraisals',
        targetRole: 'HR',
      );

  /// HR finished setup and sent the appraisal on to the employee.
  static Future<void> appraisalSentToEmployee({required String employeeEmail}) => _create(
        type: 'appraisal_sent_to_employee',
        title: 'Appraisal ready for self-evaluation',
        body: 'Your appraisal form is ready — fill in your self-evaluation',
        route: '/employee/appraisal',
        targetEmail: employeeEmail,
      );

  /// The employee submitted their self-evaluation — notify their Reporting
  /// Manager so they can add their remarks and final score.
  static Future<void> appraisalSubmittedToRm({
    required String employeeName,
    required String reportingManagerName,
  }) {
    if (reportingManagerName.trim().isEmpty) return Future.value();
    return _create(
      type: 'appraisal_submitted_to_rm',
      title: 'Appraisal awaiting your review',
      body: '$employeeName\'s appraisal form is ready for your review',
      route: '/manager/appraisal-received',
      targetReportingManager: reportingManagerName,
    );
  }

  /// The Reporting Manager submitted their review — notify Management.
  static Future<void> appraisalSubmittedToManagement({required String employeeName}) => _create(
        type: 'appraisal_submitted_to_management',
        title: 'Appraisal awaiting Management',
        body: '$employeeName\'s appraisal form is ready for Management review',
        route: '/management/appraisals',
        targetRole: 'Management',
      );

  /// Management completed the final stage — the form is back with HR
  /// (view/download only) and the employee can see the final outcome.
  static Future<void> appraisalCompleted({
    required String employeeEmail,
    required String employeeName,
  }) async {
    await _create(
      type: 'appraisal_completed',
      title: 'Appraisal completed',
      body: '$employeeName\'s appraisal is complete',
      route: '/appraisals',
      targetRole: 'HR',
    );
    await _create(
      type: 'appraisal_completed',
      title: 'Your appraisal is complete',
      route: '/employee/appraisal',
      targetEmail: employeeEmail,
    );
  }

  /// HR uploaded a KRA document — it's held pending until Management
  /// approves it, so Management needs to know it's waiting.
  static Future<void> kraUploaded({required String employeeName}) => _create(
        type: 'kra_uploaded',
        title: 'KRA pending approval',
        body: '$employeeName\'s new KRA document needs your review',
        route: '/management/kra-approvals',
        targetRole: 'Management',
      );

  /// Management approved/rejected an HR-uploaded KRA — HR (who uploaded it)
  /// needs to know the outcome.
  static Future<void> kraDecided({
    required String employeeName,
    required bool approved,
  }) => _create(
        type: 'kra_decided',
        title: approved ? 'KRA approved' : 'KRA rejected',
        body: '$employeeName\'s KRA document was ${approved ? 'approved' : 'rejected'} by Management',
        route: '/kra-management',
        targetRole: 'HR',
      );

  /// HR/Management-wide visibility into every task status change (not just
  /// completion), distinct from [taskCompleted] which only tells the
  /// reporting manager.
  static Future<void> taskStatusChanged({
    required String taskName,
    required String status,
    required String changedBy,
  }) async {
    await _create(
      type: 'task_status_changed',
      title: 'Task status updated to $status',
      body: '$taskName · by $changedBy',
      route: '/task-management',
      targetRole: 'HR',
    );
    await _create(
      type: 'task_status_changed',
      title: 'Task status updated to $status',
      body: '$taskName · by $changedBy',
      route: '/management/task-management',
      targetRole: 'Management',
    );
  }

  // ── Maintenance ──────────────────────────────────────────────────────

  static Future<void> maintenanceSubmitted({
    required String issueType,
    required String reportedBy,
    required bool sentToManagement,
    bool reportedByHr = false,
  }) async {
    await _create(
      type: 'maintenance_submitted',
      title: 'New maintenance issue',
      body: '$reportedBy · $issueType',
      route: '/maintenance-management',
      targetRole: 'HR',
    );
    // Management sees it if it's been explicitly escalated, OR if HR is the
    // one reporting it — HR raising an issue is itself worth Management's
    // attention even before anyone flags it as escalated.
    if (sentToManagement || reportedByHr) {
      await _create(
        type: 'maintenance_submitted',
        title: 'New maintenance issue',
        body: '$reportedBy · $issueType',
        route: '/management/maintenance-management',
        targetRole: 'Management',
      );
    }
  }

  static Future<void> maintenanceEscalated({
    required String issueType,
    required String reportedBy,
    required String note,
  }) => _create(
        type: 'maintenance_escalated',
        title: 'Maintenance issue sent for review',
        body: '$reportedBy · $issueType — $note',
        route: '/management/maintenance-management',
        targetRole: 'Management',
      );

  static Future<void> maintenanceStatusChanged({
    required String reporterEmail,
    required String issueType,
    required String status,
    required String reporterRoutePrefix,
  }) => _create(
        type: 'maintenance_status_changed',
        title: 'Maintenance issue $status',
        body: issueType,
        route: '$reporterRoutePrefix/maintenance-management',
        targetEmail: reporterEmail,
      );

  // ── Candidates / interviews ──────────────────────────────────────────

  static Future<void> candidateSubmitted({required String candidateName}) async {
    await _create(
      type: 'candidate_hr_review',
      title: 'New candidate application',
      body: candidateName,
      route: '/interview-process',
      targetRole: 'HR',
    );
    await _create(
      type: 'candidate_hr_review',
      title: 'New candidate application',
      body: candidateName,
      route: '/management/interview-process',
      targetRole: 'Management',
    );
  }

  static Future<void> candidateAssignedToManager({
    required String candidateName,
    required String managerName,
  }) => _create(
        type: 'candidate_assigned_manager',
        title: 'Candidate assigned for review',
        body: candidateName,
        route: '/manager/interview-review',
        targetReportingManager: managerName,
      );

  static Future<void> candidateReadyForManagement({required String candidateName}) => _create(
        type: 'candidate_management_review',
        title: 'Candidate ready for final review',
        body: candidateName,
        route: '/management/interview-review',
        targetRole: 'Management',
      );

  // ── Onboarding ───────────────────────────────────────────────────────

  static Future<void> onboardingFormSubmitted({required String name}) async {
    await _create(
      type: 'onboarding_form_submitted',
      title: 'New onboarding form submitted',
      body: name,
      route: '/employee-onboarding',
      targetRole: 'HR',
    );
    await _create(
      type: 'onboarding_form_submitted',
      title: 'New onboarding form submitted',
      body: name,
      route: '/management/employee-onboarding',
      targetRole: 'Management',
    );
  }

  // ── Post-approval recruitment email workflow ────────────────────────────

  static Future<void> preOfferSent({required String candidateName}) => _create(
        type: 'pre_offer_sent',
        title: 'Pre-Offer Letter sent',
        body: candidateName,
        route: '/interview-process',
        targetRole: 'HR',
      );

  static Future<void> preOfferAccepted({required String candidateName}) => _create(
        type: 'pre_offer_accepted',
        title: 'Candidate accepted the offer',
        body: candidateName,
        route: '/interview-process',
        targetRole: 'HR',
      );

  static Future<void> onboardingLinkSent({required String candidateName}) => _create(
        type: 'onboarding_link_sent',
        title: 'Onboarding form link sent',
        body: candidateName,
        route: '/interview-process',
        targetRole: 'HR',
      );

  static Future<void> onboardingFormSentBack({required String name}) => _create(
        type: 'onboarding_form_sent_back',
        title: 'Onboarding submission sent back by Management',
        body: name,
        route: '/employee-onboarding',
        targetRole: 'HR',
      );

  static Future<void> employeeActivated({required String name}) => _create(
        type: 'employee_activated',
        title: 'Employee account activated',
        body: name,
        route: '/employee-onboarding',
        targetRole: 'HR',
      );

  // ── Form-edit approvals (leave / onboarding / maintenance / interview) ─

  static Future<void> formEditSubmitted({required String formName}) => _create(
        type: 'form_edit_submitted',
        title: 'Form edit awaiting approval',
        body: formName,
        route: '/management/form-approvals',
        targetRole: 'Management',
      );

  static Future<void> formEditDecided({
    required String formName,
    required bool approved,
  }) => _create(
        type: 'form_edit_decided',
        title: approved ? 'Form edit approved' : 'Form edit rejected',
        body: formName,
        route: '/edit-form',
        targetRole: 'HR',
      );

  // ── Payroll ──────────────────────────────────────────────────────────

  static Future<void> payslipReady({
    required String employeeEmail,
    required String monthYear,
    required String employeeRoutePrefix,
  }) => _create(
        type: 'payslip_ready',
        title: 'New payslip available',
        body: monthYear,
        route: '$employeeRoutePrefix/my-payslips',
        targetEmail: employeeEmail,
      );

  static Future<void> payslipRequested({
    required String employeeName,
    required String monthYear,
  }) async {
    await _create(
      type: 'payslip_requested',
      title: 'Payslip requested',
      body: '$employeeName · $monthYear',
      route: '/payroll-management',
      targetRole: 'HR',
    );
    await _create(
      type: 'payslip_requested',
      title: 'Payslip requested',
      body: '$employeeName · $monthYear',
      route: '/management/payroll-management',
      targetRole: 'Management',
    );
  }

  /// Fired when HR/Management rejects a payslip request — the accepted
  /// case doesn't need a separate notification since generating the
  /// payslip already fires [payslipReady].
  static Future<void> payslipRequestDenied({
    required String employeeEmail,
    required String monthYear,
    required String employeeRoutePrefix,
    String reason = '',
  }) => _create(
        type: 'payslip_request_denied',
        title: 'Payslip request denied',
        body: reason.isNotEmpty ? '$monthYear · $reason' : monthYear,
        route: '$employeeRoutePrefix/my-payslips',
        targetEmail: employeeEmail,
      );

  // ── Earned Leave (eligibility + encashment) ─────────────────────────

  /// Fired at the moment HR/Management clicks "Confirm EL Eligibility" —
  /// distinct from [elEligibilityDue], which is the reminder that nudges
  /// HR/Management to go do that in the first place.
  static Future<void> elMarkedEligible({
    required String employeeEmail,
    required String employeeRoutePrefix,
  }) => _create(
        type: 'el_marked_eligible',
        title: 'You\'re now eligible for Earned Leave',
        route: '$employeeRoutePrefix/attendance-leaves',
        targetEmail: employeeEmail,
      );

  static Future<void> elEncashmentRequested({required String employeeName}) async {
    await _create(
      type: 'el_encashment_requested',
      title: 'EL encashment requested',
      body: employeeName,
      route: '/payroll-management',
      targetRole: 'HR',
    );
    await _create(
      type: 'el_encashment_requested',
      title: 'EL encashment requested',
      body: employeeName,
      route: '/management/payroll-management',
      targetRole: 'Management',
    );
  }

  /// Fired once, on the exact day an on-roll employee crosses the
  /// 1-year-since-on-roll mark — a reminder to go confirm EL eligibility,
  /// which stays a manual HR/Management action either way.
  static Future<void> elEligibilityDue({
    required String employeeName,
    required String sourceId,
  }) async {
    await _create(
      type: 'el_eligibility_due',
      title: 'EL eligibility review due',
      body: '$employeeName — 1 year on-roll',
      route: '/employee-management',
      targetRole: 'HR',
      sourceId: sourceId,
    );
    await _create(
      type: 'el_eligibility_due',
      title: 'EL eligibility review due',
      body: '$employeeName — 1 year on-roll',
      route: '/management/employee-management',
      targetRole: 'Management',
      sourceId: sourceId,
    );
  }

  /// Fired once, on the exact day an employee hits a tenure milestone
  /// (6 months, or a yearly anniversary) — see [milestoneLabelForToday].
  /// Notifies HR + Management (visibility) and the employee themselves
  /// (congratulations) in the same pass.
  static Future<void> tenureMilestone({
    required String employeeName,
    required String employeeEmail,
    required String employeeProfileRoute,
    required String milestoneLabel,
    required String sourceId,
  }) async {
    await _create(
      type: 'tenure_milestone',
      title: '$employeeName reached $milestoneLabel',
      route: '/employee-management',
      targetRole: 'HR',
      sourceId: sourceId,
    );
    await _create(
      type: 'tenure_milestone',
      title: '$employeeName reached $milestoneLabel',
      route: '/management/employee-management',
      targetRole: 'Management',
      sourceId: sourceId,
    );
    if (employeeEmail.isNotEmpty) {
      await _create(
        type: 'tenure_milestone',
        title: 'Congrats on $milestoneLabel with FOMRA!',
        route: employeeProfileRoute,
        targetEmail: employeeEmail,
        sourceId: sourceId,
      );
    }
  }

  // ── Leads ────────────────────────────────────────────────────────────

  static Future<void> leadAdded({required String leadName}) async {
    await _create(
      type: 'lead_added',
      title: 'New lead added',
      body: leadName,
      route: '/lead-management',
      targetRole: 'HR',
    );
    await _create(
      type: 'lead_added',
      title: 'New lead added',
      body: leadName,
      route: '/management/lead-management',
      targetRole: 'Management',
    );
  }

  // ── Interview outcome (back to HR) ──────────────────────────────────

  static Future<void> interviewDecided({
    required String candidateName,
    required String stage, // 'Manager' | 'Management'
    required bool accepted,
  }) async {
    await _create(
      type: 'candidate_decided',
      title: 'Interview $stage decision: ${accepted ? 'Accepted' : 'Rejected'}',
      body: candidateName,
      route: '/interview-process',
      targetRole: 'HR',
    );
    // Management cares most about the Manager stage — that's the review
    // "received from" a Manager "for" a candidate, before it ever reaches
    // Management's own queue. Their own decisions are self-evident, but
    // broadcasting those too keeps every Management user in sync.
    await _create(
      type: 'candidate_decided',
      title: 'Interview $stage decision: ${accepted ? 'Accepted' : 'Rejected'}',
      body: candidateName,
      route: '/management/interview-review',
      targetRole: 'Management',
    );
  }

  // ── Maintenance addressed by Management ─────────────────────────────

  static Future<void> maintenanceAddressedByManagement({
    required String issueType,
    required String reportedBy,
  }) => _create(
        type: 'maintenance_addressed',
        title: 'Issue sent back by Management',
        body: '$issueType · reported by $reportedBy',
        route: '/maintenance-management',
        targetRole: 'HR',
      );

  // ── Attendance self-confirmation ─────────────────────────────────────

  static Future<void> checkInRecorded({
    required String employeeEmail,
    required String time,
    required String employeeRoutePrefix,
  }) => _create(
        type: 'attendance_checkin',
        title: 'Check-in recorded',
        body: 'at $time',
        route: '$employeeRoutePrefix/attendance-leaves',
        targetEmail: employeeEmail,
      );

  static Future<void> checkOutRecorded({
    required String employeeEmail,
    required String time,
    required String employeeRoutePrefix,
  }) => _create(
        type: 'attendance_checkout',
        title: 'Check-out recorded',
        body: 'at $time',
        route: '$employeeRoutePrefix/attendance-leaves',
        targetEmail: employeeEmail,
      );

  /// HR-wide alert fired alongside [checkInRecorded] whenever a check-in
  /// comes back late — including one that exceeds an already-approved
  /// Permission window, which reads distinctly in the title. Silently does
  /// nothing for on-time or fully permission-covered check-ins.
  static Future<void> notifyIfLateCheckIn({
    required String employeeName,
    required String checkInTime,
    required DateTime date,
    required OfficeTiming schedule,
    // A waived arrival must not raise a late alert either — otherwise HR is
    // notified about lateness Management has already excused.
    bool lateWaived = false,
    // Nor an on-duty day: the timing rules do not apply to business work
    // outside normal hours, so a 9pm BTL start is not a late arrival.
    bool onDuty = false,
  }) async {
    final leaves = await SupabaseService.fetchLeaveApplications();
    final status = checkInStatusFor(checkInTime, date, employeeName, leaves, schedule,
        lateWaived: lateWaived, onDuty: onDuty);
    if (status.status != CheckInStatus.late) return;

    final hadApprovedPermissionToday =
        approvedPermissionMinutesFor(leaves, employeeName, date) > 0;

    await _create(
      type: 'attendance_checkin_late',
      title: hadApprovedPermissionToday
          ? '$employeeName exceeded their approved permission'
          : '$employeeName checked in late',
      body: 'Checked in at $checkInTime',
      route: '/attendance-management',
      targetRole: 'HR',
    );
  }

  // ── Task reminders (self, not user-triggered) ───────────────────────

  static Future<void> taskPendingReminder({
    required String taskName,
    required String assigneeEmail,
    required String assigneeRoutePrefix,
    required String sourceId,
  }) => _create(
        type: 'task_pending_reminder',
        title: 'Task still pending: $taskName',
        route: _myTasksRoute(assigneeRoutePrefix),
        targetEmail: assigneeEmail,
        sourceId: sourceId,
      );

  static Future<void> taskDueSoon({
    required String taskName,
    required String assigneeEmail,
    required String assigneeRoutePrefix,
    required String dueLabel, // 'today' | 'tomorrow'
    required String sourceId,
  }) => _create(
        type: 'task_due_soon',
        title: 'Task due $dueLabel: $taskName',
        route: _myTasksRoute(assigneeRoutePrefix),
        targetEmail: assigneeEmail,
        sourceId: sourceId,
      );

  // ── Announcements ────────────────────────────────────────────────────

  static Future<void> announcementPosted({required String text}) => _create(
        type: 'announcement_posted',
        title: 'New announcement',
        body: text,
        route: '/dashboard',
        targetRole: 'ALL',
      );

  // ── Daily HR/Management reminders (date-crossed, not user actions) ──

  static DateTime? _lastDailyCheck;
  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static bool _alreadyNotified(String sourceId) =>
      NotificationStore.all.any((n) => n.sourceId == sourceId);

  /// Scans every active employee for tenure-milestone and EL-eligibility
  /// anniversaries that land on today, and notifies HR + Management once
  /// per employee per day (deduped via sourceId, since this can be called
  /// repeatedly). Cheap to call often — the actual scan only runs once per
  /// calendar day; either an HR or a Management session can trigger it
  /// (whichever logs in / polls first that day), since tenureMilestone and
  /// elEligibilityDue each write both roles' rows in one pass.
  static Future<void> checkDailyReminders() async {
    if (UserSession.role != UserRole.hr && UserSession.role != UserRole.management) return;
    final today = DateTime.now();
    if (_lastDailyCheck != null && _sameDate(_lastDailyCheck!, today)) return;
    _lastDailyCheck = today;

    final users = await UserStore.load();
    for (final u in users) {
      if (!u.active) continue;
      final userRole = AppUser.userRoleFor(u.role);

      final milestone = milestoneLabelForToday(u.dateOfJoining, today: today);
      if (milestone != null) {
        final sourceId = '${u.employeeId}_tenure_${_dateKey(today)}';
        if (!_alreadyNotified(sourceId)) {
          await tenureMilestone(
            employeeName: u.name,
            employeeEmail: u.email,
            employeeProfileRoute: profileRouteForRole(userRole),
            milestoneLabel: milestone,
            sourceId: sourceId,
          );
        }
        // On-roll eligibility opens up at exactly the same 6-month mark.
        if (milestone == '6 Months' && u.onrollRequestedAt.isEmpty && u.email.isNotEmpty) {
          final onrollSourceId = '${u.employeeId}_onroll_eligible_${_dateKey(today)}';
          if (!_alreadyNotified(onrollSourceId)) {
            await onrollEligible(
              employeeEmail: u.email,
              profileRoute: profileRouteForRole(userRole),
              sourceId: onrollSourceId,
            );
          }
        }
      }

      if (u.isOnroll && !u.isElEligible && u.onrollConfirmedAt.isNotEmpty) {
        final onrollDate = DateTime.tryParse(u.onrollConfirmedAt);
        if (onrollDate != null) {
          final oneYearMark = DateTime(onrollDate.year + 1, onrollDate.month, onrollDate.day);
          if (_sameDate(oneYearMark, today)) {
            final sourceId = '${u.employeeId}_el_eligible_${_dateKey(today)}';
            if (!_alreadyNotified(sourceId)) {
              await elEligibilityDue(employeeName: u.name, sourceId: sourceId);
            }
          }
        }
      }
    }
  }

  // ── Daily task reminders (any signed-in role, own tasks only) ───────

  static DateTime? _lastTaskCheck;

  /// Scans the signed-in user's own tasks (TaskStore is already loaded
  /// globally, same as every other store in this app) for ones still
  /// sitting unstarted, or due today/tomorrow, and reminds them once per
  /// task per day. Unlike [checkDailyReminders] this runs for every role —
  /// anyone can have tasks assigned to them.
  static Future<void> checkDailyTaskReminders() async {
    if (!UserSession.loggedIn) return;
    final today = DateTime.now();
    if (_lastTaskCheck != null && _sameDate(_lastTaskCheck!, today)) return;
    _lastTaskCheck = today;

    final name = UserSession.name.trim();
    final email = UserSession.email;
    if (name.isEmpty || email.isEmpty) return;
    final prefix = routePrefixForRole(UserSession.role);
    final todayDate = DateTime(today.year, today.month, today.day);

    final myTasks = TaskStore.tasks.where((t) =>
        t.assignedEmployee.trim() == name || t.teamMembers.any((m) => m.trim() == name));

    for (final t in myTasks) {
      final isGroupMember = t.teamMembers.any((m) => m.trim() == name);
      final effectiveStatus = isGroupMember
          ? TaskStatus.values.firstWhere(
              (s) => s.name == (t.teamMemberStatuses[name] ?? 'assigned'),
              orElse: () => TaskStatus.assigned)
          : t.status;

      if (effectiveStatus == TaskStatus.assigned) {
        final sourceId = '${t.id}_pending_${_dateKey(today)}';
        if (!_alreadyNotified(sourceId)) {
          await taskPendingReminder(
            taskName: t.name, assigneeEmail: email, assigneeRoutePrefix: prefix,
            sourceId: sourceId,
          );
        }
      }

      if (effectiveStatus != TaskStatus.completed) {
        final daysLeft = t.dueDate.difference(todayDate).inDays;
        if (daysLeft == 0 || daysLeft == 1) {
          final sourceId = '${t.id}_duesoon_${_dateKey(today)}';
          if (!_alreadyNotified(sourceId)) {
            await taskDueSoon(
              taskName: t.name, assigneeEmail: email, assigneeRoutePrefix: prefix,
              dueLabel: daysLeft == 0 ? 'today' : 'tomorrow',
              sourceId: sourceId,
            );
          }
        }
      }
    }
  }
}
