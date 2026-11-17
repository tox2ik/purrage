import 'dart:io';

import 'package:flutter/material.dart';

import 'state/console.dart';
import 'state/diagnostics.dart';
import 'state/repo.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

void main(List<String> args) {
  // `purrage [directory]`; with no argument, the folder it was started in.
  final target = args.isEmpty ? Directory.current.path : args.first;

  // One console for the whole process: the window shows it, and the error
  // handlers below write to the same one.
  final console = ConsoleLog();
  Diagnostics.install(console);
  Diagnostics.enter('startup: opening $target');

  Diagnostics.guard(() {
    runApp(PurrageApp(directory: target, console: console));
  });
}

/// Opens the repository in [directory] and shows the shell; when that fails,
/// the error is the whole window, with git's text selectable.
class PurrageApp extends StatefulWidget {
  const PurrageApp({super.key, required this.directory, required this.console});

  final String directory;
  final ConsoleLog console;

  @override
  State<PurrageApp> createState() => _PurrageAppState();
}

class _PurrageAppState extends State<PurrageApp> {
  late final Future<Repo> repo = Repo.open(widget.directory);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Purrage',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: FutureBuilder<Repo>(
        future: repo,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error!;
            // The window could not open: say it here and in the console.
            Diagnostics.record(error, snapshot.stackTrace, source: 'PurrageApp.open(${widget.directory})');
            return _OpenError(message: error.toString(), console: widget.console);
          }
          final open = snapshot.data;
          if (open == null) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          Diagnostics.enter('Changes');
          return Shell(repo: open, console: widget.console);
        },
      ),
    );
  }
}

class _OpenError extends StatelessWidget {
  const _OpenError({required this.message, required this.console});

  final String message;
  final ConsoleLog console;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Cannot open a repository', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SelectableText(message),
                const SizedBox(height: 16),
                Text(
                  'The Console mode (Alt+3) holds the details once a repository is open; '
                  'this one failed before that, so it is in the log only.',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      );
}
