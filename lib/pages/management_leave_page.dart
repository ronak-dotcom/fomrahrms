import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

class ManagementLeavePage extends StatelessWidget {
  const ManagementLeavePage({super.key});

  static const _color = Color(0xFF111827);

  static List<_Topic> get _topics => [
    // One card, not two. These pointed at the same screen under different
    // names — "Leave Management" and "Team Leave Approvals" — so whichever a
    // person picked, they got the same page and could not tell whether they
    // were in the right place. That is a large part of why approvals kept
    // looking broken.
    _Topic(
      'Leave Approvals',
      Icons.group_rounded,
      AppTheme.primaryBlue,
      '/management/leave/team-approvals',
      'Every employee\u2019s leave — approve, reject, escalate, or change a '
      'decision already made.',
    ),
    _Topic(
      'Edit Leave Forms',
      Icons.edit_note_rounded,
      AppTheme.primaryBlue,
      '/management/edit-leave-form',
      'Approve HR requests or directly update Leave, Permission & Comp Off form options.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: null,
      body: SingleChildScrollView(
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
                child: const Icon(Icons.beach_access_rounded, color: _color, size: 26),
              ),
              const SizedBox(width: 16),
              Text('Leave Management',
                  style: Theme.of(context).textTheme.headlineMedium),
            ]),
            const SizedBox(height: 24),

            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width < 600 ? 1 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 2.8,
              children: _topics.map((t) => _TopicCard(topic: t)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Topic {
  final String title;
  final IconData icon;
  final Color color;
  final String route;
  final String subtitle;
  const _Topic(this.title, this.icon, this.color, this.route, this.subtitle);
}

class _TopicCard extends StatelessWidget {
  final _Topic topic;
  const _TopicCard({required this.topic});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(topic.route),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: topic.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(topic.icon, color: topic.color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(topic.title,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: topic.color)),
                const SizedBox(height: 3),
                Text(topic.subtitle,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: topic.color.withValues(alpha: 0.5)),
          ]),
        ),
      ),
    );
  }
}
