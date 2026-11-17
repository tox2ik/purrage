/// The small widgets the views are built from, as in Ops' `widgets.dart`.
///
/// Each atom takes values and emits callbacks, and every clickable one goes
/// through [Clickable], so the pointer cursor and the tooltip are there by
/// construction instead of by remembering. Nothing else in `lib/ui/` sets
/// `SystemMouseCursors.click`.
library;

import 'package:flutter/material.dart';

/// The pointer cursor and a tooltip around a control: the one place they are
/// put on anything clickable. Disabled, the cursor is the plain arrow.
class Clickable extends StatelessWidget {
  const Clickable({super.key, required this.tooltip, required this.child, this.enabled = true});

  final String tooltip;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: child,
        ),
      );
}

/// A list row: hover, tap, secondary tap and double tap, with the pointer
/// cursor and a tooltip. [decoration] draws the selected or current state.
class HoverRow extends StatelessWidget {
  const HoverRow({
    super.key,
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.onSecondaryTap,
    this.onDoubleTap,
    this.decoration,
    this.padding = EdgeInsets.zero,
  });

  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onDoubleTap;
  final Decoration? decoration;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => Clickable(
        tooltip: tooltip,
        child: InkWell(
          onTap: onTap,
          onSecondaryTap: onSecondaryTap,
          onDoubleTap: onDoubleTap,
          child: Container(decoration: decoration, padding: padding, child: child),
        ),
      );
}

/// A compact icon button: the reload, up-a-level, clear and dismiss buttons.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 16,
    this.buttonKey,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  /// A key on the button itself, for tests that tap it.
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => Clickable(
        tooltip: tooltip,
        enabled: onPressed != null,
        child: IconButton(
          key: buttonKey,
          icon: Icon(icon, size: size),
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: size + 12, height: size + 12),
          onPressed: onPressed,
        ),
      );
}

/// A labelled button; the label is part of the control, so clicking the text
/// does what the button does. [filled] is the one primary action of a pane.
class SmallButton extends StatelessWidget {
  const SmallButton({
    super.key,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.filled = false,
  });

  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) => Clickable(
        tooltip: tooltip,
        enabled: onPressed != null,
        child: _button(),
      );

  Widget _button() {
    final text = Text(label);
    final glyph = icon == null ? null : Icon(icon, size: 16);
    if (filled) {
      return glyph == null
          ? FilledButton.tonal(onPressed: onPressed, child: text)
          : FilledButton.tonalIcon(onPressed: onPressed, icon: glyph, label: text);
    }
    return glyph == null
        ? TextButton(onPressed: onPressed, child: text)
        : TextButton.icon(onPressed: onPressed, icon: glyph, label: text);
  }
}

/// A word that acts: the row's `Add` / `Untrack` / `Ignore`, in a slot of a
/// fixed [width] so the names next to it line up.
class LinkButton extends StatelessWidget {
  const LinkButton({
    super.key,
    required this.label,
    required this.tooltip,
    required this.onTap,
    required this.width,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) => Clickable(
        tooltip: tooltip,
        child: SizedBox(
          width: width,
          height: 20,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Center(child: _label(context)),
          ),
        ),
      );

  Widget _label(BuildContext context) => Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}

/// A square icon that is on or off: the mode rail's entries.
class IconToggle extends StatelessWidget {
  const IconToggle({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.extent = 44,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  final double extent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Clickable(
      tooltip: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: extent,
          height: extent,
          color: active ? scheme.secondaryContainer : null,
          child: Icon(icon, size: 17, color: active ? scheme.primary : scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// A small label in a box: the `git` chip on a nested repository, the error
/// code in the console. Not clickable; [tooltip] explains it when given.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.background, this.tooltip});

  final String text;

  /// The text colour, and the outline when there is no [background].
  final Color? color;
  final Color? background;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        border: background == null ? Border.all(color: scheme.outline) : null,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: TextStyle(fontSize: 9.5, color: color ?? scheme.onSurfaceVariant)),
    );
    final help = tooltip;
    return help == null ? pill : Tooltip(message: help, child: pill);
  }
}

/// A pane's title strip: a label, then its controls at the end.
class PaneHeader extends StatelessWidget {
  const PaneHeader({super.key, required this.title, this.trailing = const []});

  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.labelMedium)),
            ...trailing,
          ],
        ),
      );
}
