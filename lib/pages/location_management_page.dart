import 'package:flutter/material.dart';
import '../constants/org_lists.dart';
import '../models/app_user.dart';
import '../models/attendance_location.dart';
import '../models/attendance_policy_store.dart';
import '../services/gps_tracking_service.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../utils/location_consent.dart';
import '../widgets/back_button.dart';
import '../widgets/office_timings_panel.dart';
import '../theme/app_theme.dart';

/// HR/Management admin hub: Locations, Attendance Policies, per-employee
/// Location/policy assignments, and (as its 4th tab) Office Timings.
/// Everything here is data-driven — see lib/models/attendance_policy_store.dart
/// for the resolver check_in_page.dart/check_out_page.dart use, and
/// supabase/migrations/20260718030000_location_management.sql for the schema.
class LocationManagementPage extends StatefulWidget {
  const LocationManagementPage({super.key});

  @override
  State<LocationManagementPage> createState() => _LocationManagementPageState();
}

class _LocationManagementPageState extends State<LocationManagementPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    AttendancePolicyStore.invalidate();
    await AttendancePolicyStore.refresh();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: null,
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Row(children: [
            const NavBackButton(),
            const SizedBox(width: 8),
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.location_on_rounded, color: AppTheme.primaryBlue, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text('Location Management',
                style: Theme.of(context).textTheme.headlineMedium)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Text(
            'Manage physical locations, attendance policies, per-employee assignments, and '
            'working hours — every change here takes effect on the next check-in, no app update needed.',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
          ),
        ),
        const SizedBox(height: 12),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Locations'),
            Tab(text: 'Attendance Policies'),
            Tab(text: 'Employee Assignments'),
            Tab(text: 'Office Timings'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(controller: _tabController, children: [
                  _LocationsTab(onChanged: _load),
                  _PoliciesTab(onChanged: _load),
                  _EmployeeAssignmentsTab(onChanged: _load),
                  const OfficeTimingsPanel(),
                ]),
        ),
      ]),
    );
  }
}

// ── Tab 1: Locations ─────────────────────────────────────────────────────────

class _LocationsTab extends StatelessWidget {
  final VoidCallback onChanged;
  const _LocationsTab({required this.onChanged});

  Future<void> _openEditor(BuildContext context, {OfficeLocation? existing}) async {
    final result = await showDialog<OfficeLocation>(
      context: context,
      builder: (_) => _LocationDialog(existing: existing),
    );
    if (result == null) return;
    final error = await SupabaseService.saveLocation(result);
    if (error != null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Save failed: $error'), backgroundColor: Colors.red.shade700,
      ));
      return;
    }
    onChanged();
  }

  Future<void> _toggleActive(BuildContext context, OfficeLocation loc) async {
    final updated = OfficeLocation(
      id: loc.id, name: loc.name, address: loc.address,
      latitude: loc.latitude, longitude: loc.longitude,
      radiusMeters: loc.radiusMeters, type: loc.type, active: !loc.active,
    );
    await SupabaseService.saveLocation(updated);
    onChanged();
  }

  Future<void> _delete(BuildContext context, OfficeLocation loc) async {
    final assignedCount = AttendancePolicyStore.employeesFor(loc.id).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Location'),
        content: Text(assignedCount > 0
            ? 'Delete "${loc.name}"? It\'s currently assigned to $assignedCount employee(s) — '
              "they'll lose this location and may need a note to check in until reassigned."
            : 'Delete "${loc.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await SupabaseService.deleteLocation(loc.id);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Delete failed: $error'), backgroundColor: Colors.red.shade700,
      ));
      return;
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final locations = AttendancePolicyStore.allLocations;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Locations', style: Theme.of(context).textTheme.titleLarge)),
          ElevatedButton.icon(
            onPressed: () => _openEditor(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Location'),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'Every office, branch, or client site employees may be required to check in/out near. '
          'Deactivating a location removes it from geofencing without deleting assignment history.',
          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
        ),
        const SizedBox(height: 20),
        if (locations.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text('No locations yet — add one to get started.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
            ),
          )
        else
          for (final loc in locations)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _LocationCard(
                location: loc,
                assignedCount: AttendancePolicyStore.employeesFor(loc.id).length,
                onEdit: () => _openEditor(context, existing: loc),
                onDelete: () => _delete(context, loc),
                onToggleActive: () => _toggleActive(context, loc),
              ),
            ),
      ]),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final OfficeLocation location;
  final int assignedCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;
  const _LocationCard({
    required this.location, required this.assignedCount,
    required this.onEdit, required this.onDelete, required this.onToggleActive,
  });

  Widget _stat(BuildContext context, IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Row(children: [
                Flexible(
                  child: Text(location.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(location.type,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue)),
                ),
                if (!location.active) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Inactive',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                  ),
                ],
              ]),
            ),
            Switch(value: location.active, onChanged: (_) => onToggleActive()),
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_rounded, size: 19),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline_rounded, size: 19, color: Colors.red.shade600),
              onPressed: onDelete,
            ),
          ]),
          if (location.address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(location.address,
                style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 8, children: [
            _stat(context, Icons.my_location_rounded,
                '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}'),
            _stat(context, Icons.radio_button_checked_rounded, '${location.radiusMeters}m radius'),
            _stat(context, Icons.people_alt_rounded,
                '$assignedCount ${assignedCount == 1 ? 'employee' : 'employees'} assigned'),
          ]),
        ]),
      ),
    );
  }
}

