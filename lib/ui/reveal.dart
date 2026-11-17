import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Scroll [controller] the least that brings the range [top] .. [top] +
/// [height] into view, with a jump (no animation to queue up while a key is
/// held). A range already in view does not scroll. Ported from Ops
/// (`nvimos-ops/lib/ui/reveal.dart`).
///
/// Returns false when the range lies past the list's current extent, i.e. the
/// list has not laid out its new length yet; the caller tries again after the
/// frame.
bool revealRange(ScrollController controller, double top, double height) {
  if (!controller.hasClients) return false;
  final position = controller.position;
  final bottom = top + height;
  if (top < position.pixels) {
    controller.jumpTo(math.max(position.minScrollExtent, top));
  } else if (bottom > position.pixels + position.viewportDimension) {
    final wanted = bottom - position.viewportDimension;
    controller.jumpTo(math.min(position.maxScrollExtent, wanted));
    if (wanted > position.maxScrollExtent) return false;
  }
  return true;
}
