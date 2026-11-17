import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/status.dart';
import 'package:purrage/state/system.dart';
import 'package:purrage/ui/browse_view.dart';
import 'package:purrage/ui/debug_bar.dart';
import 'package:purrage/ui/mode_rail.dart';
import 'package:purrage/ui/shell.dart';

import 'support/fake_repo.dart';
import 'support/fake_system.dart';
import 'support/fake_workspace.dart';

StatusRow untracked(String path) =>
    StatusRow(section: Section.untracked, kind: RowKind.untracked, path: path, code: '??');

/// A home folder with two checkouts for Browse.
FakeLister twoRepos() => FakeLister(
      dirs: {
        'C:/repo': [
          const DirEntry(r'C:\repo\one', isDirectory: true),
          const DirEntry(r'C:\repo\two', isDirectory: true),
        ],
      },
      existing: {'C:/repo/one/.git', 'C:/repo/two/.git'},
    );

class Opened {
  final List<String> paths = [];
}

Future<(ShellState, FakeRepo)> openShell(
  WidgetTester tester, {
  List<StatusRow>? rows,
  Opened? opened,
  MemoryPrefs? prefs,
}) async {
  final repo = FakeRepo(rows ?? [for (var i = 0; i < 40; i++) untracked('f${i.toString().padLeft(2, '0')}.txt')]);
  final workspace = fakeWorkspace(
    repo,
    lister: twoRepos(),
    which: {'code': r'C:\bin\code.exe'},
    prefs: prefs,
    opener: opened == null
        ? null
        : (path) async {
            opened.paths.add(path);
            return FakeRepo(const [], path: path);
          },
  );
  await tester.pumpWidget(MaterialApp(home: Shell(workspace: workspace)));
  await tester.pump();
  await tester.pump();
  return (tester.state<ShellState>(find.byType(Shell)), repo);
}

Future<void> alt(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pump();
  await tester.pump();
}

Future<void> withKey(WidgetTester tester, LogicalKeyboardKey modifier, LogicalKeyboardKey key,
    {String? character}) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key, character: character);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {String? character}) async {
  await tester.sendKeyEvent(key, character: character);
  await tester.pump();
}

String? focusedRole() {
  final node = FocusManager.instance.primaryFocus;
  return node == null ? null : appFocusRoles.roleFor(node);
}

/// The fake clock has to pass the ignore probe's delay before the test ends.
Future<void> settle(WidgetTester tester) => tester.pump(const Duration(milliseconds: 300));

