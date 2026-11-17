import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/browser.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/git_repo.dart';
import 'package:purrage/state/ignore_files.dart';
import 'package:purrage/state/status.dart';

import 'support/fake_repo.dart';
import 'support/temp_dirs.dart';

/// A fake whose `gitlinks` and `checkIgnore` wait until the test lets them go.
class HeldRepo extends FakeRepo {
  HeldRepo(super.rows);

  final links = Completer<Set<String>>();
  final ignore = Completer<IgnoreMatch?>();

  @override
  Future<Set<String>> gitlinks() => links.future;

  @override
  Future<IgnoreMatch?> checkIgnore(String path) => ignore.future;
}

const _rows = [
  StatusRow(section: Section.untracked, kind: RowKind.untracked, path: 'lib/', code: '??'),
];

void main() {
  test('Changes.idle waits for the nested probe that load() started', () async {
    final repo = HeldRepo(_rows);
    final changes = Changes(repo);
    await changes.load();

    var done = false;
    final idle = changes.idle().then((_) => done = true);
    await pumpEventQueue();
    expect(done, isFalse, reason: 'the probe is still held');

    repo.nested.add('lib');
    repo.links.complete({'lib'});
    await idle;
    expect(done, isTrue);
    expect(changes.isNested(changes.visible.single), isTrue);
  });

  test('a disposed Changes stops its probe and redraws nothing', () async {
    final repo = HeldRepo(_rows);
    final changes = Changes(repo);
    await changes.load();
    var redraws = 0;
    changes.addListener(() => redraws++);
    changes.dispose();

    repo.links.complete({'lib'});
    await changes.idle();
    expect(redraws, 0);
  });

  test('IgnorePaneState.idle waits for a focusPath nobody awaited', () async {
    final repo = HeldRepo(_rows);
    final pane = IgnorePaneState(repo);
    unawaited(pane.focusPath('lib/a.txt'));

    var done = false;
    final idle = pane.idle().then((_) => done = true);
    await pumpEventQueue();
    expect(done, isFalse);

    repo.ignore.complete(null);
    await idle;
    expect(done, isTrue);
    expect(pane.focusedPath, 'lib/a.txt');
  });

  test('RepoBrowser.idle waits for a scan, and a second request joins it', () async {
    final dir = keepForCleanup(await Directory.systemTemp.createTemp('purrage_'));
    addTearDown(() => deleteWithRetry(dir));
    await Directory('${dir.path}/one/.git').create(recursive: true);

    final browser = RepoBrowser(startDirectory: dir.path);
    addTearDown(browser.dispose);
    final first = browser.scan();
    final second = browser.rescan();
    expect(identical(first, second), isTrue, reason: 'folded into the running walk');

    await browser.idle();
    expect(browser.scanning, isFalse);
    expect(browser.repos.single, endsWith('/one'));
  });
}
