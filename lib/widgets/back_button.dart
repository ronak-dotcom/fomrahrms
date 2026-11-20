import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'mobile_shell.dart';

class NavBackButton extends StatelessWidget {
  const NavBackButton({super.key});

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      final path = GoRouterState.of(context).uri.path;
      if (path.startsWith('/manager/')) {
        context.go('/manager/dashboard');
      } else if (path.startsWith('/employee/')) {
        context.go('/employee/dashboard');
      } else if (path.startsWith('/management/')) {
        context.go('/management/dashboard');
      } else {
        context.go('/dashboard');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // On phones the header already shows a back arrow; a second one in the
    // page was one of the four stacked bands the redesign removed.
    if (MobileChrome.maybeOf(context)?.providesBack ?? false) {
      return const SizedBox.shrink();
    }
    return IconButton(
      onPressed: () => _back(context),
      icon: const Icon(Icons.arrow_back_rounded),
      tooltip: 'Back',
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
    );
  }
}
