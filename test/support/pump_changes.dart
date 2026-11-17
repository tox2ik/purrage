import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/ignore_files.dart';
import 'package:purrage/state/status.dart';
import 'package:purrage/ui/changes_view.dart';
import 'package:purrage/ui/theme.dart';

/// [n] untracked rows named `f000.txt` .. so the sorted order is the index.
List<StatusRow> numberedRows(int n, {int from = 0}) => [
      for (var i = from; i < from + n; i++)
        StatusRow(
          section: Section.untracked,
          kind: RowKind.untracked,
          path: 'f${i.toString().padLeft(4, '0')}.txt',
          code: '??',
        ),
    ];

/// The Changes mode on its own, with no-op callbacks: no shell, no git, no
/// files. [changes] and [pane] come from a FakeRepo.
Future<void> pumpChangesView(
  WidgetTester tester,
  Changes changes,
  IgnorePaneState pane,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: Scaffold(
      body: ChangesView(
        changes: changes,
        commitController: TextEditingController(),
        commitFocus: FocusNode(),
        listFocus: FocusNode(),
        onIgnore: () {},
        onQuickIgnore: () {},
        onTrack: () {},
        onUntrack: () {},
        onOpen: () {},
        onReload: () {},
        filterController: TextEditingController(),
        filterFocus: FocusNode(),
        ignoreState: pane,
        onOpenIgnore: () {},
        onNewIgnore: () {},
        onCommit: (_) async {},
      ),
    ),
  ));
  await tester.pump();
}
