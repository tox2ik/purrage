import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One directory the walk opened, kept when it was slow or wide.
class ScanSample {
  const ScanSample({required this.path, required this.took, required this.entries});

  final String path;
  final Duration took;
  final int entries;
}

/// What one scan did, for the console: how far it went, what it skipped, and
/// which directories cost the most, so the skip list can be tuned from evidence.
class ScanReport {
  const ScanReport({
    required this.directory,
    required this.depth,
    required this.visited,
    required this.found,
    required this.skipped,
    required this.elapsed,
    required this.slowest,
    required this.widest,
    required this.stopped,
  });

  final String directory;
  final int depth;
  final int visited;
  final int found;
  final int skipped;
  final Duration elapsed;
  final List<ScanSample> slowest;
  final List<ScanSample> widest;
  final bool stopped;

  String get summary =>
      'scanned $directory  ${_ms(elapsed)}  depth $depth  '
      '$visited dir(s), $found repo(s)'
      '${skipped > 0 ? ', $skipped skipped' : ''}'
      '${stopped ? ', stopped at the limit' : ''}';

  String get detail {
    final lines = <String>[
      'origin: RepoBrowser.scan -> Directory.list',
      'root: $directory',
      'depth: $depth',
      'directories visited: $visited',
      'directories skipped by rule: $skipped',
      'repositories found: $found',
      'elapsed: ${_ms(elapsed)}',
    ];
    if (slowest.isNotEmpty) {
      lines.add('slowest listings:');
      for (final sample in slowest) {
        lines.add('  ${_ms(sample.took).padLeft(8)}  ${sample.entries} entries  ${sample.path}');
      }
    }
    if (widest.isNotEmpty) {
      lines.add('widest directories:');
      for (final sample in widest) {
        lines.add('  ${sample.entries.toString().padLeft(6)} entries  ${_ms(sample.took).padLeft(8)}  ${sample.path}');
      }
    }
    return lines.join('\n');
  }

  static String _ms(Duration duration) => duration.inMilliseconds < 1000
      ? '${duration.inMilliseconds} ms'
      : '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s';
}

/// Finds the repositories under a directory, for the Browse mode.
///
/// A repository is a directory holding a `.git` (a folder for a clone, a file for
/// a worktree or submodule); the entry points at that working directory, never at
/// `.git` itself. The walk gives up at [maxDepth], never follows a link, and stops
/// at the first repository it meets on a branch — a repository's own subfolders
/// are not offered as separate checkouts.
class RepoBrowser extends ChangeNotifier {
  RepoBrowser({
    required String startDirectory,
    this.maxDepth = 5,
    this.onReport,
  }) : directory = _clean(startDirectory);

  /// Five levels below the browsed directory, as asked.
  final int maxDepth;

  /// Called once per scan, for the console.
  void Function(ScanReport report)? onReport;

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
    'obj',
    'bin',
    'out',
    'coverage',
    '.next',
    '.turbo',
    '.terraform',
    'vendor',
    'Pods',
    'AppData',
    '__pycache__',
    '.npm',
    '.pnpm-store',
    '.nuget',
    '.rustup',
    '.cargo',
  };

  /// Whole trees never worth walking on Windows: no checkout lives there, and the
  /// enumeration cost is enormous. Matched as path prefixes, case-insensitively.
  static const skipTrees = [
    'c:/windows',
    'c:/program files',
    'c:/program files (x86)',
    'c:/programdata',
    r'c:/$recycle.bin',
    'c:/system volume information',
    'c:/recovery',
    'c:/perflogs',
  ];

  /// A ceiling on how many directories one scan will open. Five levels below a
  /// drive root can still be enormous; the user can narrow the folder instead.
  static const maxDirectories = 20000;

  String directory;

  List<String> repos = const [];
  bool scanning = false;
  String? error;

  /// Set while a scan is running and a new one was asked for.
  bool _again = false;

  static String _clean(String path) =>
      path.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '');

  static bool _inSkippedTree(String path) {
    final lower = _clean(path).toLowerCase();
    for (final tree in skipTrees) {
      if (lower == tree || lower.startsWith('$tree/')) return true;
    }
    return false;
  }

  /// Drop an entry the user tried to open and git refused, so the list stops
  /// offering a checkout that is gone or was never one.
  void drop(String path) {
    final before = repos.length;
    repos = [
      for (final repo in repos)
        if (repo != path) repo,
    ];
    if (repos.length != before) notifyListeners();
  }

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

    final clock = Stopwatch()..start();
    final found = <String>[];
    final samples = <ScanSample>[];
    var visited = 0;
    var skipped = 0;
    var stopped = false;

    final queue = <_Node>[_Node(directory, 0)];
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      if (++visited > maxDirectories) {
        stopped = true;
        break;
      }

      // One stat, before any listing: a folder that holds a `.git` is a hit, and
      // its own tree is not walked. Listing a directory is the expensive call.
      if (await _hasGit(node.path)) {
        found.add(node.path);
        continue;
      }
      if (node.depth >= maxDepth) continue;

      final listing = Stopwatch()..start();
      List<FileSystemEntity> children;
      try {
        children = await Directory(node.path).list(followLinks: false).toList();
      } on FileSystemException {
        continue;
      }
      listing.stop();
      samples.add(ScanSample(path: node.path, took: listing.elapsed, entries: children.length));

      for (final child in children) {
        if (child is! Directory) continue;
        if (FileSystemEntity.isLinkSync(child.path)) continue;
        final name = child.path.replaceAll(r'\', '/').split('/').last;
        if (skip.contains(name)) continue;
        final clean = _clean(child.path);
        if (_inSkippedTree(clean)) {
          skipped++;
          continue;
        }
        queue.add(_Node(clean, node.depth + 1));
      }
      // Let the UI breathe every few directories: on Windows a listing can block
      // the event loop for a moment.
      if (visited % 8 == 0) await Future<void>.delayed(Duration.zero);
    }

    clock.stop();
    repos = found..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (stopped) {
      error = 'stopped after $maxDirectories directories; narrow the folder to see more';
    }
    scanning = false;
    notifyListeners();

    final slowest = [...samples]..sort((a, b) => b.took.compareTo(a.took));
    final widest = [...samples]..sort((a, b) => b.entries.compareTo(a.entries));
    onReport?.call(ScanReport(
      directory: directory,
      depth: maxDepth,
      visited: visited,
      found: found.length,
      skipped: skipped,
      elapsed: clock.elapsed,
      slowest: slowest.take(6).toList(),
      widest: widest.take(6).toList(),
      stopped: stopped,
    ));

    if (_again) {
      _again = false;
      await _scan(empty: false);
    }
  }

  /// A `.git` of its own: a folder for a clone, a file for a worktree or a
  /// submodule. One `type` call, no listing.
  static Future<bool> _hasGit(String path) async {
    final kind = await FileSystemEntity.type('$path/.git');
    return kind != FileSystemEntityType.notFound;
  }
}

class _Node {
  const _Node(this.path, this.depth);

  final String path;
  final int depth;
}
