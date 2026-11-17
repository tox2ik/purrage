// ignore_for_file: avoid_print
// Prints the rows of a repository that hold a `.git` of their own, plus every
// row whose path contains one of the filters, for checking the nested-repository
// marker without the app.
//
// Why this exists: a row whose folder is a repository of its own (an embedded
// repo, a gitlink, a submodule) carries the small `git` marker, because its
// ignore rules belong to the inner repository. The marker was missing on some
// rows and present on others; this probe printed which ones the stat finds
// (added with 7a2997a "ui: the git marker sits right after the base name").
//
//   dart run tool/nested_probe.dart <directory> [filter...]
//
// The filters it was written with, in the home repository:
//
//   dart run tool/nested_probe.dart %USERPROFILE% mattpocock es/
import 'dart:io';

import 'package:purrage/state/repo.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run tool/nested_probe.dart <directory> [filter...]');
    exitCode = 64;
    return;
  }
  final filters = args.skip(1).toList();
  final repo = await Repo.open(args.first);
  final rows = await repo.status();
  print('repo: ${repo.path}  rows: ${rows.length}');
  var nestedFound = 0;
  for (final row in rows) {
    final nested = await repo.isNestedRepository(row.path);
    if (nested) nestedFound++;
    if (nested || filters.any(row.path.contains)) {
      print(
        '${row.section.name.padRight(9)} ${row.path.padRight(48)} nested=$nested',
      );
    }
  }
  print('nested rows: $nestedFound');
}
