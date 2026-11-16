/// Editor detection and launching: which editor opens `{file}`, and how.
///
/// The order is the one in `PLAN.md`: the saved choice, `nvim-qt`, a resolvable
/// `git var GIT_EDITOR`, `VISUAL`, `EDITOR`, known editors on `PATH`, then
/// Notepad. Nothing here throws for a missing editor; only [Editors.open] fails,
/// with an [EditorException] the UI can show.
library;

import 'dart:io';

import 'prefs.dart';

/// A failure the user can act on, with no stack trace in the message.
class EditorException implements Exception {
  EditorException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One editor the app can start, as a command template.
class EditorOption {
  const EditorOption({
    required this.id,
    required this.label,
    required this.command,
    this.detected = true,
    this.path,
  });

  final String id;
  final String label;

  /// The template handed to [Editors.expand]; `{file}`, may use `{line}`.
  final String command;

  /// False only for the "nothing found" placeholder.
  final bool detected;

  /// The executable or shim that was resolved, when there is one.
  final String? path;

  @override
  String toString() => '$id: $command';
}

/// Resolves a bare executable name to a full path, like `where` does.
typedef Which = Future<String?> Function(String exe);

/// True when an absolute path is a file that exists.
typedef Exists = bool Function(String path);

/// Reads `git var GIT_EDITOR`, or null when git has no answer.
typedef GitEditorReader = Future<String?> Function();

/// The editors looked up on `PATH`, in the order `PLAN.md` lists them.
class KnownEditor {
  const KnownEditor(this.id, this.label, this.exe);

  final String id;
  final String label;
  final String exe;
}

const List<KnownEditor> knownEditors = [
  KnownEditor('code', 'VS Code', 'code'),
  KnownEditor('nvim', 'Neovim', 'nvim'),
  KnownEditor('gvim', 'gvim', 'gvim'),
  KnownEditor('notepad++', 'Notepad++', 'notepad++'),
  KnownEditor('zed', 'Zed', 'zed'),
  KnownEditor('hx', 'Helix', 'hx'),
  KnownEditor('subl', 'Sublime Text', 'subl'),
  KnownEditor('cursor', 'Cursor', 'cursor'),
  KnownEditor('idea64', 'IntelliJ IDEA', 'idea64'),
];

/// Detection and launch. Every side effect is injectable, so the precedence
/// table is a plain unit test with no processes and no filesystem.
class Editors {
  Editors({
    this.prefs,
    Which? which,
    Exists? exists,
    GitEditorReader? gitEditor,
    List<String> Function()? nvimQtCandidates,
    Map<String, String>? environment,
  }) : _which = which ?? _systemWhich,
       _exists = exists ?? _fileExists,
       _gitEditor = gitEditor ?? _systemGitEditor,
       _nvimQtCandidates = nvimQtCandidates ?? _windowsNvimQtCandidates,
       _environment = environment ?? Platform.environment;

  final Prefs? prefs;
  final Which _which;
  final Exists _exists;
  final GitEditorReader _gitEditor;
  final List<String> Function() _nvimQtCandidates;
  final Map<String, String> _environment;

  /// Every editor found, best first. A saved choice always leads; Notepad is
  /// the last resort; when literally nothing resolves the single entry is
  /// marked not detected instead of throwing.
  Future<List<EditorOption>> detect() async {
    await prefs?.load();
    final found = <EditorOption>[];

    final saved = prefs?.editorCommand;
    if (saved != null) {
      _append(
        found,
        EditorOption(
          id: 'saved',
          label: 'Your choice',
          command: saved,
          path: exeOf(saved),
        ),
      );
    }

    final nvimQt = await _nvimQtPath();
    if (nvimQt != null) _append(found, _fromPath('nvim-qt', 'nvim-qt', nvimQt));

    final git = await _fromCommand(
      'git',
      'git var GIT_EDITOR',
      await _gitEditedByGit(),
    );
    if (git != null) _append(found, git);

    final visual = await _fromCommand(
      'visual',
      'VISUAL',
      _environment['VISUAL'],
    );
    if (visual != null) _append(found, visual);

    final editor = await _fromCommand(
      'editor',
      'EDITOR',
      _environment['EDITOR'],
    );
    if (editor != null) _append(found, editor);

    for (final known in knownEditors) {
      final path = await _which(known.exe);
      if (path != null) _append(found, _fromPath(known.id, known.label, path));
    }

    _append(
      found,
      const EditorOption(
        id: 'notepad',
        label: 'Notepad',
        command: 'notepad {file}',
      ),
    );

    if (found.isEmpty) {
      return const [
        EditorOption(
          id: 'none',
          label: 'No editor found',
          command: '',
          detected: false,
        ),
      ];
    }
    return found;
  }

