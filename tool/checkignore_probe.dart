// ignore_for_file: avoid_print
// Checks the ignore answers for the paths the home repository shows, with and
// without the trailing slash git status prints for a directory.
//
//   dart run tool/checkignore_probe.dart [directory] [path...]
import 'dart:io';

import 'package:purrage/state/repo.dart';

Future<void> main(List<String> args) async {
  final target = args.isEmpty ? Directory.current.path : args.first;
  final paths = args.length > 1 ? args.sublist(1) : ['es/buss-sjekk/', 'hs/it-agent/'];
  final repo = await Repo.open(target);
  for (final path in paths) {
    final match = await repo.checkIgnore(path);
    print('${path.padRight(28)} -> ${match == null ? 'no match' : '${match.pattern} in ${match.source}:${match.line}'}');
  }
}
