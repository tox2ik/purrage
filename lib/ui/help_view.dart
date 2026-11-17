import 'package:flutter/material.dart';

import 'app_keys.dart';

/// One line of the help table. Every key also appears in PLAN.md.
class KeyHelp {
  const KeyHelp(this.keys, this.what);

  final String keys;
  final String what;
}

/// The help table, read from the same bindings the `Shortcuts` are built from
/// (`app_keys.dart`), so a key and its line cannot drift apart.
final List<KeyHelp> keyTable = [
  for (final binding in helpLines(allBindings))
    KeyHelp(binding.keys, binding.what),
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