/// The `git status --porcelain=v1 -z` model.
///
/// One call feeds everything the app shows: each entry becomes one or two
/// rows, because a file can be staged and changed at the same time.
library;

/// Where a row sits in the list.
enum Section { conflicts, staged, changed, untracked }

/// What happened to the file, from the side that produced the row.
enum RowKind { added, modified, deleted, renamed, copied, typeChanged, untracked, conflicted }

/// One line of the list: a path, the section it belongs to, and the two
/// porcelain columns it came from.
class StatusRow {
  const StatusRow({
    required this.section,
    required this.kind,
    required this.path,
    required this.code,
    this.origPath,
  });

  final Section section;
  final RowKind kind;

  /// Path relative to the repository root, as git prints it (forward slashes).
  final String path;

  /// The previous path of a rename or copy, when git reported one.
  final String? origPath;

  /// The two porcelain columns, for the row's side only (`M `, ` M`, `??`, `UU`).
  final String code;

  bool get isStaged => section == Section.staged;

  bool get isConflict => section == Section.conflicts;

  /// The name shown in the list: the last segment, with a slash for folders.
  String get name {
    final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final slash = trimmed.lastIndexOf('/');
    final base = slash < 0 ? trimmed : trimmed.substring(slash + 1);
    return path.endsWith('/') ? '$base/' : base;
  }

  /// The folder shown after the name, or an empty string at the root.
  String get folder {
    final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final slash = trimmed.lastIndexOf('/');
    return slash < 0 ? '' : trimmed.substring(0, slash);
  }

  @override
  String toString() => '${section.name} ${code.trim()} $path';
}

/// Codes that mean a merge conflict, whatever side they are on.
const _conflictCodes = {'DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU'};

/// Parses the NUL-separated output of
/// `git status --porcelain=v1 -z --untracked-files=all --find-renames`.
///
/// Ignored entries (`!!`) are dropped: the app never lists them.
List<StatusRow> parseStatusZ(String raw) {
  final rows = <StatusRow>[];
  if (raw.isEmpty) return rows;
  final tokens = raw.split('\u0000');
  for (var i = 0; i < tokens.length; i++) {
    final record = tokens[i];
    if (record.length < 4) continue; // "XY p" is the shortest real record
    final x = record[0];
    final y = record[1];
    final code = '$x$y';
    final path = record.substring(3);

    String? origPath;
    if (x == 'R' || x == 'C' || y == 'R' || y == 'C') {
      // -z puts the rename source in the next token, after the new path.
      if (i + 1 < tokens.length) {
        origPath = tokens[++i];
      }
    }

    if (code == '!!') continue;

    if (code == '??') {
      rows.add(StatusRow(
        section: Section.untracked,
        kind: RowKind.untracked,
        path: path,
        code: code,
      ));
      continue;
    }

    if (_conflictCodes.contains(code)) {
      rows.add(StatusRow(
        section: Section.conflicts,
        kind: RowKind.conflicted,
        path: path,
        code: code,
        origPath: origPath,
      ));
      continue;
    }

    if (x != ' ' && x != '?') {
      rows.add(StatusRow(
        section: Section.staged,
        kind: _kindFor(x),
        path: path,
        code: code,
        origPath: x == 'R' || x == 'C' ? origPath : null,
      ));
    }
    if (y != ' ' && y != '?') {
      rows.add(StatusRow(
        section: Section.changed,
        kind: _kindFor(y),
        path: path,
        code: code,
        origPath: y == 'R' || y == 'C' ? origPath : null,
      ));
    }
  }
  return rows;
}

RowKind _kindFor(String column) => switch (column) {
      'A' => RowKind.added,
      'D' => RowKind.deleted,
      'R' => RowKind.renamed,
      'C' => RowKind.copied,
      'T' => RowKind.typeChanged,
      _ => RowKind.modified,
    };
