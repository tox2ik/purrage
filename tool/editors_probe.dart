// ignore_for_file: avoid_print
// Prints what the editor detection picks on this machine, and the command line
// "Open in editor" would start for a file, without starting the app.
//
// Why this exists: "Open in editor" did nothing on this machine. `git var
// GIT_EDITOR` answers `vi`, which is not on PATH, and `where` lists a `.bat`
// wrapper before the real `.exe`. The probe shows the detected list, the chosen
// one and the tokens it launches; the order it settled on is in PLAN.md
// "Editor detection" (07e6ebf added the probe with the detection rework).
//
//   dart run tool/editors_probe.dart <file> [line]
//
// For example:
//
//   dart run tool/editors_probe.dart C:\tmp\PLAN.md 3
import 'dart:io';

import 'package:purrage/state/editors.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run tool/editors_probe.dart <file> [line]');
    exitCode = 64;
    return;
  }
  final file = args.first;
  final line = args.length > 1 ? int.tryParse(args[1]) : null;
  final editors = Editors();
  final found = await editors.detect();
  for (final option in found) {
    print(
      '${option.id.padRight(10)} ${option.detected ? 'found' : 'MISSING'}'
      '  ${option.command}',
    );
  }
  final chosen = await editors.chosenOption();
  print('');
  print('chosen: ${chosen.label} -> ${chosen.command}');
  final tokens = Editors.expand(chosen.command, file: file, line: line);
  print('launch: ${tokens.first}');
  print('args:   ${tokens.skip(1).toList()}');
}
