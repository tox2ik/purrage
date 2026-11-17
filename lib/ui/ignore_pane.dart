import 'package:flutter/material.dart';

import '../state/ignore_files.dart';
import 'app_keys.dart';
import 'theme.dart';
import 'widgets.dart';

/// The read-only `.gitignore` pane: a rail of every ignore file, the selected
/// file's lines, and the line that matches the focused path.
class IgnorePane extends StatelessWidget {
  const IgnorePane({
    super.key,
    required this.state,
    required this.onOpenInEditor,
    required this.onNewHere,
    this.railFocus,
    this.linesFocus,
    this.onOpenFile,
  });

  final IgnorePaneState state;
  final VoidCallback onOpenInEditor;
  final VoidCallback onNewHere;

  /// Open an ignore file the rail does not list (exclude, global), by path.
  final ValueChanged<String>? onOpenFile;

  /// The two Tab stops of the pane: the file rail (j/k pick a file) and the
  /// lines (j/k scroll). Without them the pane takes no keys.
  final FocusNode? railFocus;
  final FocusNode? linesFocus;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Column(
        children: [
          if (state.error != null) _ErrorLine(message: state.error!),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  /// The rail takes half the pane, up to its old 180 px, so a narrow pane
  /// keeps room for the lines.
  Widget _body() => LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            SizedBox(
              width: (box.maxWidth / 2).clamp(0, 180),
              child: _keys(railFocus, _railActions, _FileRail(state: state)),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _Detail(
                state: state,
                linesFocus: linesFocus,
                onOpenInEditor: onOpenInEditor,
                onNewHere: onNewHere,
                onOpenFile: onOpenFile,
              ),
            ),
          ],
        ),
      );

  Map<Type, Action<Intent>> get _railActions => {
        MoveIntent: CallbackAction<MoveIntent>(onInvoke: (intent) => state.selectBy(intent.delta)),
      };
}

/// [child] with the motion keys of [actions] while [node] has the keyboard.
Widget _keys(FocusNode? node, Map<Type, Action<Intent>> actions, Widget child) => node == null
    ? child
    : KeyScope(bindings: motionBindings, actions: actions, focusNode: node, child: child);

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
          onTap: () => state.pick(file.path),
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
    return HoverRow(
      tooltip: tooltip,
      onTap: onTap,
      decoration: BoxDecoration(color: selected ? scheme.secondaryContainer : null),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: T.code.copyWith(color: selected ? scheme.onSurface : scheme.onSurfaceVariant),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.state,
    required this.linesFocus,
    required this.onOpenInEditor,
    required this.onNewHere,
    required this.onOpenFile,
  });

  final IgnorePaneState state;
  final FocusNode? linesFocus;
  final VoidCallback onOpenInEditor;
  final VoidCallback onNewHere;
  final ValueChanged<String>? onOpenFile;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _Header(
            state: state,
            onOpenInEditor: onOpenInEditor,
            onNewHere: onNewHere,
            onOpenFile: onOpenFile,
          ),
          const Divider(height: 1),
          Expanded(child: _Lines(state: state, focusNode: linesFocus)),
        ],
      );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.onOpenInEditor,
    required this.onNewHere,
    required this.onOpenFile,
  });

  final IgnorePaneState state;
  final VoidCallback onOpenInEditor;
  final VoidCallback onNewHere;
  final ValueChanged<String>? onOpenFile;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TitleRow(state: state),
            if (state.outsideMatch != null)
              _OutsideLine(match: state.outsideMatch!, onOpen: onOpenFile),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                SmallButton(
                  label: 'Open in editor',
                  icon: Icons.open_in_new,
                  tooltip: 'Open the selected .gitignore in the editor (E)',
                  onPressed: onOpenInEditor,
                ),
                SmallButton(
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
    return Row(
      children: [
        Expanded(
          child: Text(
            state.selected?.path ?? 'no .gitignore selected',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: T.code,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            state.verdict,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: T.tiny.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// The selected file's lines, one row each, with the matching line tinted.
class _Lines extends StatefulWidget {
  const _Lines({required this.state, required this.focusNode});

  final IgnorePaneState state;
  final FocusNode? focusNode;

  @override
  State<_Lines> createState() => _LinesState();
}

class _LinesState extends State<_Lines> {
  final ScrollController scroll = ScrollController();

  /// Every line has this height, so the matching one is found by index.
  static const extent = 20.0;

  int? _revealed;
  String? _revealedIn;

  /// Motion keys scroll by lines, clamped.
  void scrollBy(MoveIntent intent) {
    if (!scroll.hasClients) return;
    final position = scroll.position;
    final target = position.pixels + intent.delta.clamp(-1 << 20, 1 << 20) * extent;
    scroll.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  /// After a frame that shows a new match (or the match in a newly selected
  /// file), bring its line into view.
  void _revealAfterFrame() {
    final line = widget.state.matchLine;
    final file = widget.state.selected?.path;
    if (line == _revealed && file == _revealedIn) return;
    _revealed = line;
    _revealedIn = file;
    WidgetsBinding.instance.addPostFrameCallback((_) => reveal());
  }

  /// Scroll only when the matching line is outside the viewport, and then put it
  /// in the middle.
  void reveal() {
    final line = widget.state.matchLine;
    if (line == null || !mounted || !scroll.hasClients) return;
    final position = scroll.position;
    final top = (line - 1) * extent;
    final inView = top >= position.pixels && top + extent <= position.pixels + position.viewportDimension;
    if (inView) return;
    final centred = top - (position.viewportDimension - extent) / 2;
    scroll.jumpTo(centred.clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final actions = {MoveIntent: CallbackAction<MoveIntent>(onInvoke: scrollBy)};
    return _keys(widget.focusNode, actions, _list());
  }

  Widget _list() {
    final file = widget.state.selected;
    if (file == null || file.lines.isEmpty) {
      return const Center(child: Text('nothing in this file'));
    }
    final matchLine = widget.state.matchLine;
    _revealAfterFrame();
    return ListView.builder(
      controller: scroll,
      itemExtent: extent,
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
              style: T.code.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: T.code.copyWith(color: matched ? scheme.onPrimaryContainer : scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rule from a file the rail does not list: the sentence and an Open button.
class _OutsideLine extends StatelessWidget {
  const _OutsideLine({required this.match, required this.onOpen});

  final OutsideMatch match;
  final ValueChanged<String>? onOpen;

  void open() => onOpen?.call(match.absolutePath);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: match.absolutePath,
            child: Text(
              match.sentence,
              key: const ValueKey('ignore-outside-match'),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: T.code,
            ),
          ),
        ),
        if (onOpen != null)
          SmallButton(
            label: 'Open',
            icon: Icons.open_in_new,
            tooltip: 'Open ${match.file} in the editor',
            onPressed: open,
          ),
      ],
    );
  }
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
