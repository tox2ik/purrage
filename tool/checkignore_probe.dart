// ignore_for_file: avoid_print
// Prints what `Repo.checkIgnore` answers for each path, so the answer can be
// compared with `git status` without starting the app.
//
// Why this exists: `git status` prints an untracked directory as `dir/`, and
// `git check-ignore -v -- dir/` then answers with an empty pattern and the last
// line it scanned: a match that does not exist. The app refused to ignore such
// folders as "already ignored". This probe found it; the fix strips the slash
// (6f3f52f "state: never hand git check-ignore a trailing slash").
//
//   dart run tool/checkignore_probe.dart <directory> <path>...
//
// The paths it was written for, in the home repository:
//
//   dart run tool/checkignore_probe.dart %USERPROFILE% es/buss-sjekk/ hs/it-agent/
import 'dart:io';

import 'package:purrage/state/repo.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('usage: dart run tool/checkignore_probe.dart <directory> <path>...');
    exitCode = 64;
    return;
  }
  final repo = await Repo.open(args.first);
  for (final path in args.skip(1)) {
    final match = await repo.checkIgnore(path);
    final answer = match == null
        ? 'no match'
        : '${match.pattern} in ${match.source}:${match.line}';
    print('${path.padRight(28)} -> $answer');
  }
}
