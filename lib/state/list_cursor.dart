import 'package:flutter/foundation.dart';

/// A cursor over a list whose rows live elsewhere (the console log, the
/// detected editors): the index, kept inside the list as it grows and shrinks.
///
/// Motion clamps at both ends; a jump of any size (Home, End, a page) is just
/// a large delta.
class ListCursor extends ChangeNotifier {
  int _index = 0;
  int _length = 0;

  int get index => _index;
  int get length => _length;

  /// The list now has [length] rows; the cursor stays inside it. Called from
  /// `build`, so it does not notify.
  void sync(int length) {
    _length = length;
    _index = length == 0 ? 0 : _index.clamp(0, length - 1);
  }

  /// Move by [delta] rows, clamped; nothing is redrawn when it does not move.
  void move(int delta) => jump(_index + delta);

  /// Put the cursor on row [index], clamped.
  void jump(int index) {
    if (_length == 0) return;
    final next = index.clamp(0, _length - 1);
    if (next == _index) return;
    _index = next;
    notifyListeners();
  }
}
