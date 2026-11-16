import 'package:flutter/material.dart';

/// One line of the help table. The table is the single source for the Help
/// mode; every key also appears in PLAN.md.
class KeyHelp {
  const KeyHelp(this.keys, this.what);

  final String keys;
  final String what;
}

const List<KeyHelp> keyTable = [
  KeyHelp('Alt+1 / Alt+2 / Alt+3', 'Changes, Settings, Help'),
  KeyHelp('Alt+] / Alt+[', 'next / previous mode'),
  KeyHelp('j k Up Down (W S)', 'move the cursor'),
  KeyHelp('Shift+Up / Shift+Down', 'extend the highlight from the anchor'),
  KeyHelp('Ctrl+Enter', 'highlight or un-highlight the cursor row'),
  KeyHelp('space / a', 'track (git add) the highlighted files'),
  KeyHelp('u', 'stop tracking, keep on disk'),
  KeyHelp('i', 'ignore: pick scope and which ignore file'),
  KeyHelp('c', 'jump to the commit message'),
  KeyHelp('/', 'filter the list (Esc clears, Enter leaves)'),
  KeyHelp('e / E', 'open the file / the selected .gitignore in the editor'),
  KeyHelp('Ctrl+click / Shift+click', 'select one more / select a range'),
  KeyHelp('r', 'refresh from git'),
  KeyHelp('Tab / Shift+Tab', 'next / previous pane'),
  KeyHelp('?', 'this list'),
  KeyHelp('Esc', 'leave the field or the menu'),
];

/// The Help mode: the key table, nothing else.
class HelpView extends StatelessWidget {
  const HelpView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Keys', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final help in keyTable) _KeyRow(help: help),
      ],
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.help});

  final KeyHelp help;

  @override
  Widget build(BuildContext context) {
    final mono = Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 240, child: Text(help.keys, style: mono)),
          Expanded(child: Text(help.what)),
        ],
      ),
    );
  }
}