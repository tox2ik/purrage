import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glustered/ui/debug_bar.dart';

/// The window the bar is given: a dark theme, a body that can hold a focus
/// node, and the bar wrapping it, as `shell.dart` will.
Widget host({FocusRoles? roles, FocusNode? focus}) => MaterialApp(
  theme: ThemeData(
    colorSchemeSeed: const Color(0xFF4C6EF5),
    useMaterial3: true,
    brightness: Brightness.dark,
  ),
  home: Scaffold(
    body: DebugBar(
      roles: roles,
      child: Center(
        child: Focus(
          focusNode: focus,
          autofocus: true,
          child: const SizedBox(width: 200, height: 200, child: Text('body')),
        ),
      ),
    ),
  ),
);

Future<void> openPanel(WidgetTester tester) async {
  await tester.tap(find.byKey(DebugBar.buttonKey));
  await tester.pump();
}

void main() {
  testWidgets('the bug button opens the panel, closed by default', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.byKey(DebugBar.buttonKey), findsOneWidget);
    expect(find.byKey(DebugBar.panelKey), findsNothing);

    await openPanel(tester);
    expect(find.byKey(DebugBar.panelKey), findsOneWidget);
    expect(find.textContaining('Focus:'), findsOneWidget);

    await openPanel(tester);
    expect(find.byKey(DebugBar.panelKey), findsNothing);
  });

  testWidgets('the last key is shown with its modifiers', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await openPanel(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK, character: 'k');
    await tester.pump();
    expect(find.text('Key: k'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK, character: 'k');
    await tester.pump();
    expect(find.text('Key: Ctrl+K'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('a key release lands only in its own line, and only when asked', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await openPanel(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK, character: 'k');
    await tester.pump();
    expect(find.textContaining('Released:'), findsNothing);

    await tester.tap(find.byKey(DebugBar.releasesKey));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK, character: 'k');
    await tester.pump();

    expect(find.text('Key: k'), findsOneWidget);
    expect(find.text('Released: k'), findsOneWidget);
  });

  testWidgets('the focused node is named by its role', (tester) async {
    final node = FocusNode(debugLabel: 'file list');
    addTearDown(node.dispose);
    await tester.pumpWidget(host(focus: node));
    await tester.pump();
    await openPanel(tester);

    expect(find.text('Focus: file list'), findsOneWidget);
  });

  testWidgets('a registered role overrides the fallback', (tester) async {
    final roles = FocusRoles()
      ..register('commit message', 'commit message field')
      ..register('filter', 'filter field');
    final node = FocusNode(debugLabel: 'commit message');
    addTearDown(node.dispose);
    await tester.pumpWidget(host(roles: roles, focus: node));
    await tester.pump();
    await openPanel(tester);

    expect(find.text('Focus: commit message field'), findsOneWidget);
  });

  testWidgets('an unregistered label is prettified, not shown raw', (
    tester,
  ) async {
    final node = FocusNode(debugLabel: 'ignore_dialog');
    addTearDown(node.dispose);
    await tester.pumpWidget(host(focus: node));
    await tester.pump();
    await openPanel(tester);

    expect(find.text('Focus: ignore dialog'), findsOneWidget);
  });

  testWidgets('a wheel event changes the last-mouse line', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await openPanel(tester);

    expect(find.textContaining('wheel'), findsNothing);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(100, 100)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
    await tester.pump();

    expect(find.textContaining('wheel down at 100,100'), findsOneWidget);

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -40)));
    await tester.pump();
    expect(find.textContaining('wheel up at 100,100'), findsOneWidget);

    // Shift + the wheel is the app's five-row step; the bar says so.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
    await tester.pump();
    expect(find.text('Mouse: Shift+wheel down at 100,100'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });
}
