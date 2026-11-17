import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/ui/widgets.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

/// The cursor the atom puts over itself.
/// The Tooltip's and the button's own regions defer; the atom's is the one
/// with a system cursor.
MouseCursor cursorOf(WidgetTester tester, Type atom) => tester
    .widgetList<MouseRegion>(find.descendant(of: find.byType(atom), matching: find.byType(MouseRegion)))
    .map((region) => region.cursor)
    .whereType<SystemMouseCursor>()
    .first;

/// The tooltip message the atom carries.
String tooltipOf(WidgetTester tester, Type atom) => tester
    .widget<Tooltip>(find.descendant(of: find.byType(atom), matching: find.byType(Tooltip)).first)
    .message!;

void main() {
  testWidgets('HoverRow: pointer, tooltip, and its text taps, right-clicks and double-clicks', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(host(HoverRow(
      tooltip: 'Open a',
      onTap: () => events.add('tap'),
      onSecondaryTap: () => events.add('secondary'),
      onDoubleTap: () => events.add('double'),
      child: const Text('a.txt'),
    )));
    expect(cursorOf(tester, HoverRow), SystemMouseCursors.click);
    expect(tooltipOf(tester, HoverRow), 'Open a');

    await tester.tap(find.text('a.txt'), buttons: kSecondaryButton);
    await tester.tap(find.text('a.txt'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(events, ['secondary', 'tap']);
  });

  testWidgets('IconAction: pointer and tooltip; disabled shows the arrow', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(host(IconAction(icon: Icons.refresh, tooltip: 'Reload (F5)', onPressed: () => pressed++)));
    expect(cursorOf(tester, IconAction), SystemMouseCursors.click);
    expect(tooltipOf(tester, IconAction), 'Reload (F5)');
    await tester.tap(find.byIcon(Icons.refresh));
    expect(pressed, 1);

    await tester.pumpWidget(host(const IconAction(icon: Icons.refresh, tooltip: 'Reload', onPressed: null)));
    expect(cursorOf(tester, IconAction), SystemMouseCursors.basic);
  });

  testWidgets('SmallButton: the label is the control, plain and filled', (tester) async {
    var pressed = 0;
    for (final filled in [false, true]) {
      for (final icon in [null, Icons.open_in_new]) {
        await tester.pumpWidget(host(SmallButton(
          label: 'Test',
          tooltip: 'Open PLAN.md',
          icon: icon,
          filled: filled,
          onPressed: () => pressed++,
        )));
        expect(cursorOf(tester, SmallButton), SystemMouseCursors.click);
        expect(tooltipOf(tester, SmallButton), 'Open PLAN.md');
        await tester.tap(find.text('Test'));
      }
    }
    expect(pressed, 4);
  });

  testWidgets('LinkButton: the word acts', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(host(LinkButton(label: 'Add', tooltip: 'git add (a)', width: 52, onTap: () => pressed++)));
    expect(cursorOf(tester, LinkButton), SystemMouseCursors.click);
    expect(tooltipOf(tester, LinkButton), 'git add (a)');
    await tester.tap(find.text('Add'));
    expect(pressed, 1);
  });

  testWidgets('IconToggle: pointer, tooltip, tap', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(host(IconToggle(
      icon: Icons.terminal,
      tooltip: 'Console (Alt+4)',
      active: true,
      onTap: () => pressed++,
    )));
    expect(cursorOf(tester, IconToggle), SystemMouseCursors.click);
    expect(tooltipOf(tester, IconToggle), 'Console (Alt+4)');
    await tester.tap(find.byIcon(Icons.terminal));
    expect(pressed, 1);
  });

  testWidgets('Pill and PaneHeader show their text; a pill explains itself when asked', (tester) async {
    await tester.pumpWidget(host(Column(children: [
      const Pill('git', tooltip: 'Nested repository'),
      const Pill('exit 128', background: Colors.red),
      PaneHeader(title: 'CONSOLE  2', trailing: [SmallButton(label: 'Clear', tooltip: 'Clear the log', onPressed: () {})]),
    ])));
    expect(find.text('git'), findsOneWidget);
    expect(find.byTooltip('Nested repository'), findsOneWidget);
    expect(find.text('exit 128'), findsOneWidget);
    expect(find.text('CONSOLE  2'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
  });
}