class _LocationDialog extends StatefulWidget {
  final OfficeLocation? existing;
  const _LocationDialog({this.existing});

  @override
  State<_LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends State<_LocationDialog> {
  static const _typePresets = ['Office', 'Branch', 'Client Site', 'Other'];

  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  late final TextEditingController _radiusCtrl;
  late final TextEditingController _typeCtrl;
  late bool _active;
  bool _locating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final l = widget.existing;
    _nameCtrl = TextEditingController(text: l?.name ?? '');
    _addressCtrl = TextEditingController(text: l?.address ?? '');
    _latCtrl = TextEditingController(text: l != null ? l.latitude.toString() : '');
    _lngCtrl = TextEditingController(text: l != null ? l.longitude.toString() : '');
    _radiusCtrl = TextEditingController(text: (l?.radiusMeters ?? 30).toString());
    _typeCtrl = TextEditingController(text: l?.type ?? 'Office');
    _active = l?.active ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    _typeCtrl.dispose();
    super.dispose();
  }

  /// Pulls coordinates out of a pasted Google Maps link.
  ///
  /// Typing latitude and longitude by hand means reading them off a map and
  /// transcribing 12 digits, and a single wrong digit puts the office in the
  /// wrong place with no obvious sign anything is wrong. Pasting the link is
  /// the way people actually have the location to hand.
  ///
  /// Handles the common shapes:
  ///   .../@13.0850,80.2227,17z          — map centre
  ///   ...!3d13.0850!4d80.2227           — the place itself
  ///   ...?q=13.0850,80.2227             — query form
  ///   ...&ll=13.0850,80.2227
  /// A shortened maps.app.goo.gl link carries no coordinates at all until it
  /// is opened, so that is reported rather than silently failing.
  static ({double lat, double lng})? _parseMapsLink(String url) {
    final u = url.trim();
    if (u.isEmpty) return null;

    // !3d<lat>!4d<lng> is the actual pin, so it wins over the map centre.
    final place = RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)').firstMatch(u);
    if (place != null) {
      return (lat: double.parse(place.group(1)!), lng: double.parse(place.group(2)!));
    }
    for (final re in [
      RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'[?&](?:q|ll|daddr|center)=(-?\d+\.\d+),\s*(-?\d+\.\d+)'),
      RegExp(r'^\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*$'),  // bare lat, lng
    ]) {
      final m = re.firstMatch(u);
      if (m != null) {
        return (lat: double.parse(m.group(1)!), lng: double.parse(m.group(2)!));
      }
    }
    return null;
  }

  Future<void> _pasteMapsLink() async {
    final ctrl = TextEditingController();
    final link = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste Google Maps link'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Open the place in Google Maps, tap Share, copy the link and paste '
            'it here. A plain "latitude, longitude" also works.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
                hintText: 'https://www.google.com/maps/...',
                border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Use this')),
        ],
      ),
    );
    if (link == null || !mounted) return;

    final coords = _parseMapsLink(link);
    setState(() {
      if (coords == null) {
        _error = link.contains('goo.gl') || link.contains('maps.app')
            ? 'That is a shortened link, which does not contain the '
              'coordinates. Open it in Google Maps first, then copy the full '
              'link from the address bar.'
            : 'Could not find coordinates in that link. Paste the full Google '
              'Maps URL, or type "latitude, longitude".';
      } else {
        _latCtrl.text = coords.lat.toString();
        _lngCtrl.text = coords.lng.toString();
        _error = null;
      }
    });
  }

  Future<void> _useCurrentLocation() async {
    await ensureLocationConsent(context);
    if (!mounted) return;
    setState(() => _locating = true);
    final pos = await GpsTrackingService.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (pos != null) {
        _latCtrl.text = pos.latitude.toString();
        _lngCtrl.text = pos.longitude.toString();
      } else {
        _error = "Couldn't read your current location. Please enter coordinates manually.";
      }
    });
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a name for this location.');
      return;
    }
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lat < -90 || lat > 90) {
      setState(() => _error = 'Latitude must be a number between -90 and 90.');
      return;
    }
    if (lng == null || lng < -180 || lng > 180) {
      setState(() => _error = 'Longitude must be a number between -180 and 180.');
      return;
    }
    final radius = int.tryParse(_radiusCtrl.text.trim());
    if (radius == null || radius <= 0) {
      setState(() => _error = 'Radius must be a positive whole number of meters.');
      return;
    }
    final type = _typeCtrl.text.trim().isEmpty ? 'Office' : _typeCtrl.text.trim();
    Navigator.pop(context, OfficeLocation(
      id: widget.existing?.id ?? '',
      name: name,
      address: _addressCtrl.text.trim(),
      latitude: lat,
      longitude: lng,
      radiusMeters: radius,
      type: type,
      active: _active,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(widget.existing == null ? 'Add Location' : 'Edit Location'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Head Office'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Address (optional)'),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 6, children: _typePresets.map((t) {
              final selected = _typeCtrl.text == t;
              return ChoiceChip(
                label: Text(t, style: const TextStyle(fontSize: 12.5)),
                selected: selected,
                onSelected: (_) => setState(() => _typeCtrl.text = t),
              );
            }).toList()),
            const SizedBox(height: 8),
            TextField(
              controller: _typeCtrl,
              decoration: const InputDecoration(labelText: 'Type', hintText: 'Office / Branch / Client Site / ...'),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _latCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lngCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _locating ? null : _useCurrentLocation,
              icon: _locating
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded, size: 16),
              label: Text(_locating ? 'Locating…' : 'Use current GPS location'),
            ),
            // Pasting the link beats transcribing 12 digits off a map, where a
            // single wrong digit puts the site somewhere else with nothing on
            // screen to show it.
            OutlinedButton.icon(
              onPressed: _pasteMapsLink,
              icon: const Icon(Icons.link_rounded, size: 16),
              label: const Text('Paste Google Maps link'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _radiusCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Allowed radius (meters)'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active', style: TextStyle(fontSize: 13.5)),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// ── Tab 2: Attendance Policies ───────────────────────────────────────────────

class _PoliciesTab extends StatelessWidget {
  final VoidCallback onChanged;
  const _PoliciesTab({required this.onChanged});

  Future<void> _openEditor(BuildContext context, {AttendancePolicy? existing}) async {
    final assigned = existing != null
        ? AttendancePolicyStore.departmentsFor(existing.id).toSet()
        : <String>{};
    final result = await showDialog<_PolicyDraft>(
      context: context,
      builder: (_) => _PolicyDialog(existing: existing, initialAssigned: assigned),
    );
    if (result == null) return;

    final policy = AttendancePolicy(
      id: existing?.id ?? '',
      name: result.name,
      policyType: result.policyType,
      noteRequiredOutsideRadius: result.noteRequiredOutsideRadius,
    );
    final error = await SupabaseService.saveAttendancePolicy(policy);
    if (error != null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Save failed: $error'), backgroundColor: Colors.red.shade700,
      ));
      return;
    }

    // Existing policies keep their id immediately; new ones need a reload
    // to learn the server-generated id before department assignments can
    // reference it.
    String policyId = existing?.id ?? '';
    if (policyId.isEmpty) {
      await AttendancePolicyStore.refresh();
      final match = AttendancePolicyStore.allPolicies.where((p) => p.name == result.name);
      if (match.isEmpty) {
        onChanged();
        return;
      }
      policyId = match.first.id;
    }

    for (final d in result.assignedDepartments.difference(assigned)) {
      await SupabaseService.assignDepartmentPolicy(d, policyId);
    }
    for (final d in assigned.difference(result.assignedDepartments)) {
      await SupabaseService.unassignDepartmentPolicy(d);
    }

    onChanged();
  }

  Future<void> _delete(BuildContext context, AttendancePolicy policy) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Attendance Policy'),
        content: Text('Delete "${policy.name}"? This fails if it\'s still used as a fallback, '
            'department assignment, or employee override.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await SupabaseService.deleteAttendancePolicy(policy.id);
    if (error != null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Can't delete — this policy is still in use."), backgroundColor: Colors.red.shade700,
      ));
      return;
    }
    onChanged();
  }

  Future<void> _setFallback(String workLocation, String policyId) async {
    await SupabaseService.setFallbackPolicy(workLocation, policyId);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final policies = AttendancePolicyStore.allPolicies;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Attendance Policies', style: Theme.of(context).textTheme.titleLarge)),
          ElevatedButton.icon(
            onPressed: () => _openEditor(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Policy'),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'A policy defines how many locations an employee may be assigned and whether being '
          'outside all of them requires a note. Assign policies to departments below, or override '
          'one specific employee from the Employee Assignments tab.',
          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
        ),
        const SizedBox(height: 20),
        if (policies.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Default policy by work location',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text('Used when an employee\'s department has no explicit policy assignment.',
                    style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _FallbackDropdown(
                      label: 'Office employees',
                      policies: _policiesForWorkLocation(policies, office: true),
                      selectedId: _fallbackFor(policies, 'Office'),
                      onChanged: (id) => _setFallback('Office', id),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FallbackDropdown(
                      label: 'Onsite employees',
                      policies: _policiesForWorkLocation(policies, office: false),
                      selectedId: _fallbackFor(policies, 'Onsite'),
                      onChanged: (id) => _setFallback('Onsite', id),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (policies.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text('No policies yet — add one to get started.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
            ),
          )
        else
          for (final p in policies)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PolicyCard(
                policy: p,
                assignedDepartments: AttendancePolicyStore.departmentsFor(p.id),
                fallbackWorkLocations: AttendancePolicyStore.fallbackWorkLocationsFor(p.id),
                onEdit: () => _openEditor(context, existing: p),
                onDelete: () => _delete(context, p),
              ),
            ),
      ]),
    );
  }

  String? _fallbackFor(List<AttendancePolicy> policies, String workLocation) {
    final match = policies.where((p) => AttendancePolicyStore.fallbackWorkLocationsFor(p.id).contains(workLocation));
    return match.isEmpty ? null : match.first.id;
  }

  // Office employees only ever need a single fixed point (the "Office"
  // policy); onsite/field employees choose between Restricted and
  // Unrestricted Check-in. Scoping each dropdown to just its relevant
  // policies keeps the two from mixing — picking "Office" for a field
  // employee (or vice versa) never made sense anyway.
  List<AttendancePolicy> _policiesForWorkLocation(List<AttendancePolicy> policies, {required bool office}) {
    final scoped = policies.where((p) =>
        office == (p.policyType == AttendancePolicyType.singleLocation)).toList();
    return scoped.isEmpty ? policies : scoped;
  }
}