  /// The editor to start now: the saved choice, else the first detected one.
  Future<EditorOption> chosenOption() async => (await detect()).first;

  /// The command template in use, for the Settings field.
  Future<String> chosen() async => (await chosenOption()).command;

  /// Open [file] at [line] in the chosen editor, detached from this app.
  Future<void> open({required String file, int? line}) async {
    final option = await chosenOption();
    final command = option.command.trim();
    if (command.isEmpty) {
      throw EditorException('No editor is set. Pick one in Settings (Alt+2).');
    }
    final tokens = expand(command, file: file, line: line);
    final exe = tokens.first;
    final args = tokens.sublist(1);
    try {
      if (_isShim(exe)) {
        // A `.cmd` or `.bat` shim needs `cmd /c start` to open a window of its
        // own; `start` takes an empty title before the command.
        await Process.start('cmd', [
          '/c',
          'start',
          '',
          exe,
          ...args,
        ], mode: ProcessStartMode.detached);
      } else {
        await Process.start(exe, args, mode: ProcessStartMode.detached);
      }
    } on ProcessException catch (error) {
      throw EditorException(
        'Could not start ${option.label}: ${error.message}',
      );
    }
  }

  /// Split a command template into an executable and its arguments, honouring
  /// double quotes so a path with spaces stays one token.
  static List<String> splitCommand(String command) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    var hasToken = false;
    for (var i = 0; i < command.length; i++) {
      final char = command[i];
      if (char == '"') {
        inQuotes = !inQuotes;
        hasToken = true;
      } else if (!inQuotes && (char == ' ' || char == '\t')) {
        if (hasToken) {
          tokens.add(buffer.toString());
          buffer.clear();
          hasToken = false;
        }
      } else {
        buffer.write(char);
        hasToken = true;
      }
    }
    if (hasToken) tokens.add(buffer.toString());
    return tokens;
  }

  /// Fill `{file}` and `{line}` in a template and split it. A file with spaces
  /// is quoted first, so it survives the split. No `{file}` appends the path.
  static List<String> expand(
    String template, {
    required String file,
    int? line,
  }) {
    final quoted = file.contains(' ') ? '"$file"' : file;
    var text = template;
    if (text.contains('{file}')) {
      text = text.replaceAll('{file}', quoted);
    } else {
      text = '$text $quoted';
    }
    text = text.replaceAll('{line}', '${line ?? 1}');
    return splitCommand(text);
  }

  /// The executable at the head of a template, or null for an empty one.
  static String? exeOf(String command) {
    final tokens = splitCommand(command);
    return tokens.isEmpty ? null : tokens.first;
  }

  static bool _isShim(String exe) {
    final lower = exe.toLowerCase();
    return lower.endsWith('.cmd') || lower.endsWith('.bat');
  }

  static String _quote(String path) => '"$path"';

  EditorOption _fromPath(String id, String label, String path) => EditorOption(
    id: id,
    label: label,
    command: '${_quote(path)} {file}',
    path: path,
  );

  /// An editor named by a command string (`git var`, `VISUAL`, `EDITOR`), kept
  /// only when its executable really resolves on this machine.
  Future<EditorOption?> _fromCommand(
    String id,
    String label,
    String? raw,
  ) async {
    final command = raw?.trim();
    if (command == null || command.isEmpty) return null;
    final exe = exeOf(command);
    if (exe == null) return null;
    if (!await _resolvable(exe)) return null;
    return EditorOption(
      id: id,
      label: label,
      command: command.contains('{file}') ? command : '$command {file}',
      path: exe,
    );
  }

