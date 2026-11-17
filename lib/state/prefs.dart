/// The app's own settings, kept out of git: `%APPDATA%/Purrage/prefs.json`.
///
/// The file is optional and may be corrupt; a missing or unreadable file reads
/// as "nothing saved yet" rather than a startup failure. Writes go through a
/// temp file and a rename, so a crash mid-write cannot leave a half file.
library;

import 'dart:convert';
import 'dart:io';

import 'system.dart';

/// A tiny JSON store with one key today, the chosen editor command.
class Prefs {
  /// [directory] overrides where `prefs.json` lives; tests pass a temp folder.
  /// The default is [defaultDirectory].
  Prefs({this.directory, this.env});

  /// The folder given to the constructor, or null for [defaultDirectory].
  final String? directory;

  /// The environment [defaultDirectory] reads; null for the real one.
  final Env? env;

  Map<String, Object?> _values = <String, Object?>{};
  bool _loaded = false;

  /// The folder holding `prefs.json`, forward slashes.
  String get folder => directory ?? defaultDirectory(env);

  /// `prefs.json` next to this app's settings.
  String get path => '$folder/prefs.json';

  /// True once a load has completed, so a caller can tell "empty" from "unread".
  bool get isLoaded => _loaded;

  /// `%APPDATA%/Purrage`, or `<home>/Purrage` when APPDATA is unset.
  /// `<cwd>/Purrage` when neither home variable is set either.
  static String defaultDirectory([Env? env]) {
    final vars = env ?? Env.system();
    final base = vars['APPDATA'] ?? vars.home ?? Directory.current.path;
    return '$base/Purrage'.replaceAll(r'\', '/');
  }

  /// Read the file; a missing, empty or unreadable file leaves the store empty.
  Future<void> load() async {
    _loaded = true;
    try {
      final file = File(path);
      if (!await file.exists()) {
        _values = <String, Object?>{};
        return;
      }
      final text = await file.readAsString();
      if (text.trim().isEmpty) {
        _values = <String, Object?>{};
        return;
      }
      final decoded = jsonDecode(text);
      _values = decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : <String, Object?>{};
    } on Exception {
      // A corrupt prefs file must not stop the app from opening.
      _values = <String, Object?>{};
    }
  }

  /// The command template the user picked, or null when there is no choice.
  String? get editorCommand {
    final value = _values['editorCommand'];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Save the editor command, or clear it with null: the next detection wins.
  Future<void> setEditorCommand(String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _values.remove('editorCommand');
    } else {
      _values['editorCommand'] = trimmed;
    }
    await _save();
  }

  /// The ignore pane's width the user dragged it to, or null for the default.
  double? get ignorePaneWidth {
    final value = _values['ignorePaneWidth'];
    return value is num && value > 0 ? value.toDouble() : null;
  }

  Future<void> setIgnorePaneWidth(double width) async {
    _values['ignorePaneWidth'] = width.roundToDouble();
    await _save();
  }

  /// Write the whole store: a temp file in the same folder, then a rename.
  Future<void> _save() async {
    final dir = Directory(folder);
    await dir.create(recursive: true);
    final text = '${const JsonEncoder.withIndent('  ').convert(_values)}\n';
    final temp = File('$folder/prefs.json.tmp');
    await temp.writeAsString(text, flush: true);
    await temp.rename(path);
  }
}