class _FallbackDropdown extends StatelessWidget {
  final String label;
  final List<AttendancePolicy> policies;
  final String? selectedId;
  final ValueChanged<String> onChanged;
  const _FallbackDropdown({
    required this.label, required this.policies, required this.selectedId, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Guards against a DropdownButtonFormField assertion crash if the
    // currently-selected policy isn't in this (possibly scoped) list.
    final value = policies.any((p) => p.id == selectedId) ? selectedId : null;
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label, isDense: true),
      borderRadius: BorderRadius.circular(AppTheme.controlRadius),
      dropdownColor: AppTheme.white,
      elevation: 3,
      items: [
        for (final p in policies)
          DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _PolicyCard extends StatelessWidget {
  final AttendancePolicy policy;
  final List<String> assignedDepartments;
  final List<String> fallbackWorkLocations;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _PolicyCard({
    required this.policy, required this.assignedDepartments, required this.fallbackWorkLocations,
    required this.onEdit, required this.onDelete,
  });

  Color get _typeColor {
    switch (policy.policyType) {
      case AttendancePolicyType.singleLocation:
        return AppTheme.primaryBlue;
      case AttendancePolicyType.multiLocation:
        return Colors.teal;
      case AttendancePolicyType.unrestricted:
        return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Row(children: [
                Flexible(
                  child: Text(policy.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(policyTypeLabel(policy.policyType),
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _typeColor)),
                ),
              ]),
            ),
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_rounded, size: 19),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline_rounded, size: 19, color: Colors.red.shade600),
              onPressed: onDelete,
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(
              policy.requiresLocation
                  ? (policy.noteRequiredOutsideRadius ? Icons.edit_note_rounded : Icons.block_rounded)
                  : Icons.explore_rounded,
              size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                policy.requiresLocation
                    ? (policy.noteRequiredOutsideRadius
                        ? 'Outside all assigned locations requires a note'
                        : 'Outside all assigned locations — no note required')
                    : 'No location restriction — GPS always recorded',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
              ),
            ),
          ]),
          if (assignedDepartments.isNotEmpty || fallbackWorkLocations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in assignedDepartments)
                _chip(context, d, AppTheme.primaryBlue),
              for (final w in fallbackWorkLocations)
                _chip(context, 'Fallback: $w', Colors.orange.shade700),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
      );
}

