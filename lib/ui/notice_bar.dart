import 'package:flutter/material.dart';

import '../state/notices.dart';
import 'widgets.dart';

/// The failure notice: a bar near the bottom, dismissed by the close button, by
/// its timer, or held open while the mouse is over it.
class NoticeBar extends StatelessWidget {
  const NoticeBar({super.key, required this.notices});

  final Notices notices;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notices,
      builder: (context, _) {
        final notice = notices.current;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: notice == null
              ? const SizedBox.shrink()
              : MouseRegion(
                  key: const ValueKey('notice'),
                  onEnter: (_) => notices.setHovered(true),
                  onExit: (_) => notices.setHovered(false),
                  child: _NoticeCard(message: notice.message, onDismiss: notices.dismiss),
                ),
        );
      },
    );
  }
}

/// The card itself: the message, selectable, and the close button.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        elevation: 6,
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SelectableText(message, style: TextStyle(color: scheme.onErrorContainer)),
              ),
              const SizedBox(width: 8),
              IconAction(icon: Icons.close, tooltip: 'Dismiss', onPressed: onDismiss),
            ],
          ),
        ),
      ),
    );
  }
}
