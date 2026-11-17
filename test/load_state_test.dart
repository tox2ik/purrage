import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/git_repo.dart';
import 'package:purrage/state/status.dart';
import 'package:purrage/ui/file_list.dart';
import 'package:purrage/ui/shell.dart';

import 'support/fake_repo.dart';
import 'support/fake_workspace.dart';

/// The shell starts the workspace, which loads the changes itself, so its
/// first frames are the ones a user sees before `git status` has answered.
Future<Changes> pumpShell(WidgetTester tester, FakeRepo repo) async {
  final changes = Changes(repo);
  await tester.pumpWidget(MaterialApp(home: Shell(workspace: fakeWorkspace(repo, changes: changes))));
  return changes;
}

void main() {
  group('the empty list says what is known', () {
    testWidgets('while status is held open: quiet, then "reading git status…"', (tester) async {
      final repo = FakeRepo([]);
      final held = repo.hold('status');
      final changes = await pumpShell(tester, repo);
      expect(changes.loadState, LoadState.loading);

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(EmptyList.reading), findsNothing);
      expect(find.text(EmptyList.clean), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(EmptyList.reading), findsOneWidget);
      expect(find.text(EmptyList.clean), findsNothing);

      held.complete();
      await tester.pump();
      await tester.pump();
      expect(changes.loadState, LoadState.loaded);
      expect(find.text(EmptyList.reading), findsNothing);
      expect(find.text(EmptyList.clean), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('a failed load shows the banner and nothing else', (tester) async {
      final repo = FakeRepo([]);
      repo.failures['status'] = GitException('git status failed: boom');
      final changes = await pumpShell(tester, repo);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(changes.loadState, LoadState.failed);
      expect(find.text('git status failed: boom'), findsOneWidget);
      expect(find.text(EmptyList.clean), findsNothing);
      expect(find.text(EmptyList.reading), findsNothing);
    });

    testWidgets('an empty successful load is a clean tree', (tester) async {
      final changes = await pumpShell(tester, FakeRepo([]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(changes.loadState, LoadState.loaded);
      expect(find.text(EmptyList.clean), findsOneWidget);
    });
  });

  group('the nested-repository probe', () {
    test('does not notify when it found nothing', () async {
      final changes = Changes(FakeRepo([_untracked('plain/')]));
      var notified = 0;
      changes.addListener(() => notified++);
      await changes.load();
      final afterLoad = notified;
      await changes.idle();
      expect(notified, afterLoad);
      changes.dispose();
    });

    test('notifies once when it found a repository', () async {
      final repo = FakeRepo([_untracked('inner/')])..nested.add('inner');
      final changes = Changes(repo);
      var notified = 0;
      changes.addListener(() => notified++);
      await changes.load();
      final afterLoad = notified;
      await changes.idle();
      expect(notified, afterLoad + 1);
      expect(changes.isNested(changes.rows.single), isTrue);
      changes.dispose();
    });
  });
}

StatusRow _untracked(String path) =>
    StatusRow(section: Section.untracked, kind: RowKind.untracked, path: path, code: '??');