class _PolicyDraft {
  final String name;
  final AttendancePolicyType policyType;
  final bool noteRequiredOutsideRadius;
  final Set<String> assignedDepartments;
  const _PolicyDraft({
    required this.name, required this.policyType,
    required this.noteRequiredOutsideRadius, required this.assignedDepartments,
  });
}

class _PolicyDialog extends StatefulWidget {
  final AttendancePolicy? existing;
  final Set<String> initialAssigned;
  const _PolicyDialog({this.existing, required this.initialAssigned});

  @override
  State<_PolicyDialog> createState() => _PolicyDialogState();
}

class _PolicyDialogState extends State<_PolicyDialog> {
  late final TextEditingController _nameCtrl;
  late AttendancePolicyType _policyType;
  late bool _noteRequired;
  late Set<String> _selectedDepartments;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _policyType = p?.policyType ?? AttendancePolicyType.singleLocation;
    _noteRequired = p?.noteRequiredOutsideRadius ?? true;
    _selectedDepartments = Set<String>.from(widget.initialAssigned);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a name for this policy.');
      return;
    }
    Navigator.pop(context, _PolicyDraft(
      name: name,
      policyType: _policyType,
      noteRequiredOutsideRadius: _policyType == AttendancePolicyType.unrestricted ? false : _noteRequired,
      assignedDepartments: _selectedDepartments,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(widget.existing == null ? 'Add Attendance Policy' : 'Edit Attendance Policy'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Sales Field Staff'),
            ),
            const SizedBox(height: 16),
            Text('Policy type', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final t in AttendancePolicyType.values)
              RadioListTile<AttendancePolicyType>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: t,
                groupValue: _policyType,
                onChanged: (v) => setState(() => _policyType = v!),
                title: Text(policyTypeLabel(t), style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  switch (t) {
                    AttendancePolicyType.singleLocation => 'Employee is assigned exactly one location',
                    AttendancePolicyType.multiLocation => 'Employee may be assigned several locations',
                    AttendancePolicyType.unrestricted => 'No location restriction; GPS still always recorded',
                  },
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            if (_policyType != AttendancePolicyType.unrestricted) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Require a note when outside all assigned locations',
                    style: TextStyle(fontSize: 13)),
                value: _noteRequired,
                onChanged: (v) => setState(() => _noteRequired = v),
              ),
            ],
            const SizedBox(height: 14),
            Text('Assign to departments',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Checking a department moves it off any other policy it was assigned to.',
                style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: kDepartments.map((d) {
              final selected = _selectedDepartments.contains(d);
              return FilterChip(
                label: Text(d, style: const TextStyle(fontSize: 12.5)),
                selected: selected,
                onSelected: (v) => setState(() {
                  if (v) {
                    _selectedDepartments.add(d);
                  } else {
                    _selectedDepartments.remove(d);
                  }
                }),
              );
            }).toList()),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// ── Tab 3: Employee Assignments ──────────────────────────────────────────────

