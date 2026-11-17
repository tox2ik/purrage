import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/console.dart';
import '../state/list_cursor.dart';
import 'app_keys.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Console mode: every failed user action, newest first, each with its
/// detail — origin, parameters, command line, code, tool text.
class ConsoleView extends StatefulWidget {
  const ConsoleView({super.key, required this.log, required this.focusNode});

  final ConsoleLog log;

  /// The list's keyboard stop; the shell gives it the keyboard on Alt+4.
  final FocusNode focusNode;

  @override
  State<ConsoleView> createState() => ConsoleViewState();
}

class ConsoleViewState extends State<ConsoleView> {
  final Set<int> open = {};
  final ListCursor cursor = ListCursor();

  @override
  void dispose() {
    cursor.dispose();
    super.dispose();
  }

  bool _isOpen(ConsoleEntry entry) => open.contains(identityHashCode(entry));

  /// Fold or unfold one entry's detail.
  void _toggle(ConsoleEntry entry) {
    final key = identityHashCode(entry);
    setState(() => open.remove(key) || open.add(key));
  }

  ConsoleEntry? get _current {
    final entries = widget.log.entries;
    cursor.sync(entries.length);
    return entries.isEmpty ? null : entries[cursor.index];
  }

  /// Enter / l: fold or unfold the row under the cursor.
  void toggleCurrent() {
    final entry = _current;
    if (entry != null) _toggle(entry);
  }

  /// Ctrl+C: the row's detail, as the console shows it, to the clipboard.
  Future<void> copyCurrent() async {
    final entry = _current;
    if (entry == null) return;
    await Clipboard.setData(ClipboardData(text: '${entry.failure.summary}\n${entry.failure.detail}'));
  }

  late final Map<Type, Action<Intent>> _actions = {
    MoveIntent: CallbackAction<MoveIntent>(onInvoke: (intent) => cursor.move(intent.delta)),
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => toggleCurrent()),
    CopyIntent: CallbackAction<CopyIntent>(onInvoke: (_) => copyCurrent()),
  };

  @override
  Widget build(BuildContext context) {
    return KeyScope(
      bindings: const [...motionBindings, ...consoleBindings],
      actions: _actions,
      focusNode: widget.focusNode,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.log, cursor]),
        builder: (context, _) => _page(widget.log.entries),
      ),
    );
  }

  Widget _page(List<ConsoleEntry> entries) {
    cursor.sync(entries.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(
          title: 'CONSOLE  ${entries.length}',
          trailing: [
            SmallButton(
              label: 'Clear',
              tooltip: 'Clear the log',
              onPressed: entries.isEmpty ? null : widget.log.clear,
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(child: _entries(entries)),
      ],
    );
  }

  Widget _entries(List<ConsoleEntry> entries) {
    if (entries.isEmpty) return const Center(child: Text('No failures this run.'));
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) => _Entry(
        entry: entries[index],
        expanded: _isOpen(entries[index]),
        focused: index == cursor.index,
        onToggle: () => _toggle(entries[index]),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.entry,
    required this.expanded,
    required this.focused,
    required this.onToggle,
  });

  final ConsoleEntry entry;
  final bool expanded;
  final bool focused;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return HoverRow(
      tooltip: expanded ? 'Fold the detail (Enter)' : 'Show the detail (Enter)',
      onTap: onToggle,
      padding: const EdgeInsets.fromLTRB(9, 6, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant),
          left: BorderSide(width: T.barWidth, color: focused ? scheme.primary : T.none),
        ),
        color: expanded ? scheme.surfaceContainerHighest : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Title(entry: entry, expanded: expanded),
          if (expanded) _Detail(entry: entry),
        ],
      ),
    );
  }
}

final _mono = T.codeSmall;

class _Detail extends StatelessWidget {
  const _Detail({required this.entry});

  final ConsoleEntry entry;

  @override
  Widget build(BuildContext context) {
    final failure = entry.failure;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(failure.detail, style: _mono),
          if (failure.code != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'code: ${failure.code}',
                style: _mono.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.entry, required this.expanded});

  final ConsoleEntry entry;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failure = entry.failure;
    final code = failure.code;
    final action = entry.action;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.timeLabel, style: _mono.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(width: T.gap8),
        if (code != null) ...[
          Pill(code, color: scheme.onErrorContainer, background: scheme.errorContainer),
          const SizedBox(width: T.gap8),
        ] else if (failure.error) ...[
          // A failure is never told apart by its red alone: no code, an icon.
          Icon(Icons.error_outline, size: T.iconSmall, color: scheme.error, semanticLabel: 'failure'),
          const SizedBox(width: T.gap8),
        ],
        if (action != null) ...[
          Text(action, style: _mono.copyWith(color: scheme.primary)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            failure.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _mono.copyWith(color: failure.error ? scheme.error : null),
          ),
        ),
        Icon(
          expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
          size: T.icon,
          color: scheme.onSurfaceVariant,
        ),
      ],
    );
  }
}
