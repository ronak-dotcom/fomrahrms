import 'package:flutter/material.dart';
import '../models/notification_store.dart';
import '../theme/app_theme.dart';

/// Bell icon with an unread-count badge, driven by [NotificationStore.unreadCount].
/// Used in the computer layout's top bar and each shell's phone header.
class NotificationBellIcon extends StatelessWidget {
  final Color color;
  final double size;
  final Color badgeBorderColor;
  const NotificationBellIcon({
    super.key,
    this.color = Colors.white70,
    this.size = 20,
    this.badgeBorderColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.notifications_rounded, color: color, size: size),
        ValueListenableBuilder<int>(
          valueListenable: NotificationStore.unreadCount,
          builder: (_, count, __) {
            if (count <= 0) return const SizedBox.shrink();
            return Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: AppTheme.error,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: badgeBorderColor, width: 1.5),
                ),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
