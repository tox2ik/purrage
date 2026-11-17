/// The app's keys as data: each [Binding] is the activators, the [Intent] they
/// send, and the line the Help mode shows. `Shortcuts` is built from these
/// lists and the help table is read from the same lists, so the two cannot
/// drift apart.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'mode_rail.dart';

// --- intents ---------------------------------------------------------------

/// Show one mode (`Alt+<n>` from [Mode.key], `?`).
class ShowModeIntent extends Intent {
  const ShowModeIntent(this.mode);
  final Mode mode;
}

/// Next or previous mode (`Alt+]`, `Alt+[`).
class CycleModeIntent extends Intent {
  const CycleModeIntent(this.delta);
  final int delta;
}

/// Move the cursor by [delta] rows; [extend] takes the selection along.
class MoveIntent extends Intent {
  const MoveIntent(this.delta, {this.extend = false});
  final int delta;
  final bool extend;
}

class ToggleRowIntent extends Intent {
  const ToggleRowIntent();
}

class TrackIntent extends Intent {
  const TrackIntent();
}

class UntrackIntent extends Intent {
  const UntrackIntent();
}

class IgnoreIntent extends Intent {
  const IgnoreIntent();
}

class IgnoreDialogIntent extends Intent {
  const IgnoreDialogIntent();
}

class OpenFileIntent extends Intent {
  const OpenFileIntent();
}

class OpenIgnoreFileIntent extends Intent {
  const OpenIgnoreFileIntent();
}

class ReloadIntent extends Intent {
  const ReloadIntent();
}

class FocusFilterIntent extends Intent {
  const FocusFilterIntent();
}

class FocusCommitIntent extends Intent {
  const FocusCommitIntent();
}

/// `p`: show or hide the ignore pane.
class TogglePaneIntent extends Intent {
  const TogglePaneIntent();
}

/// Tab / Shift+Tab: the next or previous pane of the shown mode, wrapping.
class PaneIntent extends Intent {
  const PaneIntent(this.delta);
  final int delta;
}

/// Ctrl+A: every row.
class SelectAllIntent extends Intent {
  const SelectAllIntent();
}

/// Esc in a list: the highlight back to the cursor row.
class CollapseIntent extends Intent {
  const CollapseIntent();
}

// Enter on a row is Flutter's own `ActivateIntent`: open it (Browse), unfold
// it (Console), use it (Settings).

/// Backspace / h in Browse: the parent directory.
class UpIntent extends Intent {
  const UpIntent();
}

/// Ctrl+C in the Console: the row's detail to the clipboard.
class CopyIntent extends Intent {
  const CopyIntent();
}

/// Rows a PageUp / PageDown moves. A guess at a viewport until task-4 gives
/// the list a fixed row height to measure with.
const int pageRows = 15;

/// A jump past either end; motion clamps, so this is Home or End.
const int farRows = 1 << 30;

/// True while a text field has the keyboard: plain keys must reach it.
bool typingInField() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context != null && context.findAncestorWidgetOfExactType<EditableText>() != null;
}

// --- bindings --------------------------------------------------------------

/// One line of the key map: what to press, what it sends, and how Help says
/// it. A binding with no [activators] is help text for something that is not
/// a key press (a click), or that a widget handles itself (a text field's Esc).
class Binding {
  const Binding(this.keys, this.what, {this.activators = const [], this.intent});

  final String keys;
  final String what;
  final List<ShortcutActivator> activators;
  final Intent? intent;
}

/// Keys that work in every mode, even with a text field focused.
final List<Binding> appBindings = [
  Binding(
    '${Mode.values.first.key} … ${Mode.values.last.key}',
    Mode.values.map((mode) => mode.label).join(', '),
    activators: [for (final mode in Mode.values) SingleActivator(mode.digit, alt: true)],
  ),
  const Binding(
    'Alt+] / Alt+[',
    'next / previous mode',
    activators: [SingleActivator(LogicalKeyboardKey.bracketRight, alt: true)],
    intent: CycleModeIntent(1),
  ),
  const Binding(
    '',
    '',
    activators: [SingleActivator(LogicalKeyboardKey.bracketLeft, alt: true)],
    intent: CycleModeIntent(-1),
  ),
  const Binding('Tab / Shift+Tab', 'next / previous pane, wrapping',
      activators: [SingleActivator(LogicalKeyboardKey.tab)], intent: PaneIntent(1)),
  const Binding('', '',
      activators: [SingleActivator(LogicalKeyboardKey.tab, shift: true)], intent: PaneIntent(-1)),
];

