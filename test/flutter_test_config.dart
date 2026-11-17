import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/temp_dirs.dart';

/// Runs around every test file: the temp folders it made are deleted when it is
/// done, and a folder that cannot be deleted fails the file instead of staying
/// in `%TEMP%` unnoticed.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  tearDownAll(() async {
    final left = await removeTempDirs();
    if (left.isNotEmpty) fail('temp folders left behind: ${left.join(', ')}');
  });
  await testMain();
}
