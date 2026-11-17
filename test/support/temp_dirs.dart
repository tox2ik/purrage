import 'dart:io';

final _made = <Directory>[];

/// Remember a temp folder a test made, so [removeTempDirs] deletes it when the
/// test file is done, if the test's own teardown could not.
T keepForCleanup<T extends FileSystemEntity>(T entity) {
  if (entity is Directory) _made.add(entity);
  return entity;
}

/// Delete [dir], retrying a few times while Windows still holds it: a git
/// process that is ending keeps its working directory locked (errno 32, "used
/// by another process") for a moment after its future completed.
Future<void> deleteWithRetry(Directory dir, {int attempts = 10}) async {
  for (var attempt = 1;; attempt++) {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      return;
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      final busy = code == 32 || code == 5 || code == 145;
      if (!busy || attempt >= attempts) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 50 * attempt));
    }
  }
}

/// Delete the folders this test file made and still left; returns the ones
/// that could not be deleted, so the caller can fail loudly.
Future<List<String>> removeTempDirs() async {
  final left = <String>[];
  for (final dir in _made) {
    try {
      await deleteWithRetry(dir);
    } on FileSystemException {
      left.add(dir.path);
    }
  }
  _made.clear();
  return left;
}

/// The number of `purrage_*` folders in `%TEMP%`, for the cleanup check in
/// CLAUDE.md.
Future<int> countTempDirs() async {
  var count = 0;
  await for (final entity in Directory.systemTemp.list()) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
    if (entity is Directory && name.startsWith('purrage_')) count++;
  }
  return count;
}
