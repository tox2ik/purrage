import 'dart:async';

/// Collects the files of actions that come in quick succession and hands them
/// over once, when the quiet [window] after the last one has passed.
///
/// Untrack uses it: several `u` presses within 900 ms share one notice that
/// names every file, instead of one notice per press. Each [add] restarts the
/// window; the notice goes up when it closes.
class NoticeGroup {
  NoticeGroup({required this.onClose, this.window = const Duration(milliseconds: 900)});

  final Duration window;

  /// Called with every file collected, in order, once the window closes.
  final void Function(List<String> files) onClose;

  final List<String> _files = [];
  Timer? _timer;

  /// The files collected so far, for tests and the debug bar.
  List<String> get pending => List.unmodifiable(_files);

  void add(Iterable<String> files) {
    for (final file in files) {
      if (!_files.contains(file)) _files.add(file);
    }
    _timer?.cancel();
    _timer = Timer(window, _close);
  }

  void _close() {
    _timer = null;
    if (_files.isEmpty) return;
    final files = List<String>.of(_files);
    _files.clear();
    onClose(files);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _files.clear();
  }
}
