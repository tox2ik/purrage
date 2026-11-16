/// Which rule to write for a path, and which `.gitignore`-like file it goes in.
///
/// Git reads `.gitignore` at every level, so a rule belongs in the narrowest
/// file that covers the path: patterns in a nested file are relative to that
/// file's folder, patterns in the root file are repo-relative.
library;

/// What the rule should cover.
enum IgnoreScope { file, extension, folder }

/// The four places a rule can live.
enum IgnoreTargetKind { folderGitignore, rootGitignore, localExclude, globalIgnore }

/// One writable ignore file, with the repo-relative folder it governs.
class IgnoreTarget {
  const IgnoreTarget({
    required this.kind,
    required this.label,
    required this.path,
    required this.dir,
    this.exists = false,
  });

  final IgnoreTargetKind kind;
  final String label;

  /// Absolute path, forward slashes.
  final String path;

  /// Repo-relative folder the file sits in; empty for the root.
  final String dir;

  final bool exists;

  bool get isCommitted => kind == IgnoreTargetKind.folderGitignore || kind == IgnoreTargetKind.rootGitignore;
}

/// Pure rule building, so the shapes are unit-tested without git or widgets.
class IgnoreRules {
  /// The rule that ignores [path] when written into the file that governs
  /// [targetDir]. Returns null when the scope cannot produce a rule (an
  /// extension scope on a file without an extension).
  static String? pattern({
    required IgnoreScope scope,
    required String targetDir,
    required String path,
  }) {
    final cleanPath = _noTrailingSlash(path);
    final cleanDir = _noTrailingSlash(targetDir);
    final relative = cleanDir.isEmpty ? cleanPath : _withoutPrefix(cleanPath, cleanDir);

    switch (scope) {
      case IgnoreScope.file:
        return '/${_escapeSegments(relative)}';
      case IgnoreScope.folder:
        final folder = _folderFor(relative, isFolderRow: path.endsWith('/'));
        if (folder == null) return null;
        return '/${_escapeSegments(folder)}/';
      case IgnoreScope.extension:
        final name = relative.contains('/')
            ? relative.substring(relative.lastIndexOf('/') + 1)
            : relative;
        final dot = name.lastIndexOf('.');
        if (dot <= 0 || dot == name.length - 1) return null;
        return '*.${_escapeSegment(name.substring(dot + 1))}';
    }
  }

  /// The targets to offer for [path], narrowest first.
  static List<IgnoreTarget> targets({
    required String repoPath,
    required List<String> gitignoreFiles,
    required String localExclude,
    required String globalIgnore,
    required String path,
  }) {
    final repo = _noTrailingSlash(repoPath);
    final folder = _folderOf(path);
    final existing = gitignoreFiles.map(_noTrailingSlash).toSet();
    final targets = <IgnoreTarget>[];

    if (folder.isNotEmpty) {
      final nested = '$repo/$folder/.gitignore';
      targets.add(IgnoreTarget(
        kind: IgnoreTargetKind.folderGitignore,
        label: folder,
        path: nested,
        dir: folder,
        exists: existing.contains('$folder/.gitignore'),
      ));
    }
    targets.add(IgnoreTarget(
      kind: IgnoreTargetKind.rootGitignore,
      label: 'root',
      path: '$repo/.gitignore',
      dir: '',
      exists: existing.contains('.gitignore'),
    ));
    targets.add(IgnoreTarget(
      kind: IgnoreTargetKind.localExclude,
      label: '.git/info/exclude (not committed)',
      path: localExclude,
      dir: '',
      exists: true,
    ));
    targets.add(IgnoreTarget(
      kind: IgnoreTargetKind.globalIgnore,
      label: 'global ignore (all repos)',
      path: globalIgnore,
      dir: '',
      exists: true,
    ));
    return targets;
  }

  /// The folder a *folder* scope should ignore: a folder row is itself, a file
  /// row is its parent. A top-level file has no folder to name.
  static String? _folderFor(String relative, {required bool isFolderRow}) {
    if (isFolderRow) return relative.isEmpty ? null : relative;
    if (!relative.contains('/')) return null;
    final folder = relative.substring(0, relative.lastIndexOf('/'));
    return folder.isEmpty ? null : folder;
  }

  static String _folderOf(String path) {    final clean = _noTrailingSlash(path);
    final slash = clean.lastIndexOf('/');
    return slash < 0 ? '' : clean.substring(0, slash);
  }

  static String _withoutPrefix(String path, String dir) {
    final prefix = '$dir/';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  static String _noTrailingSlash(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  static String _escapeSegments(String path) => path.split('/').map(_escapeSegment).join('/');

  /// A literal name inside a pattern: glob characters and a leading `!`/`#`
  /// lose their meaning, which is what a filename needs.
  static String _escapeSegment(String name) {
    final buffer = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      final char = name[i];
      if (char == '*' || char == '?' || char == '[' || char == ']') {
        buffer.write(r'\');
      } else if (i == 0 && (char == '!' || char == '#')) {
        buffer.write(r'\');
      }
      buffer.write(char);
    }
    var out = buffer.toString();
    // A trailing space must be escaped or git trims it.
    out = out.replaceAllMapped(RegExp(r' +$'), (match) => r'\ ' * match[0]!.length);
    return out;
  }
}
