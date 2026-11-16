import 'package:flutter/services.dart';

bool _isDown(KeyEvent event) =>
    event is KeyDownEvent || event is KeyRepeatEvent;

/// The one place Up/Down motion is decided, so `j`/`k`, WASD and the arrows
/// cannot drift apart. Returns -1 for up, 1 for down, null for anything else.
int? navDelta(KeyEvent event) {
  if (!_isDown(event)) return null;
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.arrowUp) return -1;
  if (key == LogicalKeyboardKey.arrowDown) return 1;
  final character = event.character?.toLowerCase();
  return switch (character) {
    'k' || 'w' => -1,
    'j' || 's' => 1,
    _ => null,
  };
}

/// True for a plain key that acts on the focused row: no Ctrl, Alt or Meta.
bool isPlain(KeyEvent event) {
  final keyboard = HardwareKeyboard.instance;
  return !keyboard.isControlPressed &&
      !keyboard.isAltPressed &&
      !keyboard.isMetaPressed;
}
