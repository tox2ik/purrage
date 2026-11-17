// ignore_for_file: avoid_print
// Prints the rows of a repository and which of them hold a `.git` of their own,
// for checking the nested-repository marker without the app.
//
//   dart run tool/nested_probe.dart [directory]
import 'dart:io';

import 'package:purrage/state/repo.dart';

Future<void> main(List<String> args) async {
  final target = args.isEmpty ? Directory.current.path : args.first;
  final repo = await Repo.open(target);
  final rows = await repo.status();
  print('repo: ${repo.path}  rows: ${rows.length}');
  var nestedFound = 0;
  for (final row in rows) {
    final nested = await repo.isNestedRepository(row.path);
    if (nested) nestedFound++;
    if (nested || row.path.contains('mattpocock') || row.path.startsWith('es/')) {
      print('${row.section.name.padRight(9)} ${row.path.padRight(48)} nested=$nested');
    }
  }
  print('nested rows: $nestedFound');
}
