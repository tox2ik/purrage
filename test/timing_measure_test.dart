import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/ignore_files.dart';
import 'package:purrage/state/status.dart';
import 'package:purrage/timing/ui_timing.dart';

import 'support/fake_repo.dart';
import 'support/pump_changes.dart';

/// A working tree the size of a busy home folder: [n] rows over the three
/// sections, spread over folders of a few depths.
List<StatusRow> bigTree(int n) => [
      for (var i = 0; i < n; i++)
        StatusRow(
          section: i % 4 == 0
              ? Section.staged
              : i % 4 == 1
                  ? Section.changed
                  : Section.untracked,
          kind: i % 4 < 2 ? RowKind.modified : RowKind.untracked,
          path: 'dir${i % 40}/sub${i % 7}/file$i.dart',
          code: i % 4 == 0
              ? 'M '
              : i % 4 == 1
                  ? ' M'
                  : '??',
        ),
    ];

/// Prints where the time goes, so a perf change has a before and an after
/// (`make measure`). Not a benchmark with thresholds: the asserts only check
/// that each action did what it says.
void main() {
  const rows = 2000;

  test('move, track, untrack and ignore over $rows rows', () async {
    final repo = FakeRepo(bigTree(rows));
    final changes = Changes(repo);
    UiTiming.instance.samples.clear();
    await changes.load();

    // Cursor moves: down through the list and back.
    for (var i = 0; i < 300; i++) {
      changes.move(1);
    }
    for (var i = 0; i < 300; i++) {
      changes.move(-1);
    }

    // One row at a time, the common case.
    for (var i = 0; i < 20; i++) {
      changes.move(rows ~/ 2 - changes.index);
      expect((await changes.trackSelected()).ok, isTrue);
    }

    // A wide selection: 300 rows from the top of Untracked.
    final untrackedAt = changes.visible.indexWhere((row) => row.section == Section.untracked);
    changes.click(untrackedAt);
    changes.click(untrackedAt + 299, shift: true);
    expect(changes.selectionCount, 300);
    expect((await changes.trackSelected()).ok, isTrue);

    // Untrack and ignore, one row and then 300.
    changes.click(0);
    expect((await changes.untrackSelected()).ok, isTrue);
    changes.click(0);
    changes.click(299, shift: true);
    expect((await changes.untrackSelected()).ok, isTrue);
    for (var i = 0; i < 10; i++) {
      changes.click(changes.visible.length - 1);
      expect((await changes.ignoreQuick()).ok, isTrue);
    }
    changes.click(0);
    changes.click(299, shift: true);
    expect((await changes.ignoreQuick()).ok, isTrue);

    // ignore: avoid_print
    print('\n$rows rows, state only\n${UiTiming.instance.table(filter: 'changes.')}');
    expect(UiTiming.instance.samples['changes.move']!.length, greaterThanOrEqualTo(600));
    changes.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('a cursor move, to the frame, over $rows rows', (tester) async {
    final repo = FakeRepo(bigTree(rows));
    final changes = Changes(repo);
    final pane = IgnorePaneState(repo);
    await changes.load();
    await pumpChangesView(tester, changes, pane);
    UiTiming.instance.samples.clear();

    // Inside the viewport: no scroll, only the rebuild a move causes.
    for (var round = 0; round < 5; round++) {
      for (var i = 0; i < 10; i++) {
        changes.move(1);
        await tester.pump();
      }
      for (var i = 0; i < 10; i++) {
        changes.move(-1);
        await tester.pump();
      }
    }
    // ignore: avoid_print
    print('\n$rows rows, inside the viewport, with the frame\n'
        '${UiTiming.instance.table(filter: 'changes.move')}');
    expect(UiTiming.instance.samples['changes.move/frame'], hasLength(100));

    // Down past the viewport: every move scrolls the list by one row.
    UiTiming.instance.samples.clear();
    for (var i = 0; i < 100; i++) {
      changes.move(1);
      await tester.pump();
    }
    // ignore: avoid_print
    print('\n$rows rows, scrolling, with the frame\n'
        '${UiTiming.instance.table(filter: 'changes.move')}');
    expect(UiTiming.instance.samples['changes.move/frame'], hasLength(100));
    await tester.pumpWidget(const SizedBox());
    changes.dispose();
    pane.dispose();
  });
}
