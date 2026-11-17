import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The ignore pane's width and whether it is shown: dragged by its edge,
/// remembered in prefs, and out of the way on a narrow window.
///
/// The pane follows the window until the user says otherwise: under
/// [collapseBelow] it is hidden, above it shown. The toggle key overrides that
/// for the session, both ways.
class PaneLayout extends ChangeNotifier {
  PaneLayout({double? width, this.onSave}) : _width = width ?? defaultWidth;

  static const defaultWidth = 360.0;
  static const minWidth = 240.0;

  /// The pane may take at most this share of the window.
  static const maxShare = 0.6;

  /// Narrower windows hide the pane, so the file list keeps its room.
  static const collapseBelow = 900.0;

  /// Persists a width once a drag ends.
  final Future<void> Function(double width)? onSave;

  double _width;
  bool? _shown;

  /// The width the user asked for; [widthIn] fits it to a window.
  double get width => _width;

  /// The width to draw in a window [room] wide.
  double widthIn(double room) => _fit(_width, room);

  static double _fit(double width, double room) =>
      width.clamp(minWidth, math.max(minWidth, room * maxShare));

  /// Shown in a window [room] wide: the user's toggle, else by the window width.
  bool shownIn(double room) => _shown ?? room >= collapseBelow;

  /// The pane's edge moved by [delta] (positive widens it).
  void dragBy(double delta, double room) {
    _width = _fit(widthIn(room) + delta, room);
    notifyListeners();
  }

  /// The drag ended: remember the width.
  void dragEnd() {
    final save = onSave;
    if (save != null) unawaited(save(_width));
  }

  /// Double-click on the edge: back to the default width.
  void reset() {
    _width = defaultWidth;
    notifyListeners();
    dragEnd();
  }

  /// Set the width read from prefs, without saving it again.
  void restore(double? width) {
    if (width == null || width == _width) return;
    _width = width;
    notifyListeners();
  }

  /// The toggle key: show a hidden pane, hide a shown one.
  void toggle(double room) {
    _shown = !shownIn(room);
    notifyListeners();
  }
}
