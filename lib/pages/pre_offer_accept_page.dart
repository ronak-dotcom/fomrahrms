import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/notification_service.dart';
import '../utils/open_url.dart';
import '../theme/app_theme.dart';

/// Public, unauthenticated page at /pre-offer/{token}. The candidate reaches
/// this from the Pre-Offer email's "Accept Offer" button.
class PreOfferAcceptPage extends StatefulWidget {
  final String token;
  const PreOfferAcceptPage({super.key, required this.token});

  @override
  State<PreOfferAcceptPage> createState() => _PreOfferAcceptPageState();
}

class _PreOfferAcceptPageState extends State<PreOfferAcceptPage> {
  bool _loading = true;
  bool _accepting = false;
  Map<String, dynamic>? _candidate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await SupabaseService.fetchCandidateByPreOfferToken(widget.token);
      if (mounted) setState(() { _candidate = row; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept() async {
    final c = _candidate;
    if (c == null || _accepting) return;
    // Prevent duplicate submissions if already accepted (e.g. double click,
    // or a second tab already accepted it).
    if (c['pre_offer_accepted'] == true) return;

    setState(() => _accepting = true);
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await SupabaseService.acceptPreOffer(widget.token);
      NotificationService.preOfferAccepted(candidateName: (c['name'] as String?) ?? '');
      if (mounted) {
        setState(() {
          _candidate = {...c, 'pre_offer_accepted': true, 'pre_offer_accepted_at': now};
          _accepting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _accepting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not accept offer: $e'),
          backgroundColor: Colors.red,
        ));
      }
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
              constraints: const BoxConstraints(maxWidth: 560),
              child: _loading ? _loadingCard() : (_candidate == null ? _invalidCard() : _offerCard(_candidate!)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loadingCard() => const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(child: CircularProgressIndicator()),
      );

  Widget _invalidCard() => _card(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.link_off_rounded, size: 48, color: Color(0xFF9CA3AF)),
          SizedBox(height: 16),
          Text('Invalid or Expired Link',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
          SizedBox(height: 8),
          Text('This offer link is not valid. Please contact HR for assistance.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
        ]),
      );

  Widget _offerCard(Map<String, dynamic> c) {
    final name = (c['name'] as String?) ?? '';
    final designation = (c['designation'] as String?) ?? '';
    final department = (c['department'] as String?) ?? '';
    final accepted = c['pre_offer_accepted'] == true;
    final candidateId = c['id'].toString();

    return Column(children: [
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Image.asset('assets/images/fomra_logo.png', height: 40),
          const SizedBox(height: 20),
          Text('Dear $name,',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
          const SizedBox(height: 10),
          Text(
            'We are pleased to offer you the position of '
            '${designation.isNotEmpty ? designation : 'the role you interviewed for'}'
            '${department.isNotEmpty ? ' in the $department department' : ''} '
            'at Fomra Housing & Infrastructure Pvt Ltd.',
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF374151), height: 1.6),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              final url = await SupabaseService.preOfferPdfUrl(candidateId);
              if (url != null) openUrl(url);
            },
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
            label: const Text('View Pre-Offer Letter (PDF)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryBlue,
              side: BorderSide(color: AppTheme.primaryBlue),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 24),
          if (accepted) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: const [
                Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Offer Already Accepted.',
                      style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
              ]),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _accepting ? null : _accept,
                icon: _accepting
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(_accepting ? 'Accepting…' : 'I Accept the Offer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ]),
      ),
    ]);
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: child,
      );
}
