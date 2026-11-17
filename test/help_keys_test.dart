import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/ui/app_keys.dart';
import 'package:purrage/ui/help_view.dart';
import 'package:purrage/ui/mode_rail.dart';

/// The mode numbers live in one place, `Mode`. The key map and the help table
/// are one source already (`app_keys.dart`, see `app_keys_test.dart`); these
/// tests keep the numbers from being spelled out anywhere else.
void main() {
  test('a mode carries its number, key and name', () {
    expect(Mode.values.map((mode) => mode.number), [1, 2, 3, 4, 5]);
    expect(Mode.settings.key, 'Alt+3');
    expect(Mode.console.named, 'Console (Alt+4)');
    for (final mode in Mode.values) {
      expect(mode.digit.keyLabel, '${mode.number}');
    }
  });

  test('the help line for the modes is built from the enum', () {
    final line = keyTable.firstWhere((help) => help.keys.startsWith(Mode.values.first.key));
    expect(line.keys, '${Mode.changes.key} … ${Mode.help.key}');
    expect(line.what, Mode.values.map((mode) => mode.label).join(', '));
    expect(appBindings.first.activators, hasLength(Mode.values.length));
  });

  test('no string in lib/ spells out an Alt+<digit>; it asks Mode', () {
    // A quoted string with Alt+ and a digit: the stale "(Alt+3)" kind. Doc
    // comments may still name a key as an example.
    final spelled = RegExp(r'''['"][^'"\n]*Alt\+\d''');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.replaceAll(r'\', '/').endsWith('state/modes.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (final (index, line) in lines.indexed) {
        if (line.trimLeft().startsWith('//')) continue;
        if (spelled.hasMatch(line)) offenders.add('${entity.path}:${index + 1}: ${line.trim()}');
      }
    }
    expect(offenders, isEmpty);
  });
}