class _EmployeeAssignmentsTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _EmployeeAssignmentsTab({required this.onChanged});

  @override
  State<_EmployeeAssignmentsTab> createState() => _EmployeeAssignmentsTabState();
}

class _EmployeeAssignmentsTabState extends State<_EmployeeAssignmentsTab> {
  bool _loading = true;
  List<AppUser> _users = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await UserStore.load();
    if (!mounted) return;
    setState(() {
      _users = all.where((u) => u.active && !kStaffPortalDepartments.contains(u.department)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _loading = false;
    });
  }

  Future<void> _openEditor(AppUser user) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _EmployeePolicyDialog(user: user),
    );
    widget.onChanged();
    if (mounted) setState(() {}); // re-render with the store's fresh assignments
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.trim().isEmpty
        ? _users
        : _users.where((u) =>
            u.name.toLowerCase().contains(_search.toLowerCase()) ||
            u.department.toLowerCase().contains(_search.toLowerCase())).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Employee Assignments', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          "Assign specific Locations to Single/Multi-Location employees, or override one "
          "employee's policy entirely. Everyone else inherits their department's policy.",
          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: InputDecoration(
            hintText: 'Search by name or department',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text('No employees found',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _EmployeeAssignmentRow(
                        user: filtered[i],
                        onTap: () => _openEditor(filtered[i]),
                      ),
                    ),
        ),
      ]),
    );
  }
}

