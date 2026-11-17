import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/ignore_files.dart';
import 'package:purrage/ui/commit_bar.dart';
import 'package:purrage/ui/file_list.dart';
import 'package:purrage/ui/filter_field.dart';
import 'package:purrage/ui/ignore_pane.dart';

import 'support/fake_repo.dart';
import 'support/pump_changes.dart';

/// Counts the elements rebuilt under each widget type while [body] runs, using
/// Flutter's own rebuild hook (debug builds only, which tests are).
Future<Map<Type, int>> rebuildsDuring(
  List<Type> under,
  Future<void> Function() body,
) async {
  final counts = {for (final type in under) type: 0};
  debugOnRebuildDirtyWidget = (element, _) {
    for (final type in under) {
      if (element.widget.runtimeType == type || _hasAncestor(element, type)) {
        counts[type] = counts[type]! + 1;
      }
    }
  };
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return counts;
}

bool _hasAncestor(Element element, Type type) {
  var found = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget.runtimeType == type) found = true;
    return !found;
  });
  return found;
}

void main() {
  late FakeRepo repo;
  late Changes changes;
  late IgnorePaneState pane;

  Future<void> open(WidgetTester tester) async {
    repo = FakeRepo(numberedRows(60));
    changes = Changes(repo);
    pane = IgnorePaneState(repo);
    await changes.load();
    await pumpChangesView(tester, changes, pane);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    changes.dispose();
    pane.dispose();
  }

  testWidgets('one j rebuilds the list, and no CommitBar, IgnorePane or filter', (tester) async {
    await open(tester);
    final counts = await rebuildsDuring([CommitBar, IgnorePane, FilterField, FileList], () async {
      await changes.move(1);
      await tester.pump();
    });
    expect(counts[CommitBar], 0);
    expect(counts[IgnorePane], 0);
    expect(counts[FilterField], 0);
    expect(counts[FileList], greaterThan(0));
    await close(tester);
  });

  testWidgets('a click, a range and a toggle rebuild no CommitBar either', (tester) async {
    await open(tester);
    final counts = await rebuildsDuring([CommitBar, IgnorePane], () async {
      await changes.click(5);
      await changes.extendSelection(3);
      await changes.toggleFocused();
      await tester.pump();
    });
    expect(counts[CommitBar], 0);
    expect(counts[IgnorePane], 0);
    await close(tester);
  });

  testWidgets('staging a row updates the commit bar count', (tester) async {
    await open(tester);
    expect(find.text('Commit 0'), findsOneWidget);
    final counts = await rebuildsDuring([CommitBar], () async {
      await changes.trackSelected();
      await tester.pump();
    });
    expect(counts[CommitBar], greaterThan(0));
    expect(find.text('Commit 1'), findsOneWidget);
    await close(tester);
  });

  test('a cursor move fires cursor, not rows or status', () async {
    final changes = Changes(FakeRepo(numberedRows(10)));
    await changes.load();
    // load() leaves the nested-repository scan running; let it finish first.
    await pumpEventQueue();
    var cursor = 0, rows = 0, status = 0;
    changes.cursor.addListener(() => cursor++);
    changes.rowsChanged.addListener(() => rows++);
    changes.status.addListener(() => status++);

    await changes.move(1);
    expect((cursor, rows, status), (1, 0, 0));

    await changes.setFilter('f000');
    expect((cursor, rows, status), (2, 1, 0));

    await changes.load();
    expect(status, greaterThanOrEqualTo(2)); // busy on, busy off
    await pumpEventQueue();
    changes.dispose();
  });
}
