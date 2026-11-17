import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/pane_layout.dart';
import 'package:purrage/ui/ignore_pane.dart';
import 'package:purrage/ui/resizable_pane.dart';
import 'package:purrage/ui/shell.dart';

import 'support/fake_repo.dart';
import 'support/fake_workspace.dart';

void main() {
  group('PaneLayout', () {
    test('shown on a wide window, hidden on a narrow one, until toggled', () {
      final layout = PaneLayout();
      expect(layout.shownIn(1400), isTrue);
      expect(layout.shownIn(800), isFalse);

      layout.toggle(800);
      expect(layout.shownIn(800), isTrue);
      layout.toggle(1400);
      expect(layout.shownIn(1400), isFalse);
    });

    test('a drag is clamped to the window, and its end is remembered', () {
      final saved = <double>[];
      final layout = PaneLayout(onSave: (width) async => saved.add(width));
      expect(layout.widthIn(1400), PaneLayout.defaultWidth);

      layout.dragBy(100, 1400);
      expect(layout.width, 460);
      layout.dragBy(-1000, 1400);
      expect(layout.width, PaneLayout.minWidth);
      layout.dragBy(5000, 1000);
      expect(layout.width, 600, reason: 'at most 60% of the window');
      layout.dragEnd();
      expect(saved, [600]);

      layout.reset();
      expect(layout.width, PaneLayout.defaultWidth);
      expect(saved.last, PaneLayout.defaultWidth);
    });

    test('a width from prefs is taken without saving it again', () {
      final saved = <double>[];
      final layout = PaneLayout(onSave: (width) async => saved.add(width))..restore(420);
      expect(layout.width, 420);
      expect(saved, isEmpty);
    });
  });

  group('ResizablePane', () {
    Future<PaneLayout> pumpPane(WidgetTester tester, List<double> saved) async {
      final layout = PaneLayout(onSave: (width) async => saved.add(width));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                const Expanded(child: SizedBox()),
                ListenableBuilder(
                  listenable: layout,
                  builder: (context, _) => ResizablePane(
                    layout: layout,
                    room: 1400,
                    child: const SizedBox.expand(key: ValueKey('pane')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return layout;
    }

    testWidgets('the edge has the resize cursor and a tooltip', (tester) async {
      await pumpPane(tester, []);
      final resize = find.descendant(
        of: find.byType(PaneEdge),
        matching: find.byWidgetPredicate(
          (widget) => widget is MouseRegion && widget.cursor == SystemMouseCursors.resizeColumn,
        ),
      );
      expect(resize, findsOneWidget);
      expect(find.byTooltip(PaneEdge.tooltip), findsOneWidget);
    });

    testWidgets('dragging the edge left widens the pane and remembers it', (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final saved = <double>[];
      final layout = await pumpPane(tester, saved);
      expect(tester.getSize(find.byKey(const ValueKey('pane'))).width, 360);

      await tester.drag(find.byType(PaneEdge), const Offset(-100, 0));
      // Past the double-tap window the edge also listens for.
      await tester.pump(const Duration(milliseconds: 500));

      expect(layout.width, greaterThan(360));
      expect(tester.getSize(find.byKey(const ValueKey('pane'))).width, layout.width);
      expect(saved, [layout.width]);
    });
  });

  group('the Changes mode', () {
    Future<void> pumpShell(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = FakeRepo([]);
      final changes = Changes(repo);
      await changes.load();
      await tester.pumpWidget(
        MaterialApp(home: Shell(workspace: fakeWorkspace(repo, changes: changes))),
      );
      await tester.pump();
    }

    testWidgets('shows the ignore pane on a wide window', (tester) async {
      await pumpShell(tester, 1400);
      expect(find.byType(IgnorePane), findsOneWidget);
    });

    testWidgets('hides it on a narrow window, and p brings it back', (tester) async {
      await pumpShell(tester, 800);
      expect(find.byType(IgnorePane), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP, character: 'p');
      await tester.pump();
      expect(find.byType(IgnorePane), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP, character: 'p');
      await tester.pump();
      expect(find.byType(IgnorePane), findsNothing);
    });
  });
}
