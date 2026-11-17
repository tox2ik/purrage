import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Finds the repositories under a directory, for the Browse mode.
///
/// A repository is a directory holding a `.git` (a folder for a clone, a file for
/// a worktree or submodule); the entry points at that working directory, never at
/// `.git` itself. The walk gives up at [maxDepth], never follows a link, and stops
/// at the first repository it meets on a branch — a repository's own subfolders
/// are not offered as separate checkouts.
class RepoBrowser extends ChangeNotifier {
  RepoBrowser({required String startDirectory, this.maxDepth = 5})
      : directory = _clean(startDirectory);

  /// Five levels below the browsed directory, as asked.
  final int maxDepth;

  /// Folders that never hold the checkout the user wants, and would dominate the
  /// walk on a home directory.
  static const skip = {
    '.git',
    'node_modules',
    '.dart_tool',
    '.venv',
    'venv',
    'build',
    'target',
    'dist',
    '.gradle',
    '.idea',
    '.vscode',
    '.cache',
  };

  String directory;

  List<String> repos = const [];
  bool scanning = false;
  String? error;

  /// Set while a scan is running and a new one was asked for.
  bool _again = false;

  static String _clean(String path) =>
      path.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '');

  /// Go one level up and scan there.
  Future<void> up() async {
    final slash = directory.lastIndexOf('/');
    if (slash <= 0) return;
    final parent = directory.substring(0, slash);
    await goTo(parent);
  }

  Future<void> goTo(String path) async {
    directory = _clean(path);
    await scan();
  }

  /// The mounted drives with a root directory, on Windows.
  static Future<List<String>> drives() async {
    if (!Platform.isWindows) return const [];
    final found = <String>[];
    for (var letter = 'A'.codeUnitAt(0); letter <= 'Z'.codeUnitAt(0); letter++) {
      final root = '${String.fromCharCode(letter)}:/';
      if (await Directory(root).exists()) found.add(root);
    }
    return found;
  }

  Future<void> scan() => _scan(empty: false);

  /// Rescan the current directory; a second request while one runs is folded in.
  Future<void> rescan() => _scan(empty: true);

  Future<void> _scan({required bool empty}) async {
    if (scanning) {
      _again = true;
      return;
    }
    scanning = true;
    if (empty) repos = const [];
    error = null;
    notifyListeners();

    final found = <String>[];
    final invalid = StringBuffer();
    var visited = 0;

    final queue = <_Node>[_Node(directory, 0)];
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      visited++;
      List<FileSystemEntity> children;
      try {
        children = await Directory(node.path).list(followLinks: false).toList();
      } on FileSystemException catch (error) {
        if (invalid.isEmpty) invalid.write('${node.path}: ${error.message}');
        continue;
      }
      if (children.any((child) => child.path.endsWith('/.git') || child.path.endsWith(r'\.git'))) {
        found.add(node.path);
        continue;
      }
      if (node.depth >= maxDepth) continue;
      for (final child in children) {
        if (child is! Directory) continue;
        if (FileSystemEntity.isLinkSync(child.path)) continue;
        final name = child.path.replaceAll(r'\', '/').split('/').last;
        if (skip.contains(name)) continue;
        queue.add(_Node(_clean(child.path), node.depth + 1));
      }
      // Let the UI breathe once in a while on a big tree.
      if (visited % 40 == 0) await Future<void>.delayed(Duration.zero);
    }

    repos = found..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (invalid.isNotEmpty) error = invalid.toString();
    scanning = false;
    notifyListeners();

    if (_again) {
      _again = false;
      await _scan(empty: false);
    }
  }
}

class _Node {
  const _Node(this.path, this.depth);

  final String path;
  final int depth;
}
