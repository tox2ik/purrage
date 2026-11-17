import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/ignore_files.dart';
import 'package:purrage/ui/changes_view.dart';
import 'package:purrage/ui/file_list.dart';
import 'package:purrage/ui/theme.dart';
import 'package:purrage/ui/widgets.dart';

import 'support/fake_repo.dart';
import 'support/pump_changes.dart';

void main() {
  test('no inline font, colour or tint in lib/ui outside theme.dart', () async {
    final inline = RegExp(r'fontSize:|fontFamily:|\bColor\(|\bColors\.|\.withValues\(');
    final offenders = <String>[];
    await for (final entity in Directory('lib/ui').list()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.uri.pathSegments.last == 'theme.dart') continue;
      final lines = await entity.readAsLines();
      for (var i = 0; i < lines.length; i++) {
        if (inline.hasMatch(lines[i])) offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('no text under 11 px, and the code font is named', () {
    final theme = buildTheme();
    final styles = {
      'T.body': T.body,
      'T.small': T.small,
      'T.tiny': T.tiny,
      'T.section': T.section,
      'T.title': T.title,
      'T.code': T.code,
      'T.codeSmall': T.codeSmall,
      'T.codeTiny': T.codeTiny,
      'bodyMedium': theme.textTheme.bodyMedium!,
      'bodySmall': theme.textTheme.bodySmall!,
      'labelMedium': theme.textTheme.labelMedium!,
      'labelSmall': theme.textTheme.labelSmall!,
      'titleMedium': theme.textTheme.titleMedium!,
    };
    for (final MapEntry(:key, :value) in styles.entries) {
      expect(value.fontSize, greaterThanOrEqualTo(11), reason: key);
    }
    expect(T.code.fontFamily, 'Consolas');
    expect(T.code.fontFamilyFallback, contains('Cascadia Mono'));
  });

  test('hover comes from the palette, and nothing ripples', () {
    final theme = buildTheme();
    expect(theme.splashFactory, NoSplash.splashFactory);
    expect(theme.hoverColor, T.hover);
    expect(theme.highlightColor, T.none);
  });

  group('in the Changes mode', () {
    late Changes changes;
    late IgnorePaneState pane;

    Future<void> open(WidgetTester tester) async {
      final repo = FakeRepo(numberedRows(5));
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

    /// The top line of pane [at]: 0 the list, 1 the ignore pane.
    Color markColor(WidgetTester tester, int at) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(PaneMark).at(at), matching: find.byType(DecoratedBox)).first,
      );
      return (box.decoration as BoxDecoration).border!.top.color;
    }

    /// Give the keys to [node]; focus lands after the frame that asked, and
    /// the mark follows on the next one.
    Future<void> focus(WidgetTester tester, FocusNode node) async {
      node.requestFocus();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('rows keep the theme hover and splash', (tester) async {
      await open(tester);
      final wells = tester.widgetList<InkWell>(
        find.descendant(of: find.byType(FileRow), matching: find.byType(InkWell)),
      );
      expect(wells, isNotEmpty);
      for (final well in wells) {
        expect(well.hoverColor, isNull);
        expect(well.splashFactory, isNull);
        expect(well.splashColor, isNull);
      }
      await close(tester);
    });

    testWidgets('the pane with the keys is marked, and the mark moves with them', (tester) async {
      await open(tester);
      final accent = buildTheme().colorScheme.primary;
      final view = tester.widget<ChangesView>(find.byType(ChangesView));

      await focus(tester, view.listFocus);
      expect((markColor(tester, 0), markColor(tester, 1)), (accent, T.none));

      await focus(tester, view.railFocus!);
      expect((markColor(tester, 0), markColor(tester, 1)), (T.none, accent));

      // A text field shows its own border; no pane is marked.
      await focus(tester, view.filterFocus);
      expect((markColor(tester, 0), markColor(tester, 1)), (T.none, T.none));
      await close(tester);
    });

    testWidgets('row action tooltips name their keys', (tester) async {
      await open(tester);
      expect(find.byTooltip('Track this file, git add (Space or a)'), findsWidgets);
      expect(
        find.byTooltip('Add the literal path to the root .gitignore (i; Shift+I or right-click to choose)'),
        findsWidgets,
      );
      expect(find.byTooltip('Re-read the state (F5, Ctrl+R or r)'), findsOneWidget);
      await close(tester);
    });
  });
}
