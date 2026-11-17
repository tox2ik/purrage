import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/ignore_files.dart';
import 'package:purrage/ui/file_list.dart';
import 'package:purrage/ui/theme.dart';

import 'support/fake_repo.dart';
import 'support/pump_changes.dart';

ScrollController listScroll(WidgetTester tester) =>
    tester.widget<ListView>(find.descendant(of: find.byType(FileList), matching: find.byType(ListView))).controller!;

/// True when the cursor row's name is drawn inside the list's viewport.
bool cursorOnScreen(WidgetTester tester, Changes changes) {
  final name = find.text(changes.selected!.name);
  if (name.evaluate().isEmpty) return false;
  final list = tester.getRect(find.descendant(of: find.byType(FileList), matching: find.byType(ListView)));
  final row = tester.getRect(name);
  return row.top >= list.top - 0.5 && row.bottom <= list.bottom + 0.5;
}

void main() {
  late FakeRepo repo;
  late Changes changes;
  late IgnorePaneState pane;

  Future<void> open(WidgetTester tester, int rows) async {
    repo = FakeRepo(numberedRows(rows));
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

  testWidgets('the cursor on row 400 of 500 is on screen', (tester) async {
    await open(tester, 500);
    await changes.move(400);
    await tester.pump();
    expect(changes.selected!.name, 'f0400.txt');
    expect(cursorOnScreen(tester, changes), isTrue);
    await close(tester);
  });

  testWidgets('a reload that keeps the cursor far down brings it back on screen', (tester) async {
    await open(tester, 500);
    await changes.move(450);
    await tester.pump();
    listScroll(tester).jumpTo(0);
    await tester.pump();
    expect(cursorOnScreen(tester, changes), isFalse);

    await changes.load();
    await tester.pump();
    expect(cursorOnScreen(tester, changes), isTrue);
    await close(tester);
  });

  testWidgets('a reload that grows the list reveals the kept row after the frame', (tester) async {
    repo = FakeRepo(numberedRows(10, from: 450));
    changes = Changes(repo);
    pane = IgnorePaneState(repo);
    await changes.load();
    await pumpChangesView(tester, changes, pane);
    await changes.click(5);
    await tester.pump();

    repo.rows = numberedRows(500);
    await changes.load();
    await tester.pump();
    await tester.pump();
    expect(changes.selected!.name, 'f0455.txt');
    expect(cursorOnScreen(tester, changes), isTrue);
    await close(tester);
  });

  testWidgets('a move inside the viewport does not scroll; past it, the least scroll', (tester) async {
    await open(tester, 500);
    final scroll = listScroll(tester);
    await changes.move(3);
    await tester.pump();
    expect(scroll.offset, 0);

    // Walk down to the first row below the viewport: the list moves by
    // exactly what it takes to show that row's bottom edge.
    final visibleRows = (scroll.position.viewportDimension - T.sectionHeaderHeight) ~/ T.rowHeight;
    await changes.move(visibleRows - 3);
    await tester.pump();
    final bottom = T.sectionHeaderHeight + (changes.index + 1) * T.rowHeight;
    expect(scroll.offset, closeTo(bottom - scroll.position.viewportDimension, 0.01));
    expect(cursorOnScreen(tester, changes), isTrue);
    await close(tester);
  });

  testWidgets('the list has fixed extents', (tester) async {
    await open(tester, 20);
    final list = tester.widget<ListView>(
      find.descendant(of: find.byType(FileList), matching: find.byType(ListView)),
    );
    expect(list.itemExtentBuilder, isNotNull);
    await close(tester);
  });

  test('FileList holds no GlobalKey', () async {
    final source = await File('lib/ui/file_list.dart').readAsString();
    expect(source, isNot(contains('GlobalKey')));
  });
}
