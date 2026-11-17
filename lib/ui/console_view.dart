import 'package:flutter/material.dart';

import '../state/console.dart';
import 'widgets.dart';

/// The Console mode: every failed user action, newest first, each with its
/// detail — origin, parameters, command line, code, tool text.
class ConsoleView extends StatefulWidget {
  const ConsoleView({super.key, required this.log});

  final ConsoleLog log;

  @override
  State<ConsoleView> createState() => _ConsoleViewState();
}

class _ConsoleViewState extends State<ConsoleView> {
  final Set<int> open = {};

  bool _isOpen(ConsoleEntry entry) => open.contains(identityHashCode(entry));

  /// Fold or unfold one entry's detail.
  void _toggle(ConsoleEntry entry) {
    final key = identityHashCode(entry);
    setState(() => open.remove(key) || open.add(key));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.log,
      builder: (context, _) {
        final entries = widget.log.entries;
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
      },
    );
  }

  Widget _entries(List<ConsoleEntry> entries) {
    if (entries.isEmpty) return const Center(child: Text('No failures this run.'));
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) => _Entry(
        entry: entries[index],
        expanded: _isOpen(entries[index]),
        onToggle: () => _toggle(entries[index]),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.entry, required this.expanded, required this.onToggle});

  final ConsoleEntry entry;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return HoverRow(
      tooltip: expanded ? 'Fold the detail' : 'Show the detail',
      onTap: onToggle,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
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

const _mono = TextStyle(fontFamily: 'monospace', fontSize: 11.5);

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
        const SizedBox(width: 10),
        if (code != null) ...[
          Pill(code, color: scheme.onErrorContainer, background: scheme.errorContainer),
          const SizedBox(width: 8),
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
          size: 15,
          color: scheme.onSurfaceVariant,
        ),
      ],
    );
  }
}
