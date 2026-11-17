import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/status.dart';
import 'package:purrage/ui/changes_view.dart';
import 'package:purrage/ui/shell.dart';
import 'package:purrage/ui/window_title.dart';

import 'support/fake_repo.dart';
import 'support/fake_workspace.dart';

StatusRow row(String path, Section section) => StatusRow(
      section: section,
      kind: section == Section.untracked ? RowKind.untracked : RowKind.modified,
      path: path,
      code: section == Section.untracked ? '??' : 'M ',
    );

Future<ShellState> openShell(WidgetTester tester, FakeRepo repo) async {
  final changes = Changes(repo);
  await changes.load();
  await tester.pumpWidget(
    MaterialApp(home: Shell(workspace: fakeWorkspace(repo, changes: changes))),
  );
  await tester.pump();
  return tester.state<ShellState>(find.byType(Shell));
}

Finder get messageField => find.byType(TextField).last;

void main() {
  group('the commit bar', () {
    testWidgets('with nothing staged: "Commit", disabled, and the reason shown', (tester) async {
      await openShell(tester, FakeRepo([row('a.txt', Section.untracked)]));

      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Commit'));
      expect(button.onPressed, isNull);
      expect(find.text('Commit 0'), findsNothing);
      const reason = 'Nothing is staged: add a file first (space or a)';
      expect(find.byTooltip(reason), findsOneWidget);
      expect(tester.widget<TextField>(messageField).decoration?.hintText, reason);
      expect(tester.widget<TextField>(messageField).readOnly, isTrue);
    });

    testWidgets('Ctrl+Enter commits, and the keys go back to the list', (tester) async {
      final repo = FakeRepo([row('a.txt', Section.staged)]);
      final shell = await openShell(tester, repo);
      expect(find.text('Commit 1'), findsOneWidget);

      await tester.tap(messageField);
      await tester.pump();
      await tester.enterText(messageField, 'state: one line');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump();

      expect(repo.commits, ['state: one line']);
      expect(shell.commitFocus.hasFocus, isFalse);
      expect(shell.listFocus.hasFocus, isTrue);
      expect(shell.commitController.text, isEmpty);
    });

    testWidgets('Enter still commits', (tester) async {
      final repo = FakeRepo([row('a.txt', Section.staged)]);
      await openShell(tester, repo);
      await tester.tap(messageField);
      await tester.enterText(messageField, 'ui: enter');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
      expect(repo.commits, ['ui: enter']);
    });

    testWidgets('a summary over 72 characters gets a quiet counter', (tester) async {
      await openShell(tester, FakeRepo([row('a.txt', Section.staged)]));
      await tester.enterText(messageField, 'x' * 72);
      await tester.pump();
      expect(find.text('72/72'), findsNothing);

      await tester.enterText(messageField, 'x' * 73);
      await tester.pump();
      expect(find.text('73/72'), findsOneWidget);
    });
  });

  group('the repository is named', () {
    testWidgets('the header shows the path and the branch', (tester) async {
      final repo = FakeRepo([row('a.txt', Section.untracked)])..branch = 'feature/x';
      await openShell(tester, repo);

      final header = find.byType(RepoHeader);
      expect(find.descendant(of: header, matching: find.text('C:/repo')), findsOneWidget);
      expect(find.descendant(of: header, matching: find.text('on feature/x')), findsOneWidget);
    });

    testWidgets('a detached HEAD says so', (tester) async {
      await openShell(tester, FakeRepo([])..branch = null);
      expect(find.text('detached HEAD'), findsOneWidget);
    });

    testWidgets('the window title gets the folder', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        WindowTitle.channel,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(WindowTitle.channel, null),
      );

      await openShell(tester, FakeRepo([], path: 'C:/work/purrage-2'));
      expect(calls.single.method, 'setRepository');
      expect(calls.single.arguments, 'purrage-2');
      expect(WindowTitle.forPath('C:/work/purrage-2/'), 'purrage-2 - Purrage');
    });
  });
}
