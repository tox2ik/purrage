import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/modes.dart';
import 'widgets.dart';

export '../state/modes.dart' show Mode;

/// What a mode looks like on screen, and its key as a [LogicalKeyboardKey]. The
/// label and the number are on [Mode] itself.
extension ModeLook on Mode {
  IconData get icon => switch (this) {
        Mode.changes => Icons.description_outlined,
        Mode.browse => Icons.folder_open_outlined,
        Mode.settings => Icons.settings_outlined,
        Mode.console => Icons.terminal,
        Mode.help => Icons.help_outline,
      };

  /// `Alt+<digit>` picks the mode: [Mode.number] as a key.
  LogicalKeyboardKey get digit => const [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ][number - 1];
}

/// The mode rail, in the role of Flutter's `NavigationRail` (kept custom for
/// its 44 px density): one stop in the Tab order, not one per mode.
class ModeRail extends StatelessWidget {
  const ModeRail({super.key, required this.current, required this.onPick});

  final Mode current;
  final ValueChanged<Mode> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final mode in Mode.values)
          IconToggle(
            icon: mode.icon,
            tooltip: mode.named,
            active: mode == current,
            onTap: () => onPick(mode),
          ),
      ],
    );
  }
}
