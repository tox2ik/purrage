import 'package:flutter/material.dart';

import '../state/ignore_files.dart';

/// The read-only `.gitignore` pane: a rail of every ignore file, the selected
/// file's lines, and the line that matches the focused path.
class IgnorePane extends StatelessWidget {
  const IgnorePane({
    super.key,
    required this.state,
    required this.onOpenInEditor,
    required this.onNewHere,
  });

  final IgnorePaneState state;
  final VoidCallback onOpenInEditor;
  final VoidCallback onNewHere;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Column(
        children: [
          if (state.error != null) _ErrorLine(message: state.error!),
          Expanded(
            child: _Body(
              state: state,
              onOpenInEditor: onOpenInEditor,
              onNewHere: onNewHere,
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.onOpenInEditor, required this.onNewHere});

  final IgnorePaneState state;
  final VoidCallback onOpenInEditor;
  final VoidCallback onNewHere;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 180, child: _FileRail(state: state)),
          const VerticalDivider(width: 1),
          Expanded(
            child: _Detail(
              state: state,
              onOpenInEditor: onOpenInEditor,
              onNewHere: onNewHere,
            ),
          ),
        ],
      );
}

/// The narrow rail: one entry per discovered ignore file, named by its folder.
class _FileRail extends StatelessWidget {
  const _FileRail({required this.state});

  final IgnorePaneState state;

  @override
  Widget build(BuildContext context) {
    if (state.files.isEmpty) {
      return const Center(child: Text('no .gitignore files', textAlign: TextAlign.center));
    }
    return ListView.builder(
      itemCount: state.files.length,
      itemBuilder: (context, index) {
        final file = state.files[index];
        return _RailItem(
          key: ValueKey('ignore-rail-${file.path}'),
          label: file.label,
          tooltip: file.path,
          selected: file.path == state.selected?.path,
          onTap: () => state.select(file.path),
        );
      },
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    super.key,
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          child: Container(
            color: selected ? scheme.secondaryContainer : null,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.state, required this.onOpenInEditor, required this.onNewHere});

  final IgnorePaneState state;
  final VoidCallback onOpenInEditor;
  final VoidCallback onNewHere;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _Header(state: state, onOpenInEditor: onOpenInEditor, onNewHere: onNewHere),
          const Divider(height: 1),
          Expanded(child: _Lines(state: state)),
        ],
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.onOpenInEditor, required this.onNewHere});

  final IgnorePaneState state;
  final VoidCallback onOpenInEditor;
  final VoidCallback onNewHere;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TitleRow(state: state),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                _PaneButton(
                  label: 'Open in editor',
                  icon: Icons.open_in_new,
                  tooltip: 'Open the selected .gitignore in the editor',
                  onPressed: onOpenInEditor,
                ),
                _PaneButton(
                  label: 'New here',
                  icon: Icons.note_add_outlined,
                  tooltip: 'Create a .gitignore next to the focused file',
                  onPressed: onNewHere,
                ),
              ],
            ),
          ],
        ),
      );
}

/// The selected path, and which line matches (or that nothing does).
class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.state});

  final IgnorePaneState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = state.matchLine;
    return Row(
      children: [
        Expanded(
          child: Text(
            state.selected?.path ?? 'no .gitignore selected',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            line == null ? 'no file matches' : 'line $line',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// The selected file's lines, one row each, with the matching line tinted.
class _Lines extends StatelessWidget {
  const _Lines({required this.state});

  final IgnorePaneState state;

  @override
  Widget build(BuildContext context) {
    final file = state.selected;
    if (file == null || file.lines.isEmpty) {
      return const Center(child: Text('nothing in this file'));
    }
    final matchLine = state.matchLine;
    return ListView.builder(
      itemCount: file.lines.length,
      itemBuilder: (context, index) => _Line(
        number: index + 1,
        text: file.lines[index],
        matched: index + 1 == matchLine,
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.number, required this.text, required this.matched});

  final int number;
  final String text;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: matched ? const ValueKey('ignore-matched-line') : ValueKey('ignore-line-$number'),
      color: matched ? scheme.primaryContainer : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '$number',
              textAlign: TextAlign.right,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: matched ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A header button with the pointer cursor and a tooltip; its label is part of
/// the control, so clicking the text does what the button does.
class _PaneButton extends StatelessWidget {
  const _PaneButton({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: TextButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label),
          ),
        ),
      );
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.all(8),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}
