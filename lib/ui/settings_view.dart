import 'package:flutter/material.dart';

import '../state/editors.dart';
import 'widgets.dart';

/// The Settings mode: which editor was found, which one is in use, and the
/// command template it starts. All work is done by the callbacks the shell
/// wires to `Editors` and `Prefs`; this view only presents and collects.
class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.detect,
    required this.chosenCommand,
    required this.onChoose,
    required this.onTest,
  });

  /// Find the editors on this machine, best first.
  final Future<List<EditorOption>> Function() detect;

  /// The saved command, or an empty string when nothing has been saved.
  final String chosenCommand;

  /// Persist a new choice; null clears it.
  final ValueChanged<String?> onChoose;

  /// Open a file with the current choice, for the Test button.
  final Future<void> Function(String file) onTest;

  /// The file the Test button opens.
  static const String testFile = 'PLAN.md';

  @override
  State<SettingsView> createState() => SettingsViewState();
}

class SettingsViewState extends State<SettingsView> {
  final TextEditingController command = TextEditingController();
  List<EditorOption> options = const [];
  String chosen = '';
  bool detecting = true;

  @override
  void initState() {
    super.initState();
    chosen = widget.chosenCommand;
    command.text = chosen;
    detectEditors();
  }

  @override
  void didUpdateWidget(SettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chosenCommand == widget.chosenCommand) return;
    chosen = widget.chosenCommand;
    if (command.text != chosen) command.text = chosen;
  }

  @override
  void dispose() {
    command.dispose();
    super.dispose();
  }

  /// Run detection again; with no saved choice, the winner becomes active.
  Future<void> detectEditors() async {
    setState(() => detecting = true);
    final found = await widget.detect();
    if (!mounted) return;
    setState(() {
      options = found;
      detecting = false;
      if (chosen.isEmpty) {
        chosen = found.isEmpty ? '' : found.first.command;
        command.text = chosen;
      }
    });
  }

  /// Use one detected editor: mark it, fill the field, save the choice.
  void pickEditor(EditorOption option) {
    setState(() {
      chosen = option.command;
      command.text = chosen;
    });
    widget.onChoose(option.command);
  }

  /// The Test button: hand `PLAN.md` to the caller, and say when it fails.
  Future<void> testEditor() async {
    try {
      await widget.onTest(SettingsView.testFile);
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Header(detecting: detecting, onDetect: detectEditors),
        const SizedBox(height: 12),
        _DetectedList(options: options, chosen: chosen, onPick: pickEditor),
        const SizedBox(height: 24),
        _CommandEditor(
          controller: command,
          onChanged: widget.onChoose,
          onTest: testEditor,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detecting, required this.onDetect});

  final bool detecting;
  final VoidCallback onDetect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text('Editor', style: Theme.of(context).textTheme.titleMedium),
        ),
        SmallButton(
          label: detecting ? 'Looking…' : 'Detect again',
          tooltip: 'Look for editors on this machine again',
          icon: Icons.refresh,
          onPressed: detecting ? null : onDetect,
        ),
      ],
    );
  }
}

class _DetectedList extends StatelessWidget {
  const _DetectedList({
    required this.options,
    required this.chosen,
    required this.onPick,
  });

  final List<EditorOption> options;
  final String chosen;
  final ValueChanged<EditorOption> onPick;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const Text('No editor found. Type a command below.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final option in options)
          _EditorRow(
            option: option,
            active: option.command == chosen,
            onPick: () => onPick(option),
          ),
      ],
    );
  }
}

class _EditorRow extends StatelessWidget {
  const _EditorRow({
    required this.option,
    required this.active,
    required this.onPick,
  });

  final EditorOption option;
  final bool active;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The whole tile is the control: the label, the path and the radio pick it.
    return Clickable(
      tooltip: option.detected ? 'Use ${option.label}' : '${option.label}: not on this machine',
      child: ListTile(
        dense: true,
        selected: active,
        onTap: onPick,
        leading: Icon(
          active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: active ? scheme.primary : null,
        ),
        title: Text(option.label),
        subtitle: Text(_detail(option), style: _mono(context)),
        trailing: active ? Text('in use', style: TextStyle(color: scheme.primary)) : null,
      ),
    );
  }

  static String _detail(EditorOption option) {
    if (option.path != null) return option.path!;
    return option.command.isEmpty ? 'not detected' : option.command;
  }

  static TextStyle? _mono(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
}

class _CommandEditor extends StatelessWidget {
  const _CommandEditor({
    required this.controller,
    required this.onChanged,
    required this.onTest,
  });

  final TextEditingController controller;
  final ValueChanged<String?> onChanged;
  final Future<void> Function() onTest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Command', style: Theme.of(context).textTheme.titleMedium),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '{file} is the path to open, {line} the line number.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _CommandField(
                controller: controller,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 8),
            SmallButton(
              label: 'Test',
              tooltip: 'Open PLAN.md in this editor',
              icon: Icons.open_in_new,
              filled: true,
              onPressed: onTest,
            ),
          ],
        ),
      ],
    );
  }
}

class _CommandField extends StatelessWidget {
  const _CommandField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontFamily: 'monospace'),
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        hintText: 'nvim-qt {file}',
      ),
    );
  }
}

