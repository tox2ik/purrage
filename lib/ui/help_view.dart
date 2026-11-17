import 'package:flutter/material.dart';

import 'app_keys.dart';
import 'theme.dart';

/// One line of the help table. Every key also appears in PLAN.md.
class KeyHelp {
  const KeyHelp(this.keys, this.what);

  final String keys;
  final String what;
}

/// The help table, read from the same bindings the `Shortcuts` are built from
/// (`app_keys.dart`), so a key and its line cannot drift apart. A line with no
/// keys is a section title.
final List<KeyHelp> keyTable = [
  for (final (title, bindings) in helpGroups) ...[
    KeyHelp('', title),
    for (final binding in helpLines(bindings)) KeyHelp(binding.keys, binding.what),
  ],
];

/// The Help mode: the key table, nothing else.
class HelpView extends StatelessWidget {
  const HelpView({super.key, this.focusNode});

  /// The mode's keyboard stop, so the shell can give Help the keyboard.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Keys', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final help in keyTable) _KeyRow(help: help),
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.help});

  final KeyHelp help;

  @override
  Widget build(BuildContext context) {
    if (help.keys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(help.what, style: Theme.of(context).textTheme.labelLarge),
      );
    }
    final mono = T.code;
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