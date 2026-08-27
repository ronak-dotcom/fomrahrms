import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/onboarding_form_config.dart';
import '../services/supabase_service.dart';
import '../services/notification_service.dart';
import '../utils/image_compress.dart';
import '../utils/pdf_compress.dart';
import '../widgets/app_file_picker.dart';
import '../theme/app_theme.dart';

class _AttachFile {
  final String name;
  Uint8List bytes;
  String mime;
  _AttachFile({required this.name, required this.bytes, required this.mime});
}

class OnboardingFormPage extends StatefulWidget {
  // When reached via /onboarding-form/{token} (the link HR sends after an
  // offer is accepted), this resolves to the candidate row so the
  // submission can be linked back by a real FK instead of the fuzzy
  // name/mobile match employee_onboarding_page.dart falls back to for
  // older, token-less submissions.
  final String? token;
  const OnboardingFormPage({super.key, this.token});

  // Human labels for form_data keys — shared with the HR-side "Request
  // Correction" picker in employee_onboarding_page.dart so both sides of
  // the flow agree on the same key→label mapping.
  static const Map<String, String> fieldLabels = {
    'name': 'Name', 'phone_number': 'Phone Number', 'father_name': "Father's Name",
    'mother_name': "Mother's Name", 'designation': 'Designation',
    'date_of_joining': 'Date of Joining', 'full_name': 'Full Name',
    'date_of_birth': 'Date of Birth', 'postal_address': 'Postal Address',
    'permanent_address': 'Permanent Address', 'family_details': 'Family Details',
    'education': 'Education', 'experience': 'Experience',
    'last_reporting_name': 'Last Reporting Officer', 'last_reporting_designation': 'Last Reporting Designation',
    'last_company': 'Last Company', 'reference1': 'Reference 1', 'reference2': 'Reference 2',
    'esi_number': 'ESI Number', 'pf_number': 'PF Number', 'languages_known': 'Languages Known',
    'hobbies': 'Hobbies', 'interests': 'Interests', 'related_to_employee': 'Related to Employee',
    'professional_membership': 'Professional Membership', 'specialized_training': 'Specialized Training',
    'other_information': 'Other Information', 'blood_group': 'Blood Group', 'allergic_to': 'Allergic To',
    'major_illness': 'Major Illness', 'emergency_contact_name': 'Emergency Contact Name',
    'emergency_contact_number': 'Emergency Contact Number', 'emergency_contact_address': 'Emergency Contact Address',
    'declaration_date': 'Declaration Date', 'declaration_place': 'Declaration Place',
    'attachments': 'Attachments',
  };

  @override
  State<OnboardingFormPage> createState() => _OnboardingFormPageState();
}

class _OnboardingFormPageState extends State<OnboardingFormPage> {
  static Color get _primary => AppTheme.primaryBlue;
  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;
  bool _saving = false;

  // Minimum mandatory entries — the first N rows of each section can't be
  // removed and all their fields are required.
  static const int _requiredFamilyRows    = 2;
  static const int _requiredEducationRows = 3;

  // Attachment doc types that must have at least one file (all except
  // #4 Experience/Relieving letters and #5 Pay Slips/Bank Statement).
  static const _requiredDocIndices = {0, 1, 2, 5};

  // ── Section 1: Basic Info
  final _name        = TextEditingController();
  final _phone       = TextEditingController();
  final _fatherName  = TextEditingController();
  final _motherName  = TextEditingController();
  final _designation = TextEditingController();
  DateTime? _dateJoiningDate;

  // ── Section 2: Personal Data
  final _fullName         = TextEditingController();
  DateTime? _dobDate;
  final _postalAddress    = TextEditingController();
  final _permanentAddress = TextEditingController();

  // ── Section 3: Family Details (dynamic rows + parallel state)
  List<Map<String, TextEditingController>> _familyRows = [];
  List<String?> _familyGenders   = [];
  List<String?> _familyRelations = [];
  List<_AttachFile?> _familyAadhars = [];

  // ── Section 4: Education (dynamic rows)
  List<Map<String, TextEditingController>> _educationRows = [];

  // ── Section 5: Experience (dynamic rows)
  List<Map<String, TextEditingController>> _experienceRows = [];

  // ── Section 6: Last Position
  final _lastReportingName  = TextEditingController();
  final _lastReportingDesig = TextEditingController();
  final _lastCompany        = TextEditingController();
  final _ref1               = TextEditingController();
  final _ref2               = TextEditingController();

  // ── Section 7: Additional Info
  final _esiNumber          = TextEditingController();
  final _pfNumber           = TextEditingController();
  final _languages          = TextEditingController();
  final _hobbies            = TextEditingController();
  final _interests          = TextEditingController();
  final _relatedToEmployee  = TextEditingController();
  final _professionalMember = TextEditingController();
  final _specializedTraining= TextEditingController();
  final _otherInfo          = TextEditingController();

  // ── Section 8: Emergency Details
  String? _bloodGroupValue;
  final _allergicTo       = TextEditingController();
  final _majorIllness     = TextEditingController();
  final _emergencyName    = TextEditingController();
  final _emergencyNumber  = TextEditingController();
  final _emergencyAddress = TextEditingController();
  _AttachFile? _emergencyAadharFile;

  // ── HR Policy
  bool _policyAgreed = false;

  // ── Declaration
  DateTime? _declarationDateVal;
  final _declarationPlace = TextEditingController();
  bool _declarationAgreed = false;

  // ── Attachments (6 doc types, each can have multiple files)
  static const _docLabels = [
    'Photocopies of all Educational certificates & degree mark sheets etc.',
    'Aadhar Card',
    'PAN Card',
    'Experience & Relieving letters of Previous employment\'s',
    'Pay Slips or Bank Statement of Previous employment\'s',
    'Passport Size Photo (2)',
  ];
  final List<List<_AttachFile>> _attachments = List.generate(6, (_) => []);

  // Resolved from widget.token, if present — see _resolveCandidateToken().
  String? _candidateApplicationId;

  // Set when this visit is a candidate returning to fix a HR-flagged
  // correction rather than a first-time fill. _submit() then UPDATEs this
  // row instead of inserting a new one, so the rest of what they already
  // entered is never lost.
  String? _editingOnboardingFormId;
  List<String> _flaggedFields = [];

