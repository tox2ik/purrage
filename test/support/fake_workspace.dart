import 'package:purrage/state/browser.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/console.dart';
import 'package:purrage/state/editors.dart';
import 'package:purrage/state/prefs.dart';
import 'package:purrage/state/system.dart';
import 'package:purrage/state/workspace.dart';

import 'fake_repo.dart';
import 'fake_system.dart';

/// Settings kept in memory: no `prefs.json` is read or written.
class MemoryPrefs extends Prefs {
  MemoryPrefs([this.saved]) : super(directory: 'memory');

  String? saved;
  int loads = 0;

  @override
  Future<void> load() async => loads++;

  @override
  String? get editorCommand => saved;

  @override
  Future<void> setEditorCommand(String? value) async => saved = value;
}

/// A workspace over [repo] that touches no git, no file and no process: the
/// Browse walk reads [lister], editors resolve through [runner] and the given
/// [which] answers, settings live in memory.
Workspace fakeWorkspace(
  FakeRepo repo, {
  RepoOpener? opener,
  Changes? changes,
  ConsoleLog? console,
  FakeRunner? runner,
  FakeLister? lister,
  Map<String, String> which = const {},
  MemoryPrefs? prefs,
  Duration probeDelay = const Duration(milliseconds: 250),
}) {
  final memory = prefs ?? MemoryPrefs();
  return Workspace(
    repo: repo,
    opener: opener,
    changes: changes,
    console: console,
    prefs: memory,
    probeDelay: probeDelay,
    editors: Editors(
      prefs: memory,
      which: (exe) async => which[exe],
      exists: (_) async => false,
      gitEditor: () async => null,
      nvimQtCandidates: () async => const [],
      env: const Env({}),
      runner: runner ?? FakeRunner(),
    ),
    browser: (start, onReport) => RepoBrowser(
      startDirectory: start,
      onReport: onReport,
      lister: lister ?? FakeLister(),
      env: const Env({}),
    ),
  );
}