void main() {
  testWidgets('Changes list: Home, End, PageDown, Shift+End, Ctrl+A, Esc', (tester) async {
    final (shell, _) = await openShell(tester);
    final changes = shell.workspace.changes;
    expect(focusedRole(), 'file list');

    await press(tester, LogicalKeyboardKey.end);
    expect(changes.index, 39);
    await press(tester, LogicalKeyboardKey.home);
    expect(changes.index, 0);
    await press(tester, LogicalKeyboardKey.pageDown);
    expect(changes.index, 15);
    await press(tester, LogicalKeyboardKey.pageUp);
    expect(changes.index, 0);

    await withKey(tester, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.pageDown);
    expect(changes.selectionCount, 16, reason: 'Shift extends from the anchor');
    await withKey(tester, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.end);
    expect(changes.selectionCount, 40);

    await press(tester, LogicalKeyboardKey.escape);
    expect(changes.selectionCount, 1);
    expect(changes.selected?.path, 'f39.txt');

    await withKey(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyA);
    expect(changes.selectionCount, 40);
    await settle(tester);
  });

  testWidgets('Ctrl+R and Ctrl+F match the key, whatever character Windows sends', (tester) async {
    final (shell, repo) = await openShell(tester, rows: [untracked('a.txt')]);
    repo.calls.clear();
    // With Ctrl held, Windows can send a control character (or none) for R.
    await withKey(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyR, character: '\u0012');
    expect(repo.calls, contains('status'));

    await withKey(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyF, character: '\u0006');
    expect(shell.filterFocus.hasFocus, isTrue);
    await settle(tester);
  });

  testWidgets('Tab and Shift+Tab visit every Changes stop in order and wrap', (tester) async {
    // Wide enough for the ignore pane: under 900 px it is hidden (task-11).
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await openShell(tester, rows: [untracked('a.txt')]);
    final seen = <String?>[focusedRole()];
    for (var i = 0; i < 5; i++) {
      await press(tester, LogicalKeyboardKey.tab);
      seen.add(focusedRole());
    }
    expect(seen, [
      'file list',
      'ignore file rail',
      'ignore file lines',
      'commit message',
      'filter field',
      'file list',
    ]);
    await withKey(tester, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.tab);
    expect(focusedRole(), 'filter field');
    await settle(tester);
  });

  testWidgets('with the ignore pane hidden, Tab skips its two stops', (tester) async {
    await openShell(tester, rows: [untracked('a.txt')]);
    final seen = <String?>[focusedRole()];
    for (var i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.tab);
      seen.add(focusedRole());
    }
    expect(seen, ['file list', 'commit message', 'filter field', 'file list']);
    await settle(tester);
  });

  testWidgets('Browse without a mouse: move, open, filter, up', (tester) async {
    final opened = Opened();
    final (shell, _) = await openShell(tester, rows: [untracked('a.txt')], opened: opened);
    await shell.workspace.browser.idle();
    await alt(tester, LogicalKeyboardKey.digit2);
    expect(shell.mode, Mode.browse);
    expect(focusedRole(), 'browse list');

    await press(tester, LogicalKeyboardKey.keyJ);
    expect(shell.workspace.browser.selected, 'C:/repo/two');
    await press(tester, LogicalKeyboardKey.keyK);
    expect(shell.workspace.browser.selected, 'C:/repo/one');

    await press(tester, LogicalKeyboardKey.slash, character: '/');
    expect(focusedRole(), 'browse filter field');
    final field = find.descendant(of: find.byType(BrowseView), matching: find.byType(TextField));
    await tester.enterText(field, 'two');
    await tester.pump();
    expect(shell.workspace.browser.visible, ['C:/repo/two']);
    await press(tester, LogicalKeyboardKey.enter);
    expect(focusedRole(), 'browse list');

    await press(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened.paths, ['C:/repo/two']);

    expect(shell.workspace.browser.directory, 'C:/repo/two', reason: 'Browse follows the open');
    await press(tester, LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(shell.workspace.browser.directory, 'C:/repo');
    await press(tester, LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(shell.workspace.browser.directory, 'C:/');
    await settle(tester);
  });

  testWidgets('Console without a mouse: move, unfold, copy', (tester) async {
    final (shell, _) = await openShell(tester, rows: [untracked('a.txt')]);
    shell.workspace.say('first failure');
    shell.workspace.say('second failure');
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await alt(tester, LogicalKeyboardKey.digit4);
    expect(focusedRole(), 'console list');

    await press(tester, LogicalKeyboardKey.keyJ);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.textContaining('message: first failure'), findsOneWidget);

    await withKey(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyC);
    expect(copied, startsWith('first failure'));
    await press(tester, LogicalKeyboardKey.keyL);
    expect(find.textContaining('message: first failure'), findsNothing);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('Settings without a mouse: move through the editors, Enter uses one', (tester) async {
    final prefs = MemoryPrefs();
    final (shell, _) = await openShell(tester, rows: [untracked('a.txt')], prefs: prefs);
    await alt(tester, LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(focusedRole(), 'editor list');

    await press(tester, LogicalKeyboardKey.keyJ);
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    expect(prefs.saved, 'notepad {file}');
    expect(shell.workspace.editorCommand, 'notepad {file}');
    await settle(tester);
  });

  testWidgets('every mode switch gives the keyboard to the shown mode', (tester) async {
    final (shell, _) = await openShell(tester, rows: [untracked('a.txt')]);
    const roles = ['file list', 'browse list', 'editor list', 'console list', 'help'];
    for (final mode in Mode.values) {
      await alt(tester, mode.digit);
      expect(shell.mode, mode);
      expect(focusedRole(), roles[mode.index]);
    }
    await settle(tester);
  });
}
