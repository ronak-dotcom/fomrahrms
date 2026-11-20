import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Building blocks for the phone redesign (approved 19 Nov 2026): white cards
/// with a hairline border on a light grey page, small uppercase section
/// labels, and colour used only for status.
class MobileUi {
  MobileUi._();

  static const line = Color(0xFFE5E9F2);
  static const radius = 16.0;

  // Status colours: present, late, leave, permission, off / holiday, LOP.
  static const present = Color(0xFF15803D);
  static const presentBg = Color(0xFFE9F7EE);
  static const late = Color(0xFFB45309);
  static const lateBg = Color(0xFFFEF3E2);
  static const leave = Color(0xFF6D28D9);
  static const leaveBg = Color(0xFFF1EBFF);
  static const permission = Color(0xFF1D4ED8);
  static const permissionBg = Color(0xFFEEF3FF);
  static const off = Color(0xFF94A3B8);
  static const lop = Color(0xFFB91C1C);
  static const lopBg = Color(0xFFFDECEC);
}

class MCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  const MCard({super.key, required this.child, this.padding = const EdgeInsets.all(14),
      this.color, this.borderColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MobileUi.radius),
      side: BorderSide(color: borderColor ?? MobileUi.line),
    );
    return Material(
      color: color ?? Colors.white,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class MSection extends StatelessWidget {
  final String label;
  final Widget? trailing;
  const MSection(this.label, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Row(children: [
          Expanded(
            child: Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                    letterSpacing: 0.6)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class MChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  final IconData? icon;
  const MChip(this.label, {super.key, required this.color, required this.background, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(13)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: color), const SizedBox(width: 5)],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

/// A row of big numbers with small labels under them.
class MStats extends StatelessWidget {
  final List<(String value, String label, Color color)> items;
  const MStats(this.items, {super.key});

  @override
  Widget build(BuildContext context) => MCard(
        child: Row(children: [
          for (final (v, l, c) in items)
            Expanded(
              child: Column(children: [
                Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
                const SizedBox(height: 2),
                Text(l,
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                    textAlign: TextAlign.center),
              ]),
            ),
        ]),
      );
}

/// A full-width primary button that stays at the bottom of a phone screen.
class MStickyButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;
  final bool busy;
  /// On a computer the button sits in the page instead of fixed at the bottom.
  final bool inline;
  const MStickyButton({super.key, required this.label, this.icon, this.onPressed, this.color,
      this.busy = false, this.inline = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: inline ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: inline
            ? null
            : const BoxDecoration(
                color: AppTheme.pageBackground,
                border: Border(top: BorderSide(color: MobileUi.line)),
              ),
        child: SizedBox(
          height: 50,
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: color ?? AppTheme.primaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            onPressed: busy ? null : onPressed,
            icon: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(icon ?? Icons.check_rounded),
            label: Text(label),
          ),
        ),
      );
}

/// Rupees in Indian grouping: 1234567.5 -> "₹12,34,568" (or with paise).
String formatRupees(num value, {bool paise = false}) {
  final neg = value < 0;
  final fixed = value.abs().toStringAsFixed(paise ? 2 : 0);
  final parts = fixed.split('.');
  var whole = parts[0];
  var grouped = '';
  if (whole.length > 3) {
    grouped = ',${whole.substring(whole.length - 3)}';
    whole = whole.substring(0, whole.length - 3);
    while (whole.length > 2) {
      grouped = ',${whole.substring(whole.length - 2)}$grouped';
      whole = whole.substring(0, whole.length - 2);
    }
    grouped = '$whole$grouped';
  } else {
    grouped = whole;
  }
  return '${neg ? '-' : ''}₹$grouped${parts.length > 1 ? '.${parts[1]}' : ''}';
}