  // ── Config (loaded from Supabase) ─────────────────────────────────────────
  List<Map<String, dynamic>> _configSections = [];
  final _customTextControllers = <String, TextEditingController>{};
  final _customMcqValues       = <String, String?>{};
  final _customFileNames       = <String, String>{};
  final _customFileUrls        = <String, String>{};
  final _customDateValues      = <String, DateTime?>{};
  final _customCheckboxValues  = <String, bool>{};

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < _requiredFamilyRows; i++) { _addFamilyRow(); }
    for (int i = 0; i < _requiredEducationRows; i++) { _addEducationRow(); }
    _addExperienceRow();
    _loadConfig();
    _resolveCandidateToken();
  }

  Future<void> _resolveCandidateToken() async {
    final token = widget.token;
    if (token == null || token.isEmpty) return;
    try {
      final candidate = await SupabaseService.fetchCandidateByOnboardingToken(token);
      if (candidate == null || !mounted) return;
      _candidateApplicationId = candidate['id']?.toString();

      // A candidate revisiting the same link either hasn't submitted yet,
      // has fully submitted (show "already submitted"), or HR sent their
      // submission back for a correction — in which case we reload what
      // they already entered instead of either blocking them or starting
      // them over from a blank form.
      final existing = await SupabaseService
          .fetchOnboardingFormForCandidate(_candidateApplicationId ?? '');
      if (!mounted) return;

      if (existing != null && existing['needs_correction'] != true) {
        setState(() => _submitted = true);
        return;
      }

      if (existing != null && existing['needs_correction'] == true) {
        final formData = existing['form_data'] is Map
            ? Map<String, dynamic>.from(existing['form_data'] as Map)
            : <String, dynamic>{};
        setState(() {
          _editingOnboardingFormId = existing['id']?.toString();
          _flaggedFields = List<String>.from((existing['fields_to_correct'] as List?) ?? []);
          _prefillFromFormData(formData);
        });
        return;
      }

      setState(() {
        _name.text = (candidate['name'] as String?) ?? '';
        _phone.text = (candidate['mobile'] as String?) ?? '';
        _designation.text = (candidate['designation'] as String?) ?? '';
      });
    } catch (_) {}
  }

  Future<void> _loadConfig() async {
    try {
      final active = await SupabaseService.fetchActiveOnboardingFormVersion();
      final config = active != null
          ? Map<String, dynamic>.from(active['form_config'] as Map)
          : OnboardingFormConfig.defaults();
      if (mounted) {
        setState(() =>
            _configSections = OnboardingFormConfig.getSections(config));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _configSections =
            OnboardingFormConfig.getSections(OnboardingFormConfig.defaults()));
      }
    }
  }

  // Returns config title for a section ID, falling back to the default
  String _cfgTitle(String id, String fallback) {
    try {
      final s = _configSections.firstWhere((s) => (s['id'] as String?) == id);
      final t = (s['title'] as String?)?.trim();
      return (t != null && t.isNotEmpty) ? t : fallback;
    } catch (_) {
      return fallback;
    }
  }

  // Returns whether a section is enabled in the config
  bool _cfgEnabled(String id) {
    try {
      final s = _configSections.firstWhere((s) => (s['id'] as String?) == id);
      return (s['enabled'] as bool?) ?? true;
    } catch (_) {
      return true; // show by default if not in config
    }
  }

  // Returns custom fields for a section from config
  List<Map<String, dynamic>> _cfgCustomFields(String id) {
    try {
      final s = _configSections.firstWhere((s) => (s['id'] as String?) == id);
      return OnboardingFormConfig.getCustomFields(s);
    } catch (_) {
      return [];
    }
  }

  // ── Row management ────────────────────────────────────────────────────────

  void _addFamilyRow() {
    _familyRows.add({
      'name':       TextEditingController(),
      'age':        TextEditingController(),
      'occupation': TextEditingController(),
    });
    _familyGenders.add(null);
    _familyRelations.add(null);
    _familyAadhars.add(null);
    setState(() {});
  }

  void _addEducationRow() {
    _educationRows.add({
      'qualification': TextEditingController(),
      'university':    TextEditingController(),
      'year':          TextEditingController(),
      'marks':         TextEditingController(),
      'subject':       TextEditingController(),
    });
    setState(() {});
  }

  void _addExperienceRow() {
    _experienceRows.add({
      'organisation':   TextEditingController(),
      'from':           TextEditingController(),
      'to':             TextEditingController(),
      'desig_joining':  TextEditingController(),
      'desig_relieving':TextEditingController(),
      'job_resp':       TextEditingController(),
      'superior':       TextEditingController(),
      'salary':         TextEditingController(),
      'reason':         TextEditingController(),
    });
    setState(() {});
  }

  void _removeFamilyRow(int i) {
    for (final c in _familyRows[i].values) c.dispose();
    _familyRows.removeAt(i);
    _familyGenders.removeAt(i);
    _familyRelations.removeAt(i);
    _familyAadhars.removeAt(i);
    setState(() {});
  }

  void _removeEducationRow(int i) {
    for (final c in _educationRows[i].values) c.dispose();
    _educationRows.removeAt(i);
    setState(() {});
  }

  void _removeExperienceRow(int i) {
    for (final c in _experienceRows[i].values) c.dispose();
    _experienceRows.removeAt(i);
    setState(() {});
  }

  // ── Date helpers ──────────────────────────────────────────────────────────

  String _fmt(DateTime? d) => d == null
      ? ''
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // Reverses _fmt() — parses the dd/MM/yyyy strings form_data stores back
  // into a DateTime for prefill. Anything unparsable is left blank rather
  // than crashing the page over one bad legacy value.
  DateTime? _parseFmt(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final parts = s.trim().split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  // Rebuilds every controller/list from a previous submission's form_data —
  // the single JSONB blob _submit() already stores everything into. Used
  // when a candidate reopens their link after HR sent it back for a
  // correction, so they see what they entered before instead of a blank
  // form.
  void _prefillFromFormData(Map<String, dynamic> d) {
    String s(String key) => (d[key] as String?) ?? '';
    _name.text = s('name');
    _phone.text = s('phone_number');
    _fatherName.text = s('father_name');
    _motherName.text = s('mother_name');
    _designation.text = s('designation');
    _dateJoiningDate = _parseFmt(d['date_of_joining'] as String?);
    _fullName.text = s('full_name');
    _dobDate = _parseFmt(d['date_of_birth'] as String?);
    _postalAddress.text = s('postal_address');
    _permanentAddress.text = s('permanent_address');

    final family = (d['family_details'] as List?) ?? [];
    if (family.isNotEmpty) {
      for (final row in _familyRows) { for (final c in row.values) c.dispose(); }
      _familyRows = []; _familyGenders = []; _familyRelations = []; _familyAadhars = [];
      for (final raw in family) {
        final row = Map<String, dynamic>.from(raw as Map);
        _familyRows.add({
          'name': TextEditingController(text: (row['name'] as String?) ?? ''),
          'age': TextEditingController(text: (row['age'] as String?) ?? ''),
          'occupation': TextEditingController(text: (row['occupation'] as String?) ?? ''),
        });
        _familyGenders.add((row['gender'] as String?)?.isEmpty ?? true ? null : row['gender'] as String?);
        _familyRelations.add((row['relation'] as String?)?.isEmpty ?? true ? null : row['relation'] as String?);
        _familyAadhars.add(null); // Previously uploaded aadhar files aren't re-attached to a picker; the URL stays in the row's saved data unless re-uploaded.
      }
    }

    final education = (d['education'] as List?) ?? [];
    if (education.isNotEmpty) {
      for (final row in _educationRows) { for (final c in row.values) c.dispose(); }
      _educationRows = [];
      for (final raw in education) {
        final row = Map<String, dynamic>.from(raw as Map);
        _educationRows.add({
          'qualification': TextEditingController(text: (row['qualification'] as String?) ?? ''),
          'university': TextEditingController(text: (row['university'] as String?) ?? ''),
          'year': TextEditingController(text: (row['year'] as String?) ?? ''),
          'marks': TextEditingController(text: (row['marks'] as String?) ?? ''),
          'subject': TextEditingController(text: (row['subject'] as String?) ?? ''),
        });
      }
    }

    final experience = (d['experience'] as List?) ?? [];
    if (experience.isNotEmpty) {
      for (final row in _experienceRows) { for (final c in row.values) c.dispose(); }
      _experienceRows = [];
      for (final raw in experience) {
        final row = Map<String, dynamic>.from(raw as Map);
        _experienceRows.add({
          'organisation': TextEditingController(text: (row['organisation'] as String?) ?? ''),
          'from': TextEditingController(text: (row['from'] as String?) ?? ''),
          'to': TextEditingController(text: (row['to'] as String?) ?? ''),
          'desig_joining': TextEditingController(text: (row['desig_joining'] as String?) ?? ''),
          'desig_relieving': TextEditingController(text: (row['desig_relieving'] as String?) ?? ''),
          'job_resp': TextEditingController(text: (row['job_resp'] as String?) ?? ''),
          'superior': TextEditingController(text: (row['superior'] as String?) ?? ''),
          'salary': TextEditingController(text: (row['salary'] as String?) ?? ''),
          'reason': TextEditingController(text: (row['reason'] as String?) ?? ''),
        });
      }
    }

    _lastReportingName.text = s('last_reporting_name');
    _lastReportingDesig.text = s('last_reporting_designation');
    _lastCompany.text = s('last_company');
    _ref1.text = s('reference1');
    _ref2.text = s('reference2');
    _esiNumber.text = s('esi_number');
    _pfNumber.text = s('pf_number');
    _languages.text = s('languages_known');
    _hobbies.text = s('hobbies');
    _interests.text = s('interests');
    _relatedToEmployee.text = s('related_to_employee');
    _professionalMember.text = s('professional_membership');
    _specializedTraining.text = s('specialized_training');
    _otherInfo.text = s('other_information');
    final bg = s('blood_group');
    _bloodGroupValue = bg.isEmpty ? null : bg;
    _allergicTo.text = s('allergic_to');
    _majorIllness.text = s('major_illness');
    _emergencyName.text = s('emergency_contact_name');
    _emergencyNumber.text = s('emergency_contact_number');
    _emergencyAddress.text = s('emergency_contact_address');
    _declarationDateVal = _parseFmt(d['declaration_date'] as String?);
    _declarationPlace.text = s('declaration_place');
    // Attachments/custom fields are left for the candidate to re-attach if
    // flagged — file bytes from a prior session aren't retrievable client
    // side, only their stored URLs, which _docLabels' UI doesn't currently
    // render as "already uploaded, keep as is".
  }

  Future<DateTime?> _pickDate({
    DateTime? initial,
    DateTime? first,
    DateTime? last,
  }) =>
      showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: first ?? DateTime(1950),
        lastDate: last ?? DateTime(2100),
        builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
              colorScheme: ColorScheme.light(primary: _primary)),
          child: child!,
        ),
      );

  // Opens a calendar picker and writes the chosen month/year into [ctrl] as
  // 'MM<sep>YYYY', matching the existing hint format for education/experience rows.
  Future<void> _pickMonthYearInto(TextEditingController ctrl, String sep) async {
    DateTime initial = DateTime.now();
    final parts = ctrl.text.trim().split(RegExp(r'[/-]'));
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]);
      final y = int.tryParse(parts[1]);
      if (m != null && y != null && m >= 1 && m <= 12) initial = DateTime(y, m);
    }
    final picked = await _pickDate(initial: initial);
    if (picked != null) {
      setState(() => ctrl.text = '${picked.month.toString().padLeft(2, '0')}$sep${picked.year}');
    }
  }

  // ── File helpers ──────────────────────────────────────────────────────────

  static const _mimeByExt = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
    'gif': 'image/gif', 'webp': 'image/webp', 'heic': 'image/heic',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };

  static String _mimeFromName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return _mimeByExt[ext] ?? 'application/octet-stream';
  }

  // Reads bytes from a picked file.
  // Photos → auto-compressed to ≤200 KB. Documents → rejected if > 1 MB.
  Future<_AttachFile?> _processRawFile(PlatformFile file) async {
    try {
      final rawBytes = file.bytes;
      if (rawBytes == null) throw 'Could not read file';
      var bytes = rawBytes;
      var mime = _mimeFromName(file.name);
      if (mime.startsWith('image/')) {
        // Photos: auto-compress to ≤200 KB
        final compressed = await compressImage(bytes, mime);
        if (compressed != null) { bytes = compressed; mime = 'image/jpeg'; }
      } else {
        final isPdf = mime == 'application/pdf';
        if (isPdf && bytes.length > 500 * 1024) {
          // PDFs: auto-compress toward ≤500 KB (best effort)
          final compressed = await compressPdf(bytes);
          if (compressed != null && compressed.length < bytes.length) bytes = compressed;
        }
        // Reject if still too large after compression (Word docs can't be
        // auto-compressed client-side)
        if (bytes.length > 1024 * 1024) {
          throw 'File too large (${(bytes.length / 1024).round()} KB) even after '
              'compression. Please reduce the file size and re-upload.';
        }
      }
      return _AttachFile(name: file.name, bytes: bytes, mime: mime);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('Could not read "${file.name}": $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ));
      return null;
    }
  }

  // Returns the bare storage path (the bucket is private — see
  // supabase/migrations/20260716000200_document_buckets.sql), or rethrows
  // so callers can surface the error. Reviewers resolve this to a signed
  // URL on demand via SupabaseService.resolveAttachmentUrl.
  Future<String> _uploadSingleFile(_AttachFile file, String path) async {
    await Supabase.instance.client.storage
        .from('onboarding attachments')
        .uploadBinary(path, file.bytes,
            fileOptions: FileOptions(contentType: file.mime));
    return path;
  }

  Future<List<Map<String, dynamic>>> _uploadAttachments(String ts) async {
    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < _attachments.length; i++) {
      for (final file in _attachments[i]) {
        final safeName = file.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
        final path = '$ts/doc${i + 1}_$safeName';
        final url = await _uploadSingleFile(file, path);
        result.add({'doc_type': _docLabels[i], 'name': file.name, 'url': url});
      }
    }
    return result;
  }

  // ── Custom field rendering ────────────────────────────────────────────────

  List<Widget> _renderCustomFields(List<Map<String, dynamic>> fields) {
    return fields.map((field) {
      final id = (field['id'] as String?) ?? field.hashCode.toString();
      final type = (field['type'] as String?) ?? 'short_answer';
      final label = (field['label'] as String?) ?? '';
      final isRequired = (field['required'] as bool?) ?? false;

      if (type == 'photo_upload' || type == 'file_upload') {
        final isPhoto = type == 'photo_upload';
        final fileAccept = isPhoto ? 'image/*' : '.pdf,.doc,.docx,.xls,.xlsx';
        final fileName = _customFileNames[id];
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: fileName != null
                  ? AppTheme.primaryBlue
                  : const Color(0xFFE5E7EB),
              width: fileName != null ? 1.5 : 1,
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Center(
                    child: Icon(Icons.attach_file_rounded,
                        color: Colors.white, size: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$label${isRequired ? ' *' : ''}',
                    style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
            ),
            if (fileName != null) ...[
              Divider(height: 1, color: AppTheme.lightBlue),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(children: [
                    const Icon(Icons.insert_drive_file_rounded,
                        size: 16, color: Color(0xFF22C55E)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(fileName,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF15803D),
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => setState(() {
                        _customFileNames.remove(id);
                        _customFileUrls.remove(id);
                      }),
                      child: Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.close_rounded,
                            size: 13, color: Colors.red),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: AppFilePicker(
                accept: fileAccept,
                onFiles: (rawFiles) async {
                  final f = await _processRawFile(rawFiles.first);
                  if (f == null || !mounted) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not read file. Please try again.'),
                          backgroundColor: Colors.orange));
                    return;
                  }
                  try {
                    final safeName = f.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
                    final url = await _uploadSingleFile(
                        f, '${DateTime.now().millisecondsSinceEpoch}_custom_$safeName');
                    if (mounted) {
                      setState(() {
                        _customFileNames[id] = f.name;
                        _customFileUrls[id] = url;
                      });
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(SnackBar(
                          content: Text('File added: ${f.name}'),
                          backgroundColor: const Color(0xFF22C55E),
                          duration: const Duration(seconds: 3),
                        ));
                    }
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Upload failed: $e'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 6)));
                  }
                },
                builder: (trigger) => OutlinedButton.icon(
                  icon: Icon(
                    isPhoto
                        ? Icons.photo_camera_rounded
                        : Icons.upload_file_rounded,
                    size: 15),
                  label: Text(
                    isPhoto
                        ? (fileName != null ? 'Change Photo' : 'Add Photo')
                        : (fileName != null ? 'Change File' : 'Add File'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryBlue,
                    side: BorderSide(color: AppTheme.primaryBlue),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7)),
                  ),
                  onPressed: trigger,
                ),
              ),
            ),
          ]),
        );
      }

      if (type == 'mcq') {
        final options = (field['options'] as List?)
                ?.whereType<String>()
                .toList() ??
            [];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$label${isRequired ? ' *' : ''}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            ...options.map((opt) => RadioListTile<String>(
                  dense: true,
                  title:
                      Text(opt, style: const TextStyle(fontSize: 13)),
                  value: opt,
                  groupValue: _customMcqValues[id],
                  onChanged: (v) =>
                      setState(() => _customMcqValues[id] = v),
                  activeColor: AppTheme.primaryBlue,
                  contentPadding: EdgeInsets.zero,
                )),
          ]),
        );
      }

      if (type == 'number') {
        _customTextControllers.putIfAbsent(id, () => TextEditingController());
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            controller: _customTextControllers[id],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            validator: isRequired
                ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
                : null,
            decoration: InputDecoration(
              labelText: '$label${isRequired ? ' *' : ''}',
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide:
                      BorderSide(color: AppTheme.primaryBlue, width: 1.5)),
              labelStyle:
                  const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            ),
          ),
        );
      }

      if (type == 'date') {
        final picked = _customDateValues[id];
        final formatted = picked != null
            ? '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}'
            : null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: picked ?? now,
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _customDateValues[id] = d);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: picked != null
                      ? AppTheme.primaryBlue
                      : const Color(0xFFE5E7EB),
                ),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                    formatted ?? '$label${isRequired ? ' *' : ''}',
                    style: TextStyle(
                      fontSize: 13,
                      color: formatted != null
                          ? const Color(0xFF6B7280)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ),
                Icon(Icons.calendar_today_rounded,
                    size: 18,
                    color: picked != null
                        ? AppTheme.primaryBlue
                        : const Color(0xFFE5E7EB)),
              ]),
            ),
          ),
        );
      }

      if (type == 'checkbox') {
        final checked = _customCheckboxValues[id] ?? false;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () =>
                setState(() => _customCheckboxValues[id] = !checked),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: checked
                      ? AppTheme.primaryBlue
                      : const Color(0xFFE5E7EB),
                ),
              ),
              child: Row(children: [
                Icon(
                  checked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: checked
                      ? AppTheme.primaryBlue
                      : const Color(0xFFE5E7EB),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$label${isRequired ? ' *' : ''}',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                ),
              ]),
            ),
          ),
        );
      }

      // Short answer (default)
      _customTextControllers.putIfAbsent(id, () => TextEditingController());
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _customTextControllers[id],
          validator: isRequired
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
          decoration: InputDecoration(
            labelText: '$label${isRequired ? ' *' : ''}',
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(
                    color: AppTheme.primaryBlue, width: 1.5)),
            labelStyle:
                const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
          ),
        ),
      );
    }).toList();
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_cfgEnabled('family_details')) {
      final missing = <int>[];
      for (int i = 0; i < _requiredFamilyRows && i < _familyAadhars.length; i++) {
        if (_familyAadhars[i] == null) missing.add(i + 1);
      }
      if (missing.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Please upload the Aadhar copy for family member${missing.length > 1 ? 's' : ''} ${missing.join(', ')}.'),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }

    if (_cfgEnabled('emergency_details') && _emergencyAadharFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please upload the Aadhar copy in the Emergency Details section.'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    if (_cfgEnabled('attachments')) {
      final missingDocs = _requiredDocIndices
          .where((i) => _attachments[i].isEmpty)
          .map((i) => _docLabels[i])
          .toList();
      if (missingDocs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Please upload: ${missingDocs.join(', ')}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ));
        return;
      }
    }

    if (_cfgEnabled('hr_policy') && !_policyAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please read and agree to the HR Policy before submitting.'),
        backgroundColor: Color(0xFFB91C1C),
      ));
      return;
    }
    if (!_declarationAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please agree to the declaration before submitting.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    if (_saving) return; // guards a double-tap on the submit button
    setState(() => _saving = true);

    // Last-second re-check (token-based flow only) — covers a second tab/
    // window or a resubmit that raced past the page-load check.
    if (_candidateApplicationId != null &&
        await SupabaseService.hasOnboardingFormForCandidate(_candidateApplicationId!)) {
      if (mounted) setState(() { _saving = false; _submitted = true; });
      return;
    }

    final ts = DateTime.now().millisecondsSinceEpoch.toString();

    // Upload family aadhar files
    final familyAadharUrls = <String?>[];
    for (int i = 0; i < _familyAadhars.length; i++) {
      final f = _familyAadhars[i];
      familyAadharUrls.add(f != null
          ? await _uploadSingleFile(f, '$ts/family_aadhar_${i}_${f.name}')
          : null);
    }

    // Upload emergency aadhar
    String? emergencyAadharUrl;
    if (_emergencyAadharFile != null) {
      emergencyAadharUrl = await _uploadSingleFile(
          _emergencyAadharFile!,
          '$ts/emergency_aadhar_${_emergencyAadharFile!.name}');
    }

    // Build family data
    final familyData = _familyRows.asMap().entries.map((e) {
      final i = e.key;
      final row = e.value;
      return {
        'name':       row['name']!.text.trim(),
        'age':        row['age']!.text.trim(),
        'occupation': row['occupation']!.text.trim(),
        'gender':     _familyGenders[i] ?? '',
        'relation':   _familyRelations[i] ?? '',
        'aadhar_url': familyAadharUrls[i] ?? '',
      };
    }).toList();

    final uploadedFiles = await _uploadAttachments(ts);

    final payload = {
      'name':                       _name.text.trim(),
      'phone_number':               _phone.text.trim(),
      'father_name':                _fatherName.text.trim(),
      'mother_name':                _motherName.text.trim(),
      'designation':                _designation.text.trim(),
      'date_of_joining':            _fmt(_dateJoiningDate),
      'full_name':                  _fullName.text.trim(),
      'date_of_birth':              _fmt(_dobDate),
      'postal_address':             _postalAddress.text.trim(),
      'permanent_address':          _permanentAddress.text.trim(),
      'family_details':             familyData,
      'education':                  _educationRows.map(_rowToMap).toList(),
      'experience':                 _experienceRows.map(_rowToMap).toList(),
      'last_reporting_name':        _lastReportingName.text.trim(),
      'last_reporting_designation': _lastReportingDesig.text.trim(),
      'last_company':               _lastCompany.text.trim(),
      'reference1':                 _ref1.text.trim(),
      'reference2':                 _ref2.text.trim(),
      'esi_number':                 _esiNumber.text.trim(),
      'pf_number':                  _pfNumber.text.trim(),
      'languages_known':            _languages.text.trim(),
      'hobbies':                    _hobbies.text.trim(),
      'interests':                  _interests.text.trim(),
      'related_to_employee':        _relatedToEmployee.text.trim(),
      'professional_membership':    _professionalMember.text.trim(),
      'specialized_training':       _specializedTraining.text.trim(),
      'other_information':          _otherInfo.text.trim(),
      'blood_group':                _bloodGroupValue ?? '',
      'allergic_to':                _allergicTo.text.trim(),
      'major_illness':              _majorIllness.text.trim(),
      'emergency_contact_name':     _emergencyName.text.trim(),
      'emergency_contact_number':   _emergencyNumber.text.trim(),
      'emergency_contact_address':  _emergencyAddress.text.trim(),
      'aadhar_url':                 emergencyAadharUrl ?? '',
      'declaration_date':           _fmt(_declarationDateVal),
      'declaration_place':          _declarationPlace.text.trim(),
      'attachments':                uploadedFiles,
      'custom_field_values': {
        ..._customTextControllers
            .map((k, v) => MapEntry(k, v.text.trim())),
        ..._customMcqValues.map((k, v) => MapEntry(k, v ?? '')),
        ..._customFileUrls,
        ...Map.fromEntries(_customDateValues.entries
            .where((e) => e.value != null)
            .map((e) => MapEntry(
                e.key,
                '${e.value!.day.toString().padLeft(2, '0')}/${e.value!.month.toString().padLeft(2, '0')}/${e.value!.year}'))),
        ..._customCheckboxValues,
      },
    };

    try {
      // Store the entire payload as a single JSONB column so new fields
      // added via the form editor never require a SQL migration.
      final editingId = _editingOnboardingFormId;
      if (editingId != null) {
        // Correction resubmission — update the same row rather than insert
        // a new one, and clear the correction flags now that it's back in
        // HR's hands.
        await Supabase.instance.client.from('onboarding_forms').update({
          'name':        payload['name'],
          'phone_number': payload['phone_number'],
          'designation': payload['designation'],
          'form_data':   payload,
          'needs_correction': false,
          'fields_to_correct': <String>[],
        }).eq('id', editingId);
      } else {
        await Supabase.instance.client.from('onboarding_forms').insert({
          'name':        payload['name'],
          'phone_number': payload['phone_number'],
          'designation': payload['designation'],
          'form_data':   payload,
          if (_candidateApplicationId != null) 'candidate_application_id': _candidateApplicationId,
        });
      }
      final candidateId = _candidateApplicationId;
      if (candidateId != null) {
        // Reflects "Onboarding Completed" live in the HR portal via the
        // realtime subscription in interview_process_page.dart.
        await SupabaseService.updateCandidateStatus(candidateId, {
          'onboarding_completed': true,
          'onboarding_completed_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      NotificationService.onboardingFormSubmitted(
        name: (payload['name'] ?? '').toString(),
      );
      if (mounted) setState(() { _saving = false; _submitted = true; });
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error submitting form: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Map<String, dynamic> _rowToMap(Map<String, TextEditingController> row) =>
      row.map((k, v) => MapEntry(k, v.text.trim()));

  @override
  void dispose() {
    for (final c in [
      _name, _phone, _fatherName, _motherName, _designation,
      _fullName, _postalAddress, _permanentAddress,
      _lastReportingName, _lastReportingDesig, _lastCompany, _ref1, _ref2,
      _esiNumber, _pfNumber, _languages, _hobbies, _interests,
      _relatedToEmployee, _professionalMember, _specializedTraining, _otherInfo,
      _allergicTo, _majorIllness,
      _emergencyName, _emergencyNumber, _emergencyAddress,
      _declarationPlace,
    ]) { c.dispose(); }
    for (final row in _familyRows)    { for (final c in row.values) c.dispose(); }
    for (final row in _educationRows) { for (final c in row.values) c.dispose(); }
    for (final row in _experienceRows){ for (final c in row.values) c.dispose(); }
    for (final c in _customTextControllers.values) c.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _buildSuccess();
    return Theme(
      data: ThemeData.light(),
      child: Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Form(
              key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildHeader(),
                if (_flaggedFields.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildCorrectionBanner(),
                ],
                const SizedBox(height: 24),
                ..._orderedSectionWidgets(),
                const SizedBox(height: 28),
                _buildSubmitButton(),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ),
      ),
    ),   // Scaffold
    );   // Theme
  }

  // Shown when this is a correction revisit — everything already entered
  // is prefilled below, this just tells the candidate which parts HR wants
  // them to look at again.
  Widget _buildCorrectionBanner() {
    final labels = _flaggedFields.map((k) => OnboardingFormPage.fieldLabels[k] ?? k).join(', ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, size: 18, color: Colors.orange.shade800),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Your earlier answers are already filled in below. HR asked you to '
            'recheck: $labels. Update those and resubmit — everything else is '
            'kept as you entered it.',
            style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900, height: 1.4),
          ),
        ),
      ]),
    );
  }

  // Returns section widgets in config order, skipping disabled sections.
  // Built-in sections use the config title; custom sections show only custom fields.
  List<Widget> _orderedSectionWidgets() {
    final defaultOrder = [
      'basic_info', 'personal_data', 'family_details', 'education',
      'experience', 'last_position', 'additional_info', 'emergency_details',
      'attachments', 'hr_policy', 'declaration',
    ];
    final Map<String, Widget Function()> builders = {
      'basic_info':        _buildSection1,
      'personal_data':     _buildSection2,
      'family_details':    _buildFamilySection,
      'education':         _buildEducationSection,
      'experience':        _buildExperienceSection,
      'last_position':     _buildLastPositionSection,
      'additional_info':   _buildAdditionalSection,
      'emergency_details': _buildEmergencySection,
      'attachments':       _buildAttachmentsSection,
      'hr_policy':         _buildHRPolicySection,
      'declaration':       _buildDeclarationSection,
    };

    // Use config order if available, else defaults
    final ordered = _configSections.isNotEmpty
        ? _configSections.map((s) => (s['id'] as String?) ?? '').where((id) => id.isNotEmpty).toList()
        : defaultOrder;

    // Append any default sections not yet in config (in case config is partial)
    for (final id in defaultOrder) {
      if (!ordered.contains(id)) ordered.add(id);
    }

    final widgets = <Widget>[];
    for (final id in ordered) {
      if (!_cfgEnabled(id)) continue;
      final builder = builders[id];
      if (builder != null) {
        widgets.add(builder());
      } else {
        // Pure custom section
        final customFields = _cfgCustomFields(id);
        if (customFields.isNotEmpty) {
          widgets.add(_buildCustomOnlySection(id, customFields));
        }
      }
      widgets.add(const SizedBox(height: 20));
    }
    if (widgets.isNotEmpty && widgets.last is SizedBox) widgets.removeLast();
    return widgets;
  }

  Widget _buildCustomOnlySection(
      String id, List<Map<String, dynamic>> customFields) {
    final title = _cfgTitle(id, 'Additional');
    return _card(
      title: title,
      icon: Icons.segment_rounded,
      child: Column(
          children: _renderCustomFields(customFields)),
    );
  }

  Widget _buildSuccess() => Theme(
    data: ThemeData.light(),
    child: Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16)],
          ),
          child: const Column(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 64),
            SizedBox(height: 16),
            Text('Form Submitted Successfully!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
            SizedBox(height: 8),
            Text('Your joining form has been submitted.\nHR will review your details.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
          ]),
        ),
      ]),
    ),
    ),   // Scaffold
  );    // Theme

  Widget _buildHeader() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: LinearGradient(
          colors: [_primary, AppTheme.accentBlue],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Image.asset('assets/images/fomra_logo.png', height: 44),
      const SizedBox(height: 4),
      const Text('(Corporate Office)',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13)),
      const SizedBox(height: 12),
      const Text('EMPLOYEE JOINING FORM',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
    ]),
  );

  // ── Section 1: Basic Info ─────────────────────────────────────────────────

  Widget _buildSection1() => _card(
    title: _cfgTitle('basic_info', 'Basic Information'),
    icon: Icons.person_rounded,
    child: Column(children: [
      _field(_name, 'Name *', required: true),
      _field(_phone, 'Phone Number *', required: true,
          keyboardType: TextInputType.phone, maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
      _field(_fatherName, 'Father Name *', required: true),
      _field(_motherName, 'Mother Name *', required: true),
      _field(_designation, 'Designation *', required: true),
      _dateField(
        label: 'Date of Joining *',
        value: _fmt(_dateJoiningDate),
        required: true,
        onTap: () async {
          final d = await _pickDate(initial: _dateJoiningDate);
          if (d != null) setState(() => _dateJoiningDate = d);
        },
      ),
      ..._renderCustomFields(_cfgCustomFields('basic_info')),
    ]),
  );

  // ── Section 2: Personal Data ──────────────────────────────────────────────

  Widget _buildSection2() => _card(
    title: _cfgTitle('personal_data', 'Personal Data Form'),
    icon: Icons.assignment_ind_rounded,
    child: Column(children: [
      _field(_fullName, 'Full Name *', required: true),
      _dateField(
        label: 'Date of Birth *',
        value: _fmt(_dobDate),
        required: true,
        onTap: () async {
          final d = await _pickDate(
              initial: _dobDate,
              first: DateTime(1950),
              last: DateTime.now());
          if (d != null) setState(() => _dobDate = d);
        },
      ),
      _field(_postalAddress,    'Postal Address *',    required: true, maxLines: 3),
      _field(_permanentAddress, 'Permanent Address *', required: true, maxLines: 3),
      ..._renderCustomFields(_cfgCustomFields('personal_data')),
    ]),
  );

  // ── Family section ────────────────────────────────────────────────────────

  Widget _buildFamilySection() => _card(
    title: _cfgTitle('family_details', 'Family Details'),
    icon: Icons.family_restroom_rounded,
    subtitle: 'First $_requiredFamilyRows members are mandatory',
    child: Column(children: [
      ..._familyRows.asMap().entries.map((e) => _buildFamilyRow(e.key, e.value)),
      const SizedBox(height: 8),
      _addRowButton('Add Family Member', _addFamilyRow),
      ..._renderCustomFields(_cfgCustomFields('family_details')),
    ]),
  );

  Widget _buildFamilyRow(int i, Map<String, TextEditingController> row) {
    final req = i < _requiredFamilyRows;
    return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Member ${i + 1}${req ? ' *' : ''}',
            style: TextStyle(
                fontWeight: FontWeight.w600, color: _primary, fontSize: 13)),
        const Spacer(),
        if (i >= _requiredFamilyRows)
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                color: Colors.red, size: 20),
            onPressed: () => _removeFamilyRow(i),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _field(row['name']!, req ? 'Name *' : 'Name',
            compact: true, required: req)),
        const SizedBox(width: 8),
        Expanded(
          child: _field(row['age']!, req ? 'Age *' : 'Age', compact: true,
              required: req,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _dropdownField(
            value: _familyGenders[i],
            label: req ? 'Gender *' : 'Gender',
            required: req,
            items: const ['Male', 'Female'],
            onChanged: (v) => setState(() => _familyGenders[i] = v),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: _dropdownField(
            value: _familyRelations[i],
            label: req ? 'Relation *' : 'Relation',
            required: req,
            // Siblings and dependants were unrepresentable: an employee with
            // a brother, sister or dependent relative had no option to pick,
            // so the row either went unfilled or was mislabelled as 'Child'.
            items: const [
              'Father',
              'Mother',
              'Spouse',
              'Son',
              'Daughter',
              // Retained: earlier submissions stored 'Child', and a
              // DropdownButtonFormField whose value is absent from its items
              // throws. Five submissions already exist.
              'Child',
              'Brother',
              'Sister',
              'Father-in-law',
              'Mother-in-law',
              'Other',
            ],
            onChanged: (v) => setState(() => _familyRelations[i] = v),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _field(row['occupation']!, req ? 'Occupation *' : 'Occupation',
            compact: true, required: req)),
        const SizedBox(width: 8),
        Expanded(
          child: _fileUploadTile(
            label: req ? 'Aadhar Copy *' : 'Aadhar Copy',
            file: _familyAadhars[i],
            onRawFile: (rawFile) async {
              final f = await _processRawFile(rawFile);
              if (f != null && mounted) setState(() => _familyAadhars[i] = f);
            },
            onRemove: () => setState(() => _familyAadhars[i] = null),
          ),
        ),
      ]),
    ]),
  );
  }

  // ── Education section ─────────────────────────────────────────────────────

  Widget _buildEducationSection() => _card(
    title: _cfgTitle('education', 'Education Qualification'),
    icon: Icons.school_rounded,
    subtitle: 'Start with School, College, Any Certification Course · '
        'First $_requiredEducationRows entries are mandatory',
    child: Column(children: [
      ..._educationRows.asMap().entries.map((e) => _buildEducationRow(e.key, e.value)),
      const SizedBox(height: 8),
      _addRowButton('Add Education', _addEducationRow),
      ..._renderCustomFields(_cfgCustomFields('education')),
    ]),
  );

  Widget _buildEducationRow(int i, Map<String, TextEditingController> row) {
    final req = i < _requiredEducationRows;
    return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Entry ${i + 1}${req ? ' *' : ''}',
            style: TextStyle(
                fontWeight: FontWeight.w600, color: _primary, fontSize: 13)),
        const Spacer(),
        if (i >= _requiredEducationRows)
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                color: Colors.red, size: 20),
            onPressed: () => _removeEducationRow(i),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _field(row['qualification']!, req ? 'Qualification *' : 'Qualification',
            compact: true, required: req)),
        const SizedBox(width: 8),
        Expanded(child: _field(row['university']!, req ? 'University / Institute *' : 'University / Institute',
            compact: true, required: req)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: _field(row['year']!, req ? 'Year of Passing *' : 'Year of Passing', compact: true,
              required: req, hint: 'MM/YYYY', readOnly: true,
              onTap: () => _pickMonthYearInto(row['year']!, '/')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _field(row['marks']!, req ? '% Marks *' : '% Marks', compact: true,
              required: req,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]),
        ),
        const SizedBox(width: 8),
        Expanded(child: _field(row['subject']!, req ? 'Major Subject *' : 'Major Subject',
            compact: true, required: req)),
      ]),
    ]),
  );
  }

  // ── Experience section ────────────────────────────────────────────────────

  Widget _buildExperienceSection() => _card(
    title: _cfgTitle('experience', 'Experience'),
    icon: Icons.work_history_rounded,
    subtitle: 'Chronological order excluding last position',
    child: Column(children: [
      ..._experienceRows.asMap().entries.map((e) => _buildExperienceRow(e.key, e.value)),
      const SizedBox(height: 8),
      _addRowButton('Add Experience', _addExperienceRow),
      ..._renderCustomFields(_cfgCustomFields('experience')),
    ]),
  );

  Widget _buildExperienceRow(int i, Map<String, TextEditingController> row) =>
      Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Experience ${i + 1}',
            style: TextStyle(
                fontWeight: FontWeight.w600, color: _primary, fontSize: 13)),
        const Spacer(),
        if (i > 0)
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                color: Colors.red, size: 20),
            onPressed: () => _removeExperienceRow(i),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ]),
      const SizedBox(height: 8),
      _field(row['organisation']!, 'Organisation', compact: true),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _field(row['from']!, 'Period From', compact: true, hint: 'MM/YYYY',
            readOnly: true, onTap: () => _pickMonthYearInto(row['from']!, '/'))),
        const SizedBox(width: 8),
        Expanded(child: _field(row['to']!,   'Period To',   compact: true, hint: 'MM/YYYY',
            readOnly: true, onTap: () => _pickMonthYearInto(row['to']!, '/'))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _field(row['desig_joining']!,   'Designation at Joining',   compact: true)),
        const SizedBox(width: 8),
        Expanded(child: _field(row['desig_relieving']!, 'Designation at Relieving', compact: true)),
      ]),
      const SizedBox(height: 8),
      _field(row['job_resp']!, 'Job Responsibility', compact: true, maxLines: 2),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _field(row['superior']!, 'Designation of Immediate Superior', compact: true)),
        const SizedBox(width: 8),
        Expanded(
          child: _field(row['salary']!, 'Gross Salary Drawn', compact: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]),
        ),
      ]),
      const SizedBox(height: 8),
      _field(row['reason']!, 'Reason for Leaving', compact: true),
    ]),
  );

  // ── Last Position section ─────────────────────────────────────────────────

  Widget _buildLastPositionSection() => _card(
    title: _cfgTitle('last_position', 'Last Position Held'),
    icon: Icons.business_center_rounded,
    child: Column(children: [
      _field(_lastReportingName,  'Last Reporting Person Name'),
      _field(_lastReportingDesig, 'Last Reporting Person Designation'),
      _field(_lastCompany,        'Last Company Name & Address', maxLines: 2),
      const SizedBox(height: 8),
      const _SectionLabel(label: 'References (from Last Company)'),
      const SizedBox(height: 8),
      _field(_ref1, 'Reference 1 — Name & Contact Number'),
      _field(_ref2, 'Reference 2 — Name & Contact Number'),
      ..._renderCustomFields(_cfgCustomFields('last_position')),
    ]),
  );

  // ── Additional Info section ───────────────────────────────────────────────

  Widget _buildAdditionalSection() => _card(
    title: _cfgTitle('additional_info', 'Additional Information'),
    icon: Icons.info_outline_rounded,
    child: Column(children: [
      Row(children: [
        Expanded(child: _field(_esiNumber, 'ESI Number',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
        const SizedBox(width: 12),
        Expanded(child: _field(_pfNumber,  'PF Number',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
      ]),
      _field(_languages,          'Languages Known'),
      _field(_hobbies,            'Your Hobbies'),
      _field(_interests,          'Interests (Sports / Music / Dance / Singing etc.)'),
      _field(_relatedToEmployee,  'Related to any employee? If yes, name'),
      _field(_professionalMember, 'Membership of any Professional Institution / Association'),
      _field(_specializedTraining,'Any Specialized Training Program attended'),
      _field(_otherInfo,          'Any Other Information / Suggestion', maxLines: 3),
      ..._renderCustomFields(_cfgCustomFields('additional_info')),
    ]),
  );

  // ── Emergency section ─────────────────────────────────────────────────────

  Widget _buildEmergencySection() => _card(
    title: _cfgTitle('emergency_details', 'EMERGENCY DETAILS OF EMPLOYEE'),
    icon: Icons.emergency_rounded,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: _dropdownField(
            value: _bloodGroupValue,
            label: 'Blood Group *',
            required: true,
            items: const ['A+', 'A-', 'A1B+', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'],
            onChanged: (v) => setState(() => _bloodGroupValue = v),
            bottomPad: 12,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _field(_allergicTo, 'Allergic To *', required: true)),
      ]),
      _field(_majorIllness,    'Any Major Illness *', required: true, maxLines: 2),
      _field(_emergencyName,   'Emergency Contact Person Name *', required: true),
      _field(_emergencyNumber, 'Emergency Contact Person Number *', required: true,
          keyboardType: TextInputType.phone, maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
      _field(_emergencyAddress,'Emergency Contact Person Address *', required: true, maxLines: 2),
      // Aadhar Copy upload
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Aadhar Copy *',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(height: 6),
          _fileUploadTile(
            label: 'Upload Aadhar Copy (PDF / image · max 1 MB)',
            file: _emergencyAadharFile,
            onRawFile: (rawFile) async {
              final f = await _processRawFile(rawFile);
              if (f != null && mounted) setState(() => _emergencyAadharFile = f);
            },
            onRemove: () => setState(() => _emergencyAadharFile = null),
            fullWidth: true,
          ),
        ]),
      ),
      ..._renderCustomFields(_cfgCustomFields('emergency_details')),
    ]),
  );

  // ── Attachments section ───────────────────────────────────────────────────

  Widget _buildAttachmentsSection() => _card(
    title: _cfgTitle('attachments', 'Attachments'),
    icon: Icons.attach_file_rounded,
    subtitle: 'PDF / image · Images > 1 MB are auto-compressed · To be given as hard copy also · '
        '* Required (except items 4 & 5)',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...List.generate(_docLabels.length, (i) {
        final files = _attachments[i];
        final req = _requiredDocIndices.contains(i);
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: files.isNotEmpty
                  ? AppTheme.primaryBlue
                  : const Color(0xFFE5E7EB),
              width: files.isNotEmpty ? 1.5 : 1,
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Doc label row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Center(
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(req ? '${_docLabels[i]} *' : _docLabels[i],
                      style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500)),
                ),
              ]),
            ),

            // Uploaded files list
            if (files.isNotEmpty) ...[
              Divider(height: 1, color: AppTheme.lightBlue),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Column(
                  children: files.asMap().entries.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(children: [
                      const Icon(Icons.insert_drive_file_rounded,
                          size: 16, color: Color(0xFF22C55E)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(e.value.name,
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF15803D),
                                fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => setState(
                            () => _attachments[i].removeAt(e.key)),
                        child: Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 13, color: Colors.red),
                        ),
                      ),
                    ]),
                  )).toList(),
                ),
              ),
            ],

            // Upload button
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: AppFilePicker(
                accept: 'image/*,.pdf,.doc,.docx,.xls,.xlsx',
                multiple: true,
                onFiles: (rawFiles) async {
                  for (final rf in rawFiles) {
                    final f = await _processRawFile(rf);
                    if (f != null && mounted) {
                      setState(() => _attachments[i].add(f));
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(SnackBar(
                          content: Text('File added: ${f.name}'),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 3),
                        ));
                    }
                  }
                },
                builder: (trigger) => OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file_rounded, size: 15),
                  label: Text(
                      files.isEmpty ? 'Add File' : 'Add More',
                      style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryBlue,
                    side: BorderSide(color: AppTheme.primaryBlue),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7)),
                  ),
                  onPressed: trigger,
                ),
              ),

            ),
          ]),
        );
      }),
      ..._renderCustomFields(_cfgCustomFields('attachments')),
    ]),
  );

  // ── HR Policy section ─────────────────────────────────────────────────────

  Widget _buildHRPolicySection() {
    final policyText = OnboardingFormConfig.getPolicyTextFromSections(_configSections);
    final sectionTitle = _cfgTitle('hr_policy', 'HR Policy');
    return _card(
      title: sectionTitle,
      icon: Icons.policy_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F8E9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF86EFAC)),
          ),
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF15803D),
                borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: const Row(children: [
                Icon(Icons.menu_book_rounded, color: Colors.white, size: 14),
                SizedBox(width: 8),
                Text('Please read the following HR Policy carefully',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            Container(
              height: 280,
              padding: const EdgeInsets.all(14),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  child: Text(
                    policyText,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2E4024),
                        height: 1.7,
                        fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => setState(() => _policyAgreed = !_policyAgreed),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _policyAgreed
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _policyAgreed
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFF57C00),
                width: 1.5,
              ),
            ),
            child: Row(children: [
              Icon(
                _policyAgreed
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: _policyAgreed
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFF57C00),
                size: 22,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'I have read and agree to the HR Policy  *',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280)),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'This is mandatory. You must accept before submitting the form.',
                    style: TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        ..._renderCustomFields(_cfgCustomFields('hr_policy')),
      ]),
    );
  }

  // ── Declaration section ───────────────────────────────────────────────────

  Widget _buildDeclarationSection() => _card(
    title: _cfgTitle('declaration', 'Declaration'),
    icon: Icons.gavel_rounded,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDE7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFDD835)),
        ),
        child: const Text(
          'I declare that the information given herein above is true & correct to the best of my knowledge & belief & nothing material has been concealed.\n\nI understand that if the above information is found false or incorrect, at any time during the course of my employment, my services will be terminated forthwith without any notice or compensation.',
          style: TextStyle(fontSize: 12, color: Color(0xFF5D4037), height: 1.6),
        ),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: _dateField(
            label: 'Date',
            value: _fmt(_declarationDateVal),
            onTap: () async {
              final d = await _pickDate(initial: _declarationDateVal);
              if (d != null) setState(() => _declarationDateVal = d);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _field(_declarationPlace, 'Place')),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Checkbox(
          value: _declarationAgreed,
          onChanged: (v) => setState(() => _declarationAgreed = v ?? false),
          activeColor: _primary,
        ),
        const Expanded(
          child: Text('I agree to the above declaration',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        ),
      ]),
      ..._renderCustomFields(_cfgCustomFields('declaration')),
    ]),
  );

  Widget _buildSubmitButton() => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      icon: _saving
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
          : const Icon(Icons.send_rounded, size: 18),
      label: Text(_saving ? 'Submitting...' : 'Submit Joining Form',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: _saving ? null : _submit,
    ),
  );

  // ── Shared widget helpers ─────────────────────────────────────────────────

  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
    String? subtitle,
  }) =>
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppTheme.lightBlue),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: _primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827))),
                  if (subtitle != null)
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF6B7280))),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            child,
          ]),
        ),
      );

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? hint,
    bool compact = false,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    bool readOnly = false,
    VoidCallback? onTap,
  }) =>
      Padding(
        padding: EdgeInsets.only(bottom: compact ? 0 : 12),
        child: TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: keyboardType,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          readOnly: readOnly,
          onTap: onTap,
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            counterText: maxLength != null ? '' : null,
            suffixIcon: onTap != null
                ? Icon(Icons.calendar_today_rounded, size: 17, color: _primary)
                : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 10 : 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: _primary, width: 1.5)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Colors.red)),
            labelStyle:
                const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
          ),
        ),
      );

  // Calendar date picker field (read-only, opens date picker on tap)
  Widget _dateField({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool compact = false,
    bool required = false,
  }) =>
      Padding(
        padding: EdgeInsets.only(bottom: compact ? 0 : 12),
        child: GestureDetector(
          onTap: onTap,
          child: AbsorbPointer(
            child: TextFormField(
              readOnly: true,
              controller: TextEditingController(text: value),
              style: const TextStyle(fontSize: 13),
              validator: required
                  ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
                  : null,
              decoration: InputDecoration(
                labelText: label,
                suffixIcon: Icon(Icons.calendar_today_rounded,
                    size: 17, color: _primary),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 12, vertical: compact ? 10 : 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide:
                        BorderSide(color: _primary, width: 1.5)),
                labelStyle:
                    const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
            ),
          ),
        ),
      );

  // Dropdown field
  Widget _dropdownField({
    required String? value,
    required String label,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    double bottomPad = 0,
    bool required = false,
  }) =>
      Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          validator: required
              ? (v) => (v == null || v.isEmpty) ? 'Required' : null
              : null,
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: _primary, width: 1.5)),
            labelStyle:
                const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
          ),
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          items: items
              .map((item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(item),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      );

  // Compact file upload tile (shows filename when picked, upload button otherwise)
  Widget _fileUploadTile({
    required String label,
    required _AttachFile? file,
    required void Function(PlatformFile) onRawFile,
    required VoidCallback onRemove,
    bool fullWidth = false,
    String accept = 'image/*,.pdf',
  }) {
    if (file != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFF4CAF50)),
        ),
        child: Row(children: [
          const Icon(Icons.insert_drive_file_rounded,
              size: 15, color: Color(0xFF22C55E)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(file.name,
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF15803D),
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                size: 16, color: Colors.red),
          ),
        ]),
      );
    }
    return AppFilePicker(
      accept: accept,
      onFiles: (files) => onRawFile(files.first),
      builder: (trigger) => OutlinedButton.icon(
        icon: const Icon(Icons.upload_file_rounded, size: 14),
        label: Text(label,
            style: const TextStyle(fontSize: 11),
            overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: _primary,
          side: BorderSide(color: _primary),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          minimumSize:
              fullWidth ? const Size(double.infinity, 42) : const Size(0, 38),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          alignment: Alignment.centerLeft,
        ),
        onPressed: trigger,
      ),
    );
  }

  Widget _addRowButton(String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        icon: const Icon(Icons.add_rounded, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _primary,
          side: BorderSide(color: _primary),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onTap,
      );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280)));
}
