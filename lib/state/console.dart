import 'package:flutter/foundation.dart';

import 'failure.dart';

/// One line in the Console mode.
class ConsoleEntry {
  const ConsoleEntry({
    required this.at,
    required this.failure,
    this.action,
  });

  final DateTime at;
  final ActionFailure failure;

  /// What the user was doing: `ignore`, `track`, `commit`, `open in editor`.
  final String? action;

  String get timeLabel {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }
}

/// The Console mode's log: user-action failures, newest first, with their
/// detail. Bounded, so a long session cannot grow without limit.
class ConsoleLog extends ChangeNotifier {
  ConsoleLog({this.limit = 200});

  final int limit;

  final List<ConsoleEntry> _entries = [];

  List<ConsoleEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  void add(ActionFailure failure, {String? action}) {
    _entries.insert(
      0,
      ConsoleEntry(at: DateTime.now(), failure: failure, action: action),
    );
    if (_entries.length > limit) _entries.removeRange(limit, _entries.length);
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}