class _EmployeeAssignmentRow extends StatelessWidget {
  final AppUser user;
  final VoidCallback onTap;
  const _EmployeeAssignmentRow({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final policy = AttendancePolicyStore.policyForUser(user);
    final isOverride = AttendancePolicyStore.hasEmployeeOverride(user.employeeId);
    final locationCount = AttendancePolicyStore.locationIdsFor(user.employeeId).length;
    final provenance = isOverride
        ? 'Override'
        : AttendancePolicyStore.hasDepartmentAssignment(user.department)
            ? user.department
            : 'Default (${user.workLocation.isEmpty ? '—' : user.workLocation})';

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${user.department} · ${user.workLocation.isEmpty ? 'Not set' : user.workLocation}',
                    style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
              ]),
            ),
            Expanded(
              flex: 2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(policy.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('via $provenance',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
              ]),
            ),
            if (policy.requiresLocation)
              Expanded(
                child: Text('$locationCount ${locationCount == 1 ? 'location' : 'locations'}',
                    style: const TextStyle(fontSize: 12)),
              )
            else
              const Expanded(child: Text('Unrestricted', style: TextStyle(fontSize: 12))),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ]),
        ),
      ),
    );
  }
}

class _EmployeePolicyDialog extends StatefulWidget {
  final AppUser user;
  const _EmployeePolicyDialog({required this.user});

