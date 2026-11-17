import 'package:flutter/material.dart';

import '../state/pane_layout.dart';

/// A right-hand pane the mouse can resize by dragging its left edge, ported
/// from Ops' `resizable_pane.dart`. The width lives in [PaneLayout] (and so in
/// prefs); double-clicking the edge goes back to the default width.
class ResizablePane extends StatelessWidget {
  const ResizablePane({super.key, required this.layout, required this.room, required this.child});

  final PaneLayout layout;

  /// The window width the pane is fitted to.
  final double room;

  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          PaneEdge(
            onDrag: (dx) => layout.dragBy(-dx, room),
            onDragEnd: layout.dragEnd,
            onReset: layout.reset,
          ),
          SizedBox(width: layout.widthIn(room), child: child),
        ],
      );
}

/// The draggable divider: a hairline with a wider hit area, the resize cursor
/// and a tooltip that says what it does.
class PaneEdge extends StatelessWidget {
  const PaneEdge({super.key, required this.onDrag, required this.onDragEnd, required this.onReset});

  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  static const tooltip = 'Drag to resize the ignore pane; double-click for the default width';

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
            onHorizontalDragEnd: (_) => onDragEnd(),
            onDoubleTap: onReset,
            child: const SizedBox(width: 7, child: Center(child: VerticalDivider(width: 1))),
          ),
        ),
      );
}
