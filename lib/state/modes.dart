/// The modes the app shows; the rail lists them in this order, and `Alt+<n>`
/// opens each one. This is the one place a mode's number lives: the key map,
/// the help table, the rail tooltips and every "(Alt+N)" in a message are built
/// from it. Plain Dart, so `lib/state` can name a mode without importing UI.
enum Mode {
  changes('Changes'),
  browse('Browse'),
  settings('Settings'),
  console('Console'),
  help('Help');

  const Mode(this.label);

  final String label;

  /// The number that opens this mode with Alt, 1 for the first.
  int get number => index + 1;

  /// The key as people read it, e.g. `Alt+3`.
  String get key => 'Alt+$number';

  /// The mode's name with its key, for messages and tooltips: `Settings (Alt+3)`.
  String get named => '$label ($key)';
}
