/// The app's keys as data: each [Binding] is the activators, the [Intent] they
/// send, and the line the Help mode shows. `Shortcuts` is built from these
/// lists and the help table is read from the same lists, so the two cannot
/// drift apart.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'mode_rail.dart';

// --- intents ---------------------------------------------------------------

/// Show one mode (`Alt+1` … `Alt+5`, `?`).
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
    'Alt+1 … Alt+${Mode.values.length}',
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
];

/// Keys of the Changes list; they do nothing while a text field has focus.
const List<Binding> changesBindings = [
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
  Binding('Shift+Up / Shift+Down', 'extend the highlight from the anchor', activators: [
    SingleActivator(LogicalKeyboardKey.arrowDown, shift: true),
  ], intent: MoveIntent(1, extend: true)),
  Binding('', '', activators: [
    SingleActivator(LogicalKeyboardKey.arrowUp, shift: true),
  ], intent: MoveIntent(-1, extend: true)),
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

/// Plain keys that work in every mode, unless a text field has focus.
const List<Binding> plainBindings = [
  Binding('?', 'this list', activators: [CharacterActivator('?')], intent: ShowModeIntent(Mode.help)),
  Binding('Esc', 'leave the field or the menu'),
];

/// Every binding, in the order Help lists them.
List<Binding> get allBindings => [...appBindings, ...changesBindings, ...plainBindings];

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
