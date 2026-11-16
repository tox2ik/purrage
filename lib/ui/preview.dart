import 'package:flutter/material.dart';

import '../state/repo.dart';

/// The right pane: the text of the focused file, read-only and selectable.
class PreviewPane extends StatelessWidget {
  const PreviewPane({super.key, required this.preview, required this.path});

  final FilePreview? preview;
  final String? path;

  @override
  Widget build(BuildContext context) {
    if (path == null) {
      return const _Empty(message: 'Select a file to see its text.');
    }
    final shown = preview;
    if (shown == null) {
      return const _Empty(message: 'Loading…');
    }
    if (shown.binary) {
      return _Empty(message: 'Binary file: $path');
    }
    if (shown.text.isEmpty) {
      return _Empty(message: 'Empty file: $path');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(path: path!, truncated: shown.truncated),
        const Divider(height: 1),
        Expanded(child: _Text(text: shown.text)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.path, required this.truncated});

  final String path;
  final bool truncated;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                path,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            if (truncated)
              Text(
                'truncated',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
      );
}

class _Text extends StatelessWidget {
  const _Text({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      );
}
