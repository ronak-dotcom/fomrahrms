import 'package:flutter/material.dart';

import '../l10n/staff_strings.dart';
import '../services/error_reporter.dart';
import '../theme/app_theme.dart';

/// "Report a problem": sends a description, the current screen and
/// (optionally) a picture of it to Management's App Health page, so an
/// issue does not have to travel by screenshot. Who sent it is taken from
/// the signed-in session.
class ReportProblemButton extends StatelessWidget {
  /// White icon for the blue shell header; dark for light app bars.
  final Color? color;
  final EdgeInsetsGeometry padding;
  final Decoration? decoration;

  const ReportProblemButton({
    super.key,
    this.color,
    this.padding = const EdgeInsets.all(8),
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: st('report_problem'),
      child: InkWell(
        onTap: () => showReportProblemDialog(context),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: padding,
          decoration: decoration,
          child: Icon(Icons.bug_report_outlined, size: 22, color: color),
        ),
      ),
    );
  }
}

/// Captures the screen first, then asks what went wrong.
Future<void> showReportProblemDialog(BuildContext context) async {
  final screen = ErrorReporter.currentScreen;
  final capture = await ErrorReporter.captureScreen();
  if (!context.mounted) return;
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ReportProblemDialog(screen: screen, capture: capture),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(st('report_sent')),
    ));
  }
}

class _ReportProblemDialog extends StatefulWidget {
  final String screen;
  final ScreenCapture? capture;
  const _ReportProblemDialog({required this.screen, required this.capture});

  @override
  State<_ReportProblemDialog> createState() => _ReportProblemDialogState();
}

class _ReportProblemDialogState extends State<_ReportProblemDialog> {
  final _note = TextEditingController();
  late bool _attach = widget.capture != null;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final note = _note.text.trim();
    if (note.isEmpty) {
      setState(() => _error = st('report_describe'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final error = await ErrorReporter.reportProblem(
      note: note,
      screen: widget.screen,
      screenshot: _attach ? widget.capture : null,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _sending = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final capture = widget.capture;
    return AlertDialog(
      title: Text(st('report_problem')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(st('report_intro'),
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                enabled: !_sending,
                decoration: InputDecoration(
                  hintText: st('report_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (widget.screen.isNotEmpty)
                Text('${st('report_screen')}: ${widget.screen}',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              if (capture != null) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _attach,
                  onChanged: _sending ? null : (v) => setState(() => _attach = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(st('report_attach')),
                ),
                if (_attach)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: Image.memory(capture.bytes, fit: BoxFit.contain),
                    ),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: AppTheme.error, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: Text(st('cancel')),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(st('report_send')),
        ),
      ],
    );
  }
}
