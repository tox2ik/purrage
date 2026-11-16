import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/changes.dart';
import '../state/git_repo.dart';
import 'changes_view.dart';
import 'help_view.dart';
import 'ignore_dialog.dart';
import 'nav_keys.dart';

/// The modes the app shows; the rail lists them in this order.
enum Mode { changes, settings, help }

extension on Mode {
  String get label => switch (this) {
        Mode.changes => 'Changes',
        Mode.settings => 'Settings',
        Mode.help => 'Help',
      };
  IconData get icon => switch (this) {
        Mode.changes => Icons.description_outlined,
        Mode.settings => Icons.settings_outlined,
        Mode.help => Icons.help_outline,
      };
}

/// The window shell: the mode rail, the shown mode, and every app-wide key.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.repo, this.seeded});

  final GitRepo repo;

  /// A prepared state, for tests: the fake repo path never touches git.
  final Changes? seeded;

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  late final Changes changes = widget.seeded ?? Changes(widget.repo);
  final FocusNode shellFocus = FocusNode(debugLabel: 'shell');
  final TextEditingController commitController = TextEditingController();
  final FocusNode commitFocus = FocusNode(debugLabel: 'commit message');
  final TextEditingController filterController = TextEditingController();
  final FocusNode filterFocus = FocusNode(debugLabel: 'filter');
  Mode mode = Mode.changes;

  @override
  void initState() {
    super.initState();
    changes.load();
  }

  @override
  void dispose() {
    changes.dispose();
    commitController.dispose();
    commitFocus.dispose();
    filterController.dispose();
    filterFocus.dispose();
    shellFocus.dispose();
    super.dispose();
  }

  void show(Mode next) {
    if (next == mode) return;
    setState(() => mode = next);
    if (next != Mode.changes) {
      // Leaving Changes takes the keyboard out of the commit field.
      commitFocus.unfocus();
    }
    shellFocus.requestFocus();
  }

  void cycle(int delta) {
    final modes = Mode.values;
    final next = (mode.index + delta) % modes.length;
    show(modes[next < 0 ? next + modes.length : next]);
  }

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;

    if (keyboard.isAltPressed) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.bracketRight) {
        cycle(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.bracketLeft) {
        cycle(-1);
        return KeyEventResult.handled;
      }
      for (final entry in _altDigits.entries) {
        if (key == entry.value) {
          show(entry.key);
          return KeyEventResult.handled;
        }
      }
    }

    if (event.character == '?' && isPlain(event)) {
      show(Mode.help);
      return KeyEventResult.handled;
    }

    if (mode != Mode.changes || commitFocus.hasFocus || filterFocus.hasFocus) {
      return KeyEventResult.ignored;
    }
    return _changesKey(event);
  }

  KeyEventResult _changesKey(KeyEvent event) {
    final delta = navDelta(event);
    if (delta != null) {
      changes.move(delta);
      return KeyEventResult.handled;
    }
    if (!isPlain(event)) return KeyEventResult.ignored;
    if (event.character == '/') {
      filterFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.character == 'I') {
      ignoreSelectedRow();
      return KeyEventResult.handled;
    }
    if (event.character?.toLowerCase() == 'i') {
      ignoreQuick();
      return KeyEventResult.handled;
    }
    switch (event.character?.toLowerCase()) {
      case ' ':
        changes.trackSelected();
      case 'u':
        changes.untrackSelected();
      case 'r':
        changes.load();
      case 'c':
        commitFocus.requestFocus();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// One key: ignore the focused rows with their literal path in the root
  /// .gitignore.
  Future<void> ignoreQuick() async {
    try {
      final problem = await changes.ignoreQuick();
      if (!mounted) return;
      say(problem ?? 'ignored ${changes.selectionCount} path(s) in the root .gitignore');
    } on Exception catch (error) {
      say('ignore failed: $error');
    }
  }

  /// Shift+I: ask how wide the rule is and where it goes, then write it.
  ///
  /// Every outcome says something: a silent early return is what makes an ignore
  /// that did nothing look intentional.
  Future<void> ignoreSelectedRow() async {
    final row = changes.selected;
    if (row == null) {
      say('nothing selected to ignore');
      return;
    }
    try {
      final targets = await changes.ignoreTargets();
      if (!mounted) return;
      if (targets.isEmpty) {
        say('no ignore file to write to for ${row.path}');
        return;
      }
      final choice = await IgnoreDialog.show(context, changes: changes, row: row, targets: targets);
      if (choice == null || !mounted) return;
      final problem = await changes.ignoreSelected(
        scope: choice.scope,
        target: choice.target,
        stopTracking: choice.stopTracking,
      );
      if (!mounted) return;
      final where = choice.target.path;
      say(problem ?? 'wrote a rule for ${changes.selectionCount} path(s) to $where');
    } on Exception catch (error) {
      say('ignore failed: $error');
    }
  }

  /// The one place a result is reported, so no action ends silently.
  void say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static const _altDigits = {
    Mode.changes: LogicalKeyboardKey.digit1,
    Mode.settings: LogicalKeyboardKey.digit2,
    Mode.help: LogicalKeyboardKey.digit3,
  };

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: shellFocus,
      autofocus: true,
      onKeyEvent: onKey,
      child: Scaffold(
        body: Row(
          children: [
            ModeRail(current: mode, onPick: show),
            const VerticalDivider(width: 1),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() => IndexedStack(
        index: mode.index,
        children: [
          ChangesView(
            changes: changes,
            commitController: commitController,
            commitFocus: commitFocus,
            onIgnore: ignoreSelectedRow,
            filterController: filterController,
            filterFocus: filterFocus,
          ),
          const SettingsPlaceholder(),
          const HelpView(),
        ],
      );
}

/// The mode rail: one stop in the Tab order, not one per mode.
class ModeRail extends StatelessWidget {
  const ModeRail({super.key, required this.current, required this.onPick});

  final Mode current;
  final ValueChanged<Mode> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final mode in Mode.values)
          _RailButton(
            mode: mode,
            active: mode == current,
            onTap: () => onPick(mode),
          ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.mode, required this.active, required this.onTap});

  final Mode mode;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: mode.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            color: active ? scheme.secondaryContainer : null,
            child: Icon(mode.icon, color: active ? scheme.onSecondaryContainer : null),
          ),
        ),
      ),
    );
  }
}

class SettingsPlaceholder extends StatelessWidget {
  const SettingsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: Text('Settings: the editor choice arrives with the editor feature.'),
      );
}
