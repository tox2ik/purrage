import 'package:flutter/material.dart';
import '../state/console.dart';

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.log,
      builder: (context, _) {
        final entries = widget.log.entries;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(log: widget.log, count: entries.length),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('No failures this run.'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _Entry(
                          entry: entry,
                          expanded: open.contains(identityHashCode(entry)),
                          onToggle: () => setState(() {
                            final key = identityHashCode(entry);
                            if (!open.remove(key)) open.add(key);
                          }),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.log, required this.count});

  final ConsoleLog log;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Text('FAILURES  $count', style: Theme.of(context).textTheme.labelMedium),
          const Spacer(),
          Tooltip(
            message: 'Clear the log',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: TextButton(
                onPressed: count == 0 ? null : log.clear,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Clear'),
              ),
            ),
          ),
        ],
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
    final mono = const TextStyle(fontFamily: 'monospace', fontSize: 11.5);
    final failure = entry.failure;
    return Tooltip(
      message: expanded ? 'Fold the detail' : 'Show the detail',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
              color: expanded ? scheme.surfaceContainerHighest : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Title(entry: entry, expanded: expanded),
                if (expanded) ...[
                  const SizedBox(height: 6),
                  SelectableText(failure.detail, style: mono),
                  if (failure.code != null) ...[
                    const SizedBox(height: 4),
                    Text('code: ${failure.code}', style: mono.copyWith(color: scheme.error)),
                  ],
                ],
              ],
            ),
          ),
        ),
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
    final mono = const TextStyle(fontFamily: 'monospace', fontSize: 11.5);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.timeLabel, style: mono.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(width: 10),
        if (failure.code != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              failure.code!,
              style: mono.copyWith(color: scheme.onErrorContainer, fontSize: 10.5),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (entry.action != null) ...[
          Text(entry.action!, style: mono.copyWith(color: scheme.primary)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            failure.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: mono,
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

