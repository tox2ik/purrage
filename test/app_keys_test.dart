import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/status.dart';
import 'package:purrage/ui/app_keys.dart';
import 'package:purrage/ui/help_view.dart';
import 'package:purrage/ui/shell.dart';

import 'support/fake_repo.dart';
import 'support/fake_workspace.dart';

StatusRow untracked(String path) =>
    StatusRow(section: Section.untracked, kind: RowKind.untracked, path: path, code: '??');

Future<(ShellState, FakeRepo)> openShell(WidgetTester tester) async {
  final repo = FakeRepo([untracked('a.txt'), untracked('b.txt')]);
  await tester.pumpWidget(MaterialApp(home: Shell(workspace: fakeWorkspace(repo))));
  await tester.pump();
  return (tester.state<ShellState>(find.byType(Shell)), repo);
}

void main() {
  test('the help table is the bindings, line for line', () {
    final lines = helpLines(allBindings);
    expect(keyTable.map((help) => help.keys), lines.map((binding) => binding.keys));
    expect(keyTable.first.what, 'Changes, Browse, Settings, Console, Help');
  });

  test('every activator sends an intent, and no activator is bound twice', () {
    final all = [for (final binding in allBindings) ...binding.activators];
    final map = shortcutsOf(allBindings);
    expect(map.length, all.length);
    expect(
      map.values.whereType<ShowModeIntent>().map((intent) => intent.mode).toSet(),
      Mode.values.toSet(),
      reason: 'Alt+<n> for every mode, and ? for Help',
    );
  });

  testWidgets('a key goes through Shortcuts to the workspace', (tester) async {
    final (shell, repo) = await openShell(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(shell.workspace.changes.selected?.path, 'b.txt');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(repo.calls, contains('track'));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('Alt+digit and ? change the mode', (tester) async {
    final (shell, _) = await openShell(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(shell.mode, Mode.console);

    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pump();
    expect(shell.mode, Mode.help);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('plain letters reach the filter field, not the list', (tester) async {
    final (shell, repo) = await openShell(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await tester.pump();
    expect(shell.filterFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(repo.calls, isNot(contains('track')));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