  Future<String?> _gitEditedByGit() async {
    try {
      return await _gitEditor();
    } on Exception {
      return null;
    }
  }

  /// `vi` and `vim` are reported by git but usually absent on Windows, so they
  /// only count when `vi` itself is on `PATH`.
  Future<bool> _resolvable(String exe) async {
    final name = _baseName(exe);
    if (name == 'vi' || name == 'vim') return await _which('vi') != null;
    if (exe.contains('/') || exe.contains(r'\')) return _exists(exe);
    return await _which(exe) != null;
  }

  static String _baseName(String exe) {
    final tail = exe.replaceAll(r'\', '/').split('/').last.toLowerCase();
    return tail.endsWith('.exe') ? tail.substring(0, tail.length - 4) : tail;
  }

  Future<String?> _nvimQtPath() async {
    final onPath = await _which('nvim-qt');
    if (onPath != null) return onPath;
    for (final candidate in _nvimQtCandidates()) {
      if (_exists(candidate)) return candidate;
    }
    return null;
  }

  /// Add [option] unless the same command is already listed.
  static void _append(List<EditorOption> found, EditorOption option) {
    if (option.command.trim().isEmpty) return;
    final command = option.command.replaceAll('/', r'\').toLowerCase();
    if (found.any(
      (other) => other.command.replaceAll('/', r'\').toLowerCase() == command,
    )) {
      return;
    }
    found.add(option);
  }

  /// `where` can find several matches (the exe, then a `.bat` wrapper earlier on
  /// PATH). A `.bat`/`.cmd` is started through `cmd /c start`, which shows a
  /// console window, so a real `.exe` is preferred whenever one is listed.
  static Future<String?> _systemWhich(String exe) async {
    try {
      final result = await Process.run('where', [exe], runInShell: false);
      if (result.exitCode != 0) return null;
      final found = (result.stdout as String)
          .split(RegExp(r'\r?\n'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (found.isEmpty) return null;
      // `.exe` first, then a shim Windows can start through cmd, then anything.
      final exePath = found.firstWhere(
        (value) => value.toLowerCase().endsWith('.exe'),
        orElse: () => '',
      );
      if (exePath.isNotEmpty) return exePath;
      final shim = found.firstWhere(
        (value) {
          final lower = value.toLowerCase();
          return lower.endsWith('.cmd') || lower.endsWith('.bat');
        },
        orElse: () => '',
      );
      return shim.isNotEmpty ? shim : found.first;
    } on ProcessException {
      return null;
    }
  }

  static bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } on FileSystemException {
      return false;
    }
  }

  static Future<String?> _systemGitEditor() async {
    try {
      final result = await Process.run('git', [
        'var',
        'GIT_EDITOR',
      ], runInShell: false);
      if (result.exitCode != 0) return null;
      final out = (result.stdout as String).trim();
      return out.isEmpty ? null : out;
    } on ProcessException {
      return null;
    }
  }

  /// `%ProgramFiles%\neovim-qt*\bin\nvim-qt.exe`, without pulling in a glob
  /// package: walk the one level that can match.
  static List<String> _windowsNvimQtCandidates() {
    final roots = [
      Platform.environment['ProgramFiles'],
      Platform.environment['ProgramFiles(x86)'],
    ].whereType<String>().where((root) => root.trim().isNotEmpty);
    final found = <String>[];
    for (final root in roots) {
      try {
        for (final entry in Directory(root).listSync(followLinks: false)) {
          final name = entry.uri.pathSegments.lastWhere(
            (part) => part.isNotEmpty,
            orElse: () => '',
          );
          if (!name.toLowerCase().startsWith('neovim-qt')) continue;
          final exe = '${entry.path.replaceAll(r'\', '/')}/bin/nvim-qt.exe';
          found.add(exe);
        }
      } on FileSystemException {
        // An unreadable Program Files is simply no candidates.
      }
    }
    return found;
  }
}
