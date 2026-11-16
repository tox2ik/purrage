import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glustered/state/changes.dart';
import 'package:glustered/state/status.dart';
import 'package:glustered/ui/shell.dart';

import 'support/fake_repo.dart';

StatusRow untracked(String path) => StatusRow(
      section: Section.untracked,
      kind: RowKind.untracked,
      path: path,
      code: '??',
    );

Future<Changes> openShell(WidgetTester tester, FakeRepo repo) async {
  final changes = Changes(repo);
  await changes.load();
  await tester.pumpWidget(MaterialApp(home: Shell(repo: repo, seeded: changes)));
  await tester.pump();
  return changes;
}

void main() {
  testWidgets('i writes the literal rule and reports it', (tester) async {
    final repo = FakeRepo([untracked('notes.md')]);
    await openShell(tester, repo);
    expect(find.text('notes.md'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pump();
    await tester.pump();

    expect(repo.writes.single, 'C:/repo/.gitignore|/notes.md');
    expect(find.textContaining('ignored'), findsOneWidget);
    expect(find.text('notes.md'), findsNothing);
  });

  testWidgets('Shift+I opens the dialog and writes where it says', (tester) async {
    final repo = FakeRepo([untracked('notes.md')]);
    await openShell(tester, repo);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'I');
    await tester.pump();
    await tester.pump();

    expect(find.text('Ignore notes.md'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Ignore'));
    await tester.pump();
    await tester.pump();

    expect(repo.writes.single, 'C:/repo/.gitignore|/notes.md');
    expect(find.textContaining('wrote a rule'), findsOneWidget);
  });

  testWidgets('a refusal is shown, not swallowed', (tester) async {
    final repo = FakeRepo([untracked('Makefile')]);
    await openShell(tester, repo);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'I');
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('this extension').first);
    await tester.pump();
    // The button is disabled when the scope makes no rule, so nothing is written.
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Ignore'));
    expect(button.onPressed, isNull);
    expect(repo.writes, isEmpty);
  });
}
