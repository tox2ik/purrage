import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/console.dart';
import 'package:purrage/state/git_repo.dart';
import 'package:purrage/state/status.dart';
import 'package:purrage/ui/shell.dart';
import 'package:purrage/ui/widgets.dart';

import 'support/fake_repo.dart';
import 'support/fake_workspace.dart';

StatusRow row(String path, Section section) => StatusRow(
      section: section,
      kind: section == Section.untracked ? RowKind.untracked : RowKind.modified,
      path: path,
      code: section == Section.untracked ? '??' : 'M ',
    );

Future<Changes> openShell(WidgetTester tester, FakeRepo repo, {ConsoleLog? console}) async {
  final changes = Changes(repo);
  await changes.load();
  await tester.pumpWidget(
    MaterialApp(home: Shell(workspace: fakeWorkspace(repo, changes: changes, console: console))),
  );
  await tester.pump();
  return changes;
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {String? character}) async {
  await tester.sendKeyEvent(key, character: character);
  await tester.pump();
  await tester.pump();
}

/// Shift+I, then the frame that gives the dialog its keys.
Future<void> openDialog(WidgetTester tester) async {
  await press(tester, LogicalKeyboardKey.keyI, character: 'I');
  await tester.pump();
}

void main() {
  group('the ignore dialog', () {
    testWidgets('can be completed with keys only', (tester) async {
      final repo = FakeRepo([
        for (final name in ['a.log', 'b.log', 'c.log']) row(name, Section.untracked),
      ]);
      final changes = await openShell(tester, repo);
      changes.selectAll();
      await tester.pump();

      await openDialog(tester);
      expect(find.text('Ignore 3 files'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.digit2, character: '2');
      // Three rows, one extension: the preview says so and lists the rule once.
      expect(find.text('3 files → 1 rule'), findsOneWidget);
      expect(find.text('*.log'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.keyJ, character: 'j');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Ignore 3 files'), findsNothing);
      expect(repo.writes, ['C:/repo/.git/info/exclude|*.log']);
    });

    testWidgets('letters pick the scope too, and Esc cancels', (tester) async {
      final repo = FakeRepo([row('src/a.log', Section.untracked)]);
      await openShell(tester, repo);

      await openDialog(tester);
      await press(tester, LogicalKeyboardKey.keyD, character: 'd');
      expect(find.text('/src/'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.keyF, character: 'f');
      expect(find.text('/src/a.log'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ignore src/a.log'), findsNothing);
      expect(repo.writes, isEmpty);
    });

    testWidgets('says which rows are already ignored, before the click', (tester) async {
      final repo = FakeRepo([row('a.log', Section.untracked)]);
      repo.ignored['a.log'] = const IgnoreMatch(
        source: 'C:/repo/.gitignore',
        line: 3,
        pattern: '*.log',
        path: 'a.log',
      );
      await openShell(tester, repo);

      await openDialog(tester);
      expect(find.text('a.log: already ignored by `*.log` in .gitignore:3'), findsOneWidget);
    });

    testWidgets('targets are clickable rows with a tooltip', (tester) async {
      final repo = FakeRepo([row('a.log', Section.untracked)]);
      await openShell(tester, repo);
      await openDialog(tester);

      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(HoverRow)),
        findsNWidgets(3),
      );
      expect(find.byTooltip('Write the rule to C:/repo/.gitignore'), findsOneWidget);
      await tester.tap(find.byTooltip('Write the rule to C:/repo/.git/info/exclude'));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.writes, ['C:/repo/.git/info/exclude|/a.log']);
    });

    testWidgets('has no stop-tracking choice, and ignoring a staged row keeps it', (tester) async {
      final repo = FakeRepo([row('keep.txt', Section.staged)]);
      await openShell(tester, repo);

      await openDialog(tester);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.textContaining('stop tracking'), findsNothing);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.writes, ['C:/repo/.gitignore|/keep.txt']);
      expect(repo.rows.map((r) => r.path), ['keep.txt']);
      expect(find.text('keep.txt'), findsOneWidget);
    });
  });

  group('untrack', () {
    testWidgets('untracks within 900 ms share one notice, each has a console row', (tester) async {
      final console = ConsoleLog();
      final repo = FakeRepo([
        for (final name in ['a.txt', 'b.txt', 'c.txt']) row(name, Section.staged),
      ]);
      await openShell(tester, repo, console: console);
      final before = console.entries.length;

      await press(tester, LogicalKeyboardKey.keyU, character: 'u');
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
      await press(tester, LogicalKeyboardKey.keyU, character: 'u');

      // 500 ms after the second one: the window restarted, nothing yet.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('stopped tracking'), findsNothing);

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('stopped tracking a.txt, b.txt (kept on disk)'), findsOneWidget);

      final untracks = console.entries
          .take(console.entries.length - before)
          .where((entry) => entry.action == 'untrack')
          .toList();
      expect(untracks, hasLength(2));
      expect(repo.rows.map((r) => r.path), ['c.txt']);

      // Let the notice run out so no timer outlives the test.
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpWidget(const SizedBox());
      console.dispose();
    });

    testWidgets('an untrack after the window gets a notice of its own', (tester) async {
      final repo = FakeRepo([
        for (final name in ['a.txt', 'b.txt']) row(name, Section.staged),
      ]);
      await openShell(tester, repo);

      await press(tester, LogicalKeyboardKey.keyU, character: 'u');
      await tester.pump(const Duration(milliseconds: 950));
      expect(find.text('stopped tracking a.txt (kept on disk)'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.keyU, character: 'u');
      await tester.pump(const Duration(milliseconds: 950));
      expect(find.text('stopped tracking b.txt (kept on disk)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
    });
  });
}
