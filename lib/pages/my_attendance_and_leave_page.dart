import 'package:flutter/material.dart';
import '../widgets/back_button.dart';
import '../widgets/mobile_shell.dart';
import 'my_attendance_page.dart';
import 'employee_leave_page.dart';
import '../theme/app_theme.dart';

Color get _blue => AppTheme.primaryBlue;

// Combines MyAttendancePage and EmployeeLeavePage into one scrollable page
// under a single sidebar entry ("My Attendance and Leaves").
class MyAttendanceAndLeavePage extends StatefulWidget {
  final String checkInRoute;
  final String leavePrefix;
  const MyAttendanceAndLeavePage({
    super.key,
    required this.checkInRoute,
    this.leavePrefix = '/employee',
  });

  @override
  State<MyAttendanceAndLeavePage> createState() => _MyAttendanceAndLeavePageState();
}

class _MyAttendanceAndLeavePageState extends State<MyAttendanceAndLeavePage> {
  int _tab = 0;

  String get checkInRoute => widget.checkInRoute;
  String get leavePrefix => widget.leavePrefix;

  /// Phones: the two halves as tabs rather than one very long page, where
  /// leave was only reached after scrolling past the whole calendar.
  Widget _buildMobile(BuildContext context) {
    Widget tab(int i, String label) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _tab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _tab == i ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: _tab == i
                    ? const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))]
                    : null,
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _tab == i ? AppTheme.textPrimary : AppTheme.textSecondary)),
            ),
          ),
        );
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFE8ECF4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [tab(0, 'Attendance'), tab(1, 'Leave & permission')]),
          ),
          const SizedBox(height: 14),
          // Both stay alive so switching back does not reload.
          Visibility(
            visible: _tab == 0,
            maintainState: true,
            child: MyAttendancePage(checkInRoute: checkInRoute, embedded: true),
          ),
          Visibility(
            visible: _tab == 1,
            maintainState: true,
            child: EmployeeLeavePage(prefix: leavePrefix, embedded: true),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MobileChrome.active(context)) return _buildMobile(context);
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const NavBackButton(),
            const SizedBox(width: 8),
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.event_note_rounded, color: _blue, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text('My Attendance and Leaves',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
          ]),
          const SizedBox(height: 24),
          MyAttendancePage(checkInRoute: checkInRoute, embedded: true),
          const SizedBox(height: 32),
          const Divider(height: 1),
          const SizedBox(height: 24),
          EmployeeLeavePage(prefix: leavePrefix, embedded: true),
        ]),
      ),
    );
  }
}