/// Motion in every list (Changes, Browse, Console, Settings, the ignore
/// pane). The Shift forms extend the highlight where there is one (Changes)
/// and move elsewhere.
const List<Binding> motionBindings = [
  Binding('j k Up Down (W S)', 'move the cursor', activators: [
    SingleActivator(LogicalKeyboardKey.arrowDown),
    CharacterActivator('j'),
    CharacterActivator('s'),
  ], intent: MoveIntent(1)),
  Binding('', '', activators: [
    SingleActivator(LogicalKeyboardKey.arrowUp),
    CharacterActivator('k'),
    CharacterActivator('w'),
  ], intent: MoveIntent(-1)),
  Binding('Home / End', 'first / last row',
      activators: [SingleActivator(LogicalKeyboardKey.home)], intent: MoveIntent(-farRows)),
  Binding('', '', activators: [SingleActivator(LogicalKeyboardKey.end)], intent: MoveIntent(farRows)),
  Binding('PageUp / PageDown', 'a page of rows up / down',
      activators: [SingleActivator(LogicalKeyboardKey.pageUp)], intent: MoveIntent(-pageRows)),
  Binding('', '', activators: [SingleActivator(LogicalKeyboardKey.pageDown)], intent: MoveIntent(pageRows)),
  Binding('Shift + any of these', 'extend the highlight from the anchor (Changes)', activators: [
    SingleActivator(LogicalKeyboardKey.arrowDown, shift: true),
  ], intent: MoveIntent(1, extend: true)),
  Binding('', '', activators: [
    SingleActivator(LogicalKeyboardKey.arrowUp, shift: true),
  ], intent: MoveIntent(-1, extend: true)),
  Binding('', '', activators: [
    SingleActivator(LogicalKeyboardKey.home, shift: true),
  ], intent: MoveIntent(-farRows, extend: true)),
  Binding('', '', activators: [
    SingleActivator(LogicalKeyboardKey.end, shift: true),
  ], intent: MoveIntent(farRows, extend: true)),
  Binding('', '', activators: [
    SingleActivator(LogicalKeyboardKey.pageUp, shift: true),
  ], intent: MoveIntent(-pageRows, extend: true)),
  Binding('', '', activators: [
    SingleActivator(LogicalKeyboardKey.pageDown, shift: true),
  ], intent: MoveIntent(pageRows, extend: true)),
];

/// Keys of the Changes list; they do nothing while a text field has focus.
const List<Binding> changesBindings = [
  Binding('Ctrl+A', 'highlight every row',
      activators: [SingleActivator(LogicalKeyboardKey.keyA, control: true)], intent: SelectAllIntent()),
  Binding('Esc', 'the highlight back to the cursor row',
      activators: [SingleActivator(LogicalKeyboardKey.escape)], intent: CollapseIntent()),
  Binding('Ctrl+Enter', 'highlight or un-highlight the cursor row',
      activators: [SingleActivator(LogicalKeyboardKey.enter, control: true)], intent: ToggleRowIntent()),
  Binding('space / a', 'track (git add) the highlighted files',
      activators: [CharacterActivator(' '), CharacterActivator('a'), CharacterActivator('A')],
      intent: TrackIntent()),
  Binding('u', 'stop tracking, keep on disk',
      activators: [CharacterActivator('u'), CharacterActivator('U')], intent: UntrackIntent()),
  Binding('i', 'ignore: the literal path into the root .gitignore',
      activators: [CharacterActivator('i')], intent: IgnoreIntent()),
  Binding('Shift+I', 'ignore: pick scope and which ignore file',
      activators: [CharacterActivator('I')], intent: IgnoreDialogIntent()),
  Binding('c', 'jump to the commit message',
      activators: [CharacterActivator('c'), CharacterActivator('C')], intent: FocusCommitIntent()),
  Binding('p', 'show or hide the ignore pane (hidden under 900 px)',
      activators: [CharacterActivator('p'), CharacterActivator('P')], intent: TogglePaneIntent()),
  Binding('/ or Ctrl+F', 'filter the list (Esc clears, Enter leaves)', activators: [
    CharacterActivator('/'),
    SingleActivator(LogicalKeyboardKey.keyF, control: true),
  ], intent: FocusFilterIntent()),
  Binding('e', 'open the file in the editor', activators: [CharacterActivator('e')], intent: OpenFileIntent()),
  Binding('E', 'open the selected .gitignore in the editor',
      activators: [CharacterActivator('E')], intent: OpenIgnoreFileIntent()),
  Binding('F5 / Ctrl+R / r', 're-read the state and update the list', activators: [
    SingleActivator(LogicalKeyboardKey.f5),
    SingleActivator(LogicalKeyboardKey.keyR, control: true),
    CharacterActivator('r'),
  ], intent: ReloadIntent()),
  Binding('Ctrl+click / Shift+click', 'select one more / select a range'),
];

/// Keys of the Browse list.
const List<Binding> browseBindings = [
  Binding('Enter', 'open the repository under the cursor',
      activators: [SingleActivator(LogicalKeyboardKey.enter)], intent: ActivateIntent()),
  Binding('Backspace / h', 'up one level', activators: [
    SingleActivator(LogicalKeyboardKey.backspace),
    CharacterActivator('h'),
  ], intent: UpIntent()),
  Binding('F5 / Ctrl+R', 'scan the directory again', activators: [
    SingleActivator(LogicalKeyboardKey.f5),
    SingleActivator(LogicalKeyboardKey.keyR, control: true),
  ], intent: ReloadIntent()),
  Binding('/ or Ctrl+F', 'filter the list (Esc clears, Enter leaves)', activators: [
    CharacterActivator('/'),
    SingleActivator(LogicalKeyboardKey.keyF, control: true),
  ], intent: FocusFilterIntent()),
];

