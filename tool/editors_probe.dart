// ignore_for_file: avoid_print
//
// Prints what the editor detection picks on this machine, for diagnosing
// "Open in editor" without starting the app.
//
//   dart run tool/editors_probe.dart
import 'package:purrage/state/editors.dart';

Future<void> main() async {
  final editors = Editors();
  final found = await editors.detect();
  for (final option in found) {
    print('${option.id.padRight(10)} ${option.detected ? 'found' : 'MISSING'}'
        '  ${option.command}');
  }
  final chosen = await editors.chosenOption();
  print('');
  print('chosen: ${chosen.label} -> ${chosen.command}');
  final tokens = Editors.expand(chosen.command, file: r'C:\tmp\PLAN.md', line: 3);
  print('launch: ${tokens.first}');
  print('args:   ${tokens.skip(1).toList()}');
}
