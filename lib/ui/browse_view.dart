import 'package:flutter/material.dart';

import '../state/browser.dart';

/// The Browse mode: the directory being browsed, the repositories found below it,
/// a way up a level and, on Windows, a drive picker.
class BrowseView extends StatefulWidget {
  const BrowseView({
    super.key,
    required this.browser,
    required this.current,
    required this.onOpen,
  });

  final RepoBrowser browser;

  /// The repository currently open, marked in the list.
  final String current;

  final ValueChanged<String> onOpen;

  @override
  State<BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<BrowseView> {
  List<String> drives = const [];

  @override
  void initState() {
    super.initState();
    RepoBrowser.drives().then((found) {
      if (mounted) setState(() => drives = found);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.browser,
      builder: (context, _) {
        final browser = widget.browser;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              browser: browser,
              drives: drives,
              onUp: browser.up,
              onScan: browser.rescan,
              onDrive: (root) => browser.goTo(root),
            ),
            const Divider(height: 1),
            Expanded(child: _List(browser: browser, current: widget.current, onOpen: widget.onOpen)),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.browser,
    required this.drives,
    required this.onUp,
    required this.onScan,
    required this.onDrive,
  });

  final RepoBrowser browser;
  final List<String> drives;
  final VoidCallback onUp;
  final VoidCallback onScan;
  final ValueChanged<String> onDrive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          _Button(icon: Icons.arrow_upward, tooltip: 'Up one level', onTap: onUp),
          const SizedBox(width: 4),
          _Button(icon: Icons.refresh, tooltip: 'Scan this directory again', onTap: onScan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              browser.directory,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: mono,
            ),
          ),
          if (browser.scanning) ...[
            const SizedBox(width: 10),
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
          if (drives.isNotEmpty) ...[
            const SizedBox(width: 10),
            _DrivePicker(drives: drives, onPicked: onDrive),
          ],
          const SizedBox(width: 8),
          Text('${browser.repos.length} repo(s)', style: mono),
        ],
      ),
    );
  }
}

class _DrivePicker extends StatelessWidget {
  const _DrivePicker({required this.drives, required this.onPicked});

  final List<String> drives;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Switch drive',
      child: DropdownButton<String>(
        value: null,
        hint: Text('Drive', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
        isDense: true,
        underline: const SizedBox.shrink(),
        padding: EdgeInsets.zero,
        items: [
          for (final root in drives)
            DropdownMenuItem(
              value: root,
              child: Text(root.substring(0, 2), style: TextStyle(fontSize: 11.5, color: scheme.onSurface)),
            ),
        ],
        onChanged: (root) {
          if (root != null) onPicked(root);
        },
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: IconButton(
            icon: Icon(icon, size: 16),
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            onPressed: onTap,
          ),
        ),
      );
}

class _List extends StatelessWidget {
  const _List({required this.browser, required this.current, required this.onOpen});

  final RepoBrowser browser;
  final String current;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (browser.repos.isEmpty) {
      return Center(
        child: Text(
          browser.scanning ? 'Scanning…' : 'No git repository within five levels.',
          textAlign: TextAlign.center,
        ),
      );
    }
    final open = current.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '');
    return ListView.builder(
      itemCount: browser.repos.length,
      itemBuilder: (context, index) {
        final repo = browser.repos[index];
        return _RepoRow(
          path: repo,
          isCurrent: repo.toLowerCase() == open.toLowerCase(),
          onTap: () => onOpen(repo),
        );
      },
    );
  }
}

class _RepoRow extends StatelessWidget {
  const _RepoRow({required this.path, required this.isCurrent, required this.onTap});

  final String path;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = path.replaceAll(r'\', '/').split('/').last;
    final parent = path.length > name.length ? path.substring(0, path.length - name.length - 1) : '';
    return Tooltip(
      message: isCurrent ? 'Already open: $path' : 'Open $path',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: isCurrent ? scheme.primaryContainer.withValues(alpha: 0.45) : null,
              border: Border(
                left: BorderSide(
                  width: 3,
                  color: isCurrent ? scheme.primary : Colors.transparent,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(9, 4, 12, 4),
            child: Row(
              children: [
                Icon(Icons.commit, size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Text(name, style: TextStyle(fontSize: 12.5, color: scheme.onSurface)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    parent,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (isCurrent)
                  Text('open', style: TextStyle(fontSize: 10.5, color: scheme.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