  @override
  State<_EmployeePolicyDialog> createState() => _EmployeePolicyDialogState();
}

class _EmployeePolicyDialogState extends State<_EmployeePolicyDialog> {
  late String? _overridePolicyId;
  late Set<String> _selectedLocationIds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _overridePolicyId = AttendancePolicyStore.hasEmployeeOverride(widget.user.employeeId)
        ? AttendancePolicyStore.policyForUser(widget.user).id
        : null;
    _selectedLocationIds = AttendancePolicyStore.locationIdsFor(widget.user.employeeId).toSet();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    if (_overridePolicyId == null) {
      await SupabaseService.clearEmployeePolicyOverride(widget.user.employeeId);
    } else {
      await SupabaseService.setEmployeePolicyOverride(widget.user.employeeId, _overridePolicyId!);
    }
    await SupabaseService.setEmployeeLocations(widget.user.employeeId, _selectedLocationIds.toList());
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final policies = AttendancePolicyStore.allPolicies;
    final inheritedPolicy = AttendancePolicyStore.inheritedPolicy(
      department: widget.user.department,
      workLocation: widget.user.workLocation,
    );
    final overrideMatch = policies.where((p) => p.id == _overridePolicyId);
    final effectivePolicy =
        _overridePolicyId == null || overrideMatch.isEmpty ? inheritedPolicy : overrideMatch.first;
    final locations = AttendancePolicyStore.activeLocations;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(widget.user.name),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${widget.user.department} · ${widget.user.workLocation.isEmpty ? 'Work location not set' : widget.user.workLocation}',
                style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 16),
            Text('Policy override', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Leave as "Inherit" to use the department/default policy.',
                style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: _overridePolicyId,
              decoration: const InputDecoration(isDense: true),
              borderRadius: BorderRadius.circular(AppTheme.controlRadius),
              dropdownColor: AppTheme.white,
              elevation: 3,
              items: [
                DropdownMenuItem<String?>(value: null, child: Text('Inherit (${inheritedPolicy.name})')),
                for (final p in policies)
                  DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _overridePolicyId = v),
            ),
            const SizedBox(height: 18),
            if (effectivePolicy.requiresLocation) ...[
              Text('Assigned locations',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                effectivePolicy.policyType == AttendancePolicyType.singleLocation
                    ? 'Pick the one location this employee checks in/out from.'
                    : 'Pick every location this employee may check in/out from.',
                style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 8),
              if (locations.isEmpty)
                Text('No active locations yet — add one from the Locations tab.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.orange.shade700))
              else
                Wrap(spacing: 6, runSpacing: 6, children: locations.map((l) {
                  final selected = _selectedLocationIds.contains(l.id);
                  return FilterChip(
                    label: Text(l.name, style: const TextStyle(fontSize: 12.5)),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (effectivePolicy.policyType == AttendancePolicyType.singleLocation) {
                        _selectedLocationIds
                          ..clear()
                          ..addAll(v ? [l.id] : []);
                      } else if (v) {
                        _selectedLocationIds.add(l.id);
                      } else {
                        _selectedLocationIds.remove(l.id);
                      }
                    }),
                  );
                }).toList()),
            ] else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'This policy has no location restriction — no assignment needed.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
