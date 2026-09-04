import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../theme/app_theme.dart';

/// Where each check-in happened, and how much to trust it.
///
/// Route points were being captured and shown nowhere. More importantly, a
/// "within radius" verdict was previously presented as fact — but a fix with a
/// ±2000 m accuracy radius measured against a 150 m geofence is a coin flip.
/// This screen shows the verdict AND the confidence behind it, so a reader can
/// tell the difference between "definitely on site" and "the phone guessed".
class LocationHistoryPage extends StatefulWidget {
  const LocationHistoryPage({super.key});

  @override
  State<LocationHistoryPage> createState() => _LocationHistoryPageState();
}

class _LocationHistoryPageState extends State<LocationHistoryPage> {
  List<Map<String, dynamic>> _rows = [];
  List<AppUser> _users = [];
  String? _employeeId;
  DateTimeRange? _range;
  bool _loading = true;

  static Color get _c => AppTheme.primaryBlue;

  @override
  void initState() {
    super.initState();
    _range = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 30)),
      end: DateTime.now(),
    );
    _load();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      SupabaseService.fetchLocationHistory(
        employeeId: _employeeId,
        fromIso: _range == null ? null : _iso(_range!.start),
        toIso: _range == null ? null : _iso(_range!.end),
      ),
      UserStore.load(),
    ]);
    if (!mounted) return;
    setState(() {
      _rows = results[0] as List<Map<String, dynamic>>;
      _users = (results[1] as List).cast<AppUser>()
          .where((u) => u.active && u.countsInHeadcount).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _loading = false;
    });
  }

  /// Colour and wording for the confidence in a fix. 'unreliable' means the
  /// accuracy radius exceeds the geofence, so the inside/outside verdict
  /// carries no information.
  (Color, String) _confidence(String? c) => switch (c) {
        'high' => (Colors.green.shade700, 'Accurate fix'),
        'usable' => (Colors.teal.shade600, 'Usable fix'),
        'weak' => (Colors.orange.shade700, 'Weak fix'),
        'unreliable' => (Colors.red.shade600, 'Unreliable — wider than the geofence'),
        _ => (Colors.grey.shade500, 'Accuracy not recorded'),
      };

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;

    return SingleChildScrollView(
      padding: EdgeInsets.all(narrow ? 14 : 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.travel_explore_rounded, color: _c, size: narrow ? 22 : 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Location History',
                style: TextStyle(
                    fontSize: narrow ? 19 : 23,
                    fontWeight: FontWeight.w700,
                    color: _c)),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Where each check-in was recorded, and how reliable the location fix '
          'was. A verdict from a weak fix should not be read as proof.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),

        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: narrow ? double.infinity : 260,
            child: DropdownButtonFormField<String?>(
              initialValue: _employeeId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Employee',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Everyone')),
                ..._users.map((u) => DropdownMenuItem(
                    value: u.employeeId, child: Text(u.name))),
              ],
              onChanged: (v) {
                setState(() => _employeeId = v);
                _load();
              },
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2024),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                initialDateRange: _range,
              );
              if (picked != null) {
                setState(() => _range = picked);
                _load();
              }
            },
            icon: const Icon(Icons.date_range_rounded, size: 16),
            label: Text(_range == null
                ? 'All dates'
                : '${_iso(_range!.start)} to ${_iso(_range!.end)}'),
          ),
        ]),
        const SizedBox(height: 18),

        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'No location records in this range.',
                style: TextStyle(
                    color: Colors.grey.shade500, fontStyle: FontStyle.italic),
              ),
            ),
          )
        else
          ...(_rows.map(_row)),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final within = r['check_in_within_radius'] as bool?;
    final acc = (r['check_in_accuracy'] as num?)?.toDouble();
    final metres = (r['metres_to_nearest_site'] as num?)?.toDouble();
    final (confColor, confLabel) = _confidence(r['check_in_confidence'] as String?);
    final gpsError = (r['check_in_gps_error'] as String?) ?? '';
    final note = (r['check_in_note'] as String?) ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${r['employee_name']}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          Text('${r['date']}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _fact(Icons.login_rounded, 'In ${r['check_in_time'] ?? '—'}'),
          if ((r['check_out_time'] as String?)?.isNotEmpty ?? false)
            _fact(Icons.logout_rounded, 'Out ${r['check_out_time']}'),
          if (metres != null)
            _fact(Icons.straighten_rounded, '${metres.toStringAsFixed(0)} m from site'),
          if (acc != null)
            _fact(Icons.my_location_rounded, '±${acc.toStringAsFixed(0)} m'),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          // The verdict, and immediately beside it how much it is worth.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (within == true ? Colors.green : Colors.orange)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              within == true ? 'At assigned site' : 'Away from site',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: within == true ? Colors.green.shade800 : Colors.orange.shade900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.circle, size: 7, color: confColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(confLabel,
                style: TextStyle(fontSize: 11.5, color: confColor)),
          ),
        ]),
        if (gpsError.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Location failed: $gpsError',
              style: TextStyle(fontSize: 11.5, color: Colors.red.shade700)),
        ],
        if (note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Reason given: $note',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
        ],
      ]),
    );
  }

  Widget _fact(IconData i, String text) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 13, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ]);
}
