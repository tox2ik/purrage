import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
          _RailButton(mode: mode, active: mode == current, onTap: () => onPick(mode)),
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
            width: 44,
            height: 44,
            color: active ? scheme.secondaryContainer : null,
            child: Icon(
              mode.icon,
              size: 17,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