/// Keys of the Console list.
const List<Binding> consoleBindings = [
  Binding('Enter / l', 'unfold or fold the row', activators: [
    SingleActivator(LogicalKeyboardKey.enter),
    CharacterActivator('l'),
  ], intent: ActivateIntent()),
  Binding('Ctrl+C', "copy the row's detail",
      activators: [SingleActivator(LogicalKeyboardKey.keyC, control: true)], intent: CopyIntent()),
];

/// Keys of the Settings editor list.
const List<Binding> settingsBindings = [
  Binding('Enter', 'use the editor under the cursor',
      activators: [SingleActivator(LogicalKeyboardKey.enter)], intent: ActivateIntent()),
];

/// The ignore dialog's scope keys: [index] into `IgnoreScope.values`.
class ScopeIntent extends Intent {
  const ScopeIntent(this.index);
  final int index;
}

/// Keys of the ignore dialog (`Shift+I`): it can be completed without a mouse.
/// `j` / `k` and the arrows move through the targets ([motionBindings]).
const List<Binding> ignoreDialogBindings = [
  Binding('1 2 3 / f x d', 'scope: this file, this extension, this folder', activators: [
    CharacterActivator('1'),
    CharacterActivator('f'),
  ], intent: ScopeIntent(0)),
  Binding('', '', activators: [CharacterActivator('2'), CharacterActivator('x')], intent: ScopeIntent(1)),
  Binding('', '', activators: [CharacterActivator('3'), CharacterActivator('d')], intent: ScopeIntent(2)),
  Binding('j k Up Down', 'where the rule goes'),
  Binding('Enter', 'write the rule',
      activators: [SingleActivator(LogicalKeyboardKey.enter)], intent: ActivateIntent()),
  Binding('Esc', 'close without writing',
      activators: [SingleActivator(LogicalKeyboardKey.escape)], intent: DismissIntent()),
];

/// Plain keys that work in every mode, unless a text field has focus.
const List<Binding> plainBindings = [
  Binding('?', 'this list', activators: [CharacterActivator('?')], intent: ShowModeIntent(Mode.help)),
  Binding('Esc (in a field)', 'clear the filter, then leave the field'),
];

/// The Help mode's sections: a title and its bindings, in the order shown.
final List<(String, List<Binding>)> helpGroups = [
  ('Everywhere', [...appBindings, ...plainBindings]),
  ('Lists', motionBindings),
  ('Changes', changesBindings),
  ('Browse', browseBindings),
  ('Console', consoleBindings),
  ('Settings', settingsBindings),
  ('Ignore dialog', ignoreDialogBindings),
];

/// Every binding, in the order Help lists them.
List<Binding> get allBindings => [for (final (_, bindings) in helpGroups) ...bindings];

/// The `Shortcuts` map of [bindings]; a binding with no intent of its own
/// (the `Alt+<n>` line) sends one [ShowModeIntent] per activator.
Map<ShortcutActivator, Intent> shortcutsOf(List<Binding> bindings) => {
      for (final binding in bindings)
        for (final (index, activator) in binding.activators.indexed)
          activator: binding.intent ?? ShowModeIntent(Mode.values[index]),
    };

/// The help table: one line per binding that has words, in map order.
List<Binding> helpLines(List<Binding> bindings) => [
      for (final binding in bindings)
        if (binding.keys.isNotEmpty) binding,
    ];

/// One mode's or one pane's keys: its [bindings] as `Shortcuts`, its
/// [actions], and the [focusNode] that has to hold the keyboard for them.
/// The keys are off while a text field inside has focus.
class KeyScope extends StatefulWidget {
  const KeyScope({
    super.key,
    required this.bindings,
    required this.actions,
    required this.focusNode,
    required this.child,
  });

  final List<Binding> bindings;
  final Map<Type, Action<Intent>> actions;
  final FocusNode focusNode;
  final Widget child;

  @override
  State<KeyScope> createState() => _KeyScopeState();
}

class _KeyScopeState extends State<KeyScope> {
  late final ShortcutManager manager = GatedShortcutManager(
    shortcuts: shortcutsOf(widget.bindings),
    active: () => !typingInField(),
  );

  @override
  void dispose() {
    manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shortcuts.manager(
        manager: manager,
        child: Actions(
          actions: widget.actions,
          child: Focus(focusNode: widget.focusNode, child: widget.child),
        ),
      );
}

/// A [ShortcutManager] that can be switched off: the Changes keys are plain
/// letters, and while a text field has focus they must reach the field.
class GatedShortcutManager extends ShortcutManager {
  GatedShortcutManager({required super.shortcuts, required this.active});

  /// Asked on every key; false lets the key through untouched.
  final bool Function() active;

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (!active()) return KeyEventResult.ignored;
    return super.handleKeypress(context, event);
  }
}
