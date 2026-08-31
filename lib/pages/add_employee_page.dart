import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/org_lists.dart';
import '../models/employee_store.dart';
import '../services/supabase_service.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

class AddEmployeePage extends StatefulWidget {
  const AddEmployeePage({super.key});

  @override
  State<AddEmployeePage> createState() => _AddEmployeePageState();
}

class _AddEmployeePageState extends State<AddEmployeePage> {
  static Color get _color => AppTheme.primaryBlue;

  final _formKey = GlobalKey<FormState>();
  final _employeeIdCtrl    = TextEditingController();
  final _nameCtrl          = TextEditingController();
  final _mobileCtrl        = TextEditingController();
  final _emailCtrl         = TextEditingController();
  final _addressCtrl       = TextEditingController();
  final _departmentCtrl    = TextEditingController();
  final _designationCtrl   = TextEditingController();
  String? _designation;
  final _managerCtrl       = TextEditingController();
  final _joiningDateCtrl   = TextEditingController();
  final _salaryCtrl        = TextEditingController();
  final _documentsCtrl     = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl= TextEditingController();
  final _bloodGroupCtrl    = TextEditingController();
  final _bankAccountCtrl   = TextEditingController();
  final _ifscCtrl          = TextEditingController();

  @override
  void dispose() {
    for (final c in [
      _employeeIdCtrl, _nameCtrl, _mobileCtrl, _emailCtrl, _addressCtrl,
      _departmentCtrl, _designationCtrl, _managerCtrl, _joiningDateCtrl,
      _salaryCtrl, _documentsCtrl, _emergencyNameCtrl, _emergencyPhoneCtrl,
      _bloodGroupCtrl, _bankAccountCtrl, _ifscCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _onSave() async {
    if (_formKey.currentState?.validate() ?? false) {
      final emp = Employee(
        id:             _employeeIdCtrl.text.trim(),
        name:           _nameCtrl.text.trim(),
        mobile:         _mobileCtrl.text.trim(),
        email:          _emailCtrl.text.trim(),
        address:        _addressCtrl.text.trim(),
        department:     _departmentCtrl.text.trim(),
        designation:    _designationCtrl.text.trim(),
        manager:        _managerCtrl.text.trim(),
        joiningDate:    _joiningDateCtrl.text.trim(),
        salary:         _salaryCtrl.text.trim(),
        documents:      _documentsCtrl.text.trim(),
        emergencyName:  _emergencyNameCtrl.text.trim(),
        emergencyPhone: _emergencyPhoneCtrl.text.trim(),
        bloodGroup:     _bloodGroupCtrl.text.trim(),
        bankAccount:    _bankAccountCtrl.text.trim(),
        ifsc:           _ifscCtrl.text.trim(),
      );
      final error = await SupabaseService.saveEmployee(emp);
      if (!context.mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save employee: $error'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        return;
      }
      EmployeeStore.employees.add(emp);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Employee added successfully'),
          backgroundColor: _color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        final path = GoRouterState.of(context).uri.path;
        context.go(path.startsWith('/management/')
            ? '/management/employee-management'
            : '/employee-management');
      }
    }
  }

  void _onClear() {
    for (final c in [
      _employeeIdCtrl, _nameCtrl, _mobileCtrl, _emailCtrl, _addressCtrl,
      _departmentCtrl, _designationCtrl, _managerCtrl, _joiningDateCtrl,
      _salaryCtrl, _documentsCtrl, _emergencyNameCtrl, _emergencyPhoneCtrl,
      _bloodGroupCtrl, _bankAccountCtrl, _ifscCtrl,
    ]) {
      c.clear();
    }
    setState(() => _designation = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: null,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                NavBackButton(),
                const SizedBox(width: 8),
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: _color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.person_add_rounded,
                      color: _color, size: 26),
                ),
                const SizedBox(width: 16),
                Text('Add New Employee',
                    style: Theme.of(context).textTheme.headlineMedium),
              ]),
              const SizedBox(height: 24),

