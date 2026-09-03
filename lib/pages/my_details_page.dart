import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../models/user_session.dart';
import '../services/user_store.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

/// Reads the employee's real record from app_users.
///
/// This page previously read ProfileStore, an in-memory map that was only
/// ever populated by a bootstrap loader querying an `employee_profiles`
/// table that does not exist. The loader 404'd on every app start, the
/// store stayed empty, and the page showed blank fields for everyone.
/// Removing the dead loader made that permanent, so it now reads the same
/// source the rest of the app treats as the truth about a person.
class MyDetailsPage extends StatefulWidget {
  const MyDetailsPage({super.key});

  @override
  State<MyDetailsPage> createState() => _MyDetailsPageState();
}

class _MyDetailsPageState extends State<MyDetailsPage> {
  static Color get _color => AppTheme.primaryBlue;

  AppUser? _me;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await UserStore.load();
      final match = users.where((u) =>
          u.email.trim().toLowerCase() == UserSession.email.trim().toLowerCase());
      if (!mounted) return;
      setState(() {
        _me = match.isNotEmpty ? match.first : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _me;

    final fields = [
      _Field('Employee ID',       Icons.badge_rounded,           p?.employeeId ?? ''),
      _Field('Full Name',         Icons.person_outline_rounded,  p?.name ?? ''),
      _Field('Mobile',            Icons.phone_rounded,           p?.mobile ?? ''),
      _Field('Email',             Icons.email_rounded,           p?.email ?? ''),
      _Field('Address',           Icons.location_on_rounded,     p?.address ?? ''),
      _Field('Department',        Icons.account_tree_rounded,    p?.department ?? ''),
      _Field('Designation',       Icons.work_rounded,            p?.designation ?? ''),
      _Field('Reporting Manager', Icons.manage_accounts_rounded, p?.reportingManager ?? ''),
      _Field('Date of Joining',   Icons.calendar_today_rounded,  p?.dateOfJoining ?? ''),
      _Field('Work Location',     Icons.place_rounded,           p?.workLocation ?? ''),
    ];

    return Scaffold(
      backgroundColor: null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                child: Icon(Icons.badge_rounded, color: _color, size: 26),
              ),
              const SizedBox(width: 16),
              Text('My Details',
                  style: Theme.of(context).textTheme.headlineMedium),
            ]),
            const SizedBox(height: 24),

            // Profile avatar card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: _color.withValues(alpha: 0.1),
                    child: Icon(Icons.person_rounded, color: _color, size: 40),
                  ),
                  const SizedBox(width: 20),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      (p?.name ?? '').isEmpty ? '—' : p!.name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold,
                          color: Color(0xFF111827)),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: _color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        (p?.designation ?? '').isEmpty ? '—' : p!.designation,
                        style: TextStyle(
                            fontSize: 12, color: _color,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: fields.map((f) => _DetailRow(field: f)).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field {
  final String label;
  final IconData icon;
  final String value;
  const _Field(this.label, this.icon, this.value);
}

class _DetailRow extends StatelessWidget {
  final _Field field;
  const _DetailRow({required this.field});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(field.icon, color: AppTheme.primaryBlue, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(field.label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
            const SizedBox(height: 2),
            Text(
              field.value.isEmpty ? '—' : field.value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: field.value.isEmpty
                      ? const Color(0xFFB0BEC5)
                      : const Color(0xFF263238)),
            ),
          ]),
        ),
      ]),
    );
  }
}
