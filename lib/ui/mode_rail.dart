import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'widgets.dart';

/// The modes the app shows; the rail lists them in this order.
enum Mode { changes, browse, settings, console, help }

extension ModeLook on Mode {
  String get label => switch (this) {
        Mode.changes => 'Changes',
        Mode.browse => 'Browse',
        Mode.settings => 'Settings',
        Mode.console => 'Console',
        Mode.help => 'Help',
      };

  IconData get icon => switch (this) {
        Mode.changes => Icons.description_outlined,
        Mode.browse => Icons.folder_open_outlined,
        Mode.settings => Icons.settings_outlined,
        Mode.console => Icons.terminal,
        Mode.help => Icons.help_outline,
      };

  /// `Alt+<digit>` picks the mode: its position in the rail, from 1.
  LogicalKeyboardKey get digit => const [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
      ][index];
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
            tooltip: '${mode.label} (Alt+${mode.index + 1})',
            active: mode == current,
            onTap: () => onPick(mode),
          ),
      ],
    );
  }
}