              // ── Personal Information ─────────────────────────────────────
              _SectionHeader(Icons.person_rounded, 'Personal Information'),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    _Field(_employeeIdCtrl,    'Employee ID',      Icons.badge_rounded,            required: true),
                    _Field(_nameCtrl,          'Full Name',        Icons.person_outline_rounded,   required: true),
                    _Field(_mobileCtrl,        'Mobile Number',    Icons.phone_rounded,            keyboard: TextInputType.phone,          required: true),
                    _Field(_emailCtrl,         'Email Address',    Icons.email_rounded,            keyboard: TextInputType.emailAddress,   required: true),
                    _Field(_addressCtrl,       'Address',          Icons.location_on_rounded,      maxLines: 3),
                    _Field(_bloodGroupCtrl,    'Blood Group',      Icons.bloodtype_rounded),
                    _Field(_emergencyNameCtrl, 'Emergency Contact Name',  Icons.contact_emergency_rounded),
                    _Field(_emergencyPhoneCtrl,'Emergency Contact Phone', Icons.phone_callback_rounded, keyboard: TextInputType.phone),
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              // ── Work Information ─────────────────────────────────────────
              _SectionHeader(Icons.work_rounded, 'Work Information'),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    _Field(_departmentCtrl,  'Department',      Icons.account_tree_rounded,          required: true),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DropdownButtonFormField<String>(
                        // Designation drives the employee's assigned Office
                        // Timing (see edit_office_timings_page.dart), so it's
                        // constrained to the fixed list rather than free text.
                        value: _designation,
                        validator: (v) => (v == null || v.isEmpty) ? 'Designation is required' : null,
                        decoration: InputDecoration(
                          labelText: 'Designation',
                          prefixIcon: Icon(Icons.work_outline_rounded, color: AppTheme.primaryBlue, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppTheme.primaryBlue, width: 2),
                          ),
                        ),
                        items: kDesignations
                            .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                            .toList(),
                        onChanged: (v) => setState(() {
                          _designation = v;
                          _designationCtrl.text = v ?? '';
                        }),
                      ),
                    ),
                    _Field(_managerCtrl,     'Reporting Manager', Icons.manage_accounts_rounded),
                    _DateField(_joiningDateCtrl, 'Date of Joining', context),
                    _Field(_salaryCtrl,      'Salary (CTC)',    Icons.account_balance_wallet_rounded, keyboard: TextInputType.number),
                    _Field(_documentsCtrl,   'Documents / Notes', Icons.folder_rounded,             maxLines: 2),
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              // ── Bank Information ─────────────────────────────────────────
              _SectionHeader(Icons.account_balance_rounded, 'Bank Information'),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    _Field(_bankAccountCtrl, 'Bank Account Number', Icons.credit_card_rounded, keyboard: TextInputType.number),
                    _Field(_ifscCtrl,        'IFSC Code',           Icons.confirmation_number_rounded),
                  ]),
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _onClear,
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    label: const Text('Clear All'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _onSave,
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Save Employee'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader(this.icon, this.title);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: AppTheme.primaryBlue),
      const SizedBox(width: 8),
      Text(title,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: AppTheme.primaryBlue, letterSpacing: 0.3)),
      const SizedBox(width: 10),
      Expanded(child: Divider(color: AppTheme.primaryBlue.withValues(alpha: 0.2))),
    ]);
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboard;
  final int maxLines;
  final bool required;

  const _Field(this.controller, this.label, this.icon, {
    this.keyboard = TextInputType.text,
    this.maxLines = 1,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
            : null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppTheme.primaryBlue, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.primaryBlue, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
          filled: true, fillColor: Colors.white,
          labelStyle: const TextStyle(color: Color(0xFF6B7280)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

Widget _DateField(TextEditingController ctrl, String label, BuildContext ctx) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: ctrl,
      readOnly: true,
      onTap: () async {
        final picked = await showDatePicker(
          context: ctx,
          initialDate: DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          ctrl.text =
              '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
        }
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(Icons.calendar_today_rounded,
            color: AppTheme.primaryBlue, size: 20),
        suffixIcon: const Icon(Icons.arrow_drop_down_rounded,
            color: Color(0xFF6B7280)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.primaryBlue, width: 2),
        ),
        filled: true, fillColor: Colors.white,
        labelStyle: const TextStyle(color: Color(0xFF6B7280)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
  );
}
