import 'package:flutter/material.dart';

import '../state/notices.dart';

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
                  cursor: SystemMouseCursors.basic,
                  onEnter: (_) => notices.setHovered(true),
                  onExit: (_) => notices.setHovered(false),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Material(
                      elevation: 6,
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: SelectableText(
                                notice.message,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Dismiss',
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: notices.dismiss,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
