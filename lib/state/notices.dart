import 'dart:async';

import 'package:flutter/foundation.dart';

/// One message in the notice bar.
class Notice {
  const Notice(this.message, {this.failure = true});

  final String message;

  /// A failure is drawn in the error colours; the one success that speaks (the
  /// grouped untrack notice) is not.
  final bool failure;
}

/// A single notice shown by the UI, which goes away on its own unless the mouse
/// is over it: hovering holds it, leaving starts the countdown again with the
/// time that was left.
///
/// Deliberately not a SnackBar: a failure has to stay readable while the user
/// looks at the row it concerns, not vanish after four seconds wherever the
/// pointer happens to be.
class Notices extends ChangeNotifier {
  Notices({this.lifetime = const Duration(seconds: 6)});

  final Duration lifetime;

  Notice? _current;
  Timer? _timer;
  Duration _remaining = Duration.zero;
  DateTime? _timerStart;
  bool _hovered = false;

  Notice? get current => _current;

  bool get hovered => _hovered;

  void show(String message, {bool failure = true}) {
    _current = Notice(message, failure: failure);
    _remaining = lifetime;
    _hovered = false;
    _startTimer();
    notifyListeners();
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    _timerStart = null;
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  /// The pointer entered or left the notice.
  void setHovered(bool value) {
    if (_hovered == value) return;
    if (value) {
      _rememberRemaining();
      _timer?.cancel();
      _timer = null;
    }
    _hovered = value;
    if (!value) _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    if (_current == null || _hovered || _remaining <= Duration.zero) return;
    _timer?.cancel();
    _timerStart = DateTime.now();
    _timer = Timer(_remaining, dismiss);
  }

  /// Keep what is left, so leaving and re-entering does not reset the clock.
  void _rememberRemaining() {
    final start = _timerStart;
    if (start == null) return;
    final left = _remaining - DateTime.now().difference(start);
    _remaining = left.isNegative ? Duration.zero : left;
    _timerStart = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
