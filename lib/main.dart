import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'state/console.dart';
import 'state/diagnostics.dart';
import 'state/failure.dart';
import 'state/repo.dart';
import 'state/workspace.dart';
import 'timing/ui_timing.dart';
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

  // The first console row names the launch, so "which build am I looking at" has
  // an answer without reading process start times.
  final started = DateTime.now();
  console.add(
    ActionFailure.done(
      summary: 'Purrage started ${started.toIso8601String().substring(11, 19)} '
          '(${kReleaseMode ? 'release' : 'debug'})',
      detail: [
        'started: ${started.toIso8601String()}',
        'build: ${kReleaseMode ? 'release' : 'debug'}',
        'pid: $pid',
        'directory: $target',
      ].join('\n'),
    ),
    action: 'startup',
  );

  Diagnostics.guard(() {
    WidgetsFlutterBinding.ensureInitialized();
    UiTiming.instance.start();
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
  /// Built once: the shell owns the workspace and disposes it.
  late final Future<Workspace> workspace = Repo.open(widget.directory).then(
    (repo) => Workspace(repo: repo, opener: Repo.open, console: widget.console),
  );
  late final AppLifecycleListener lifecycle;

  @override
  void initState() {
    super.initState();
    lifecycle = AppLifecycleListener(onExitRequested: onExit);
  }

  @override
  void dispose() {
    lifecycle.dispose();
    super.dispose();
  }

  /// Closing the window: write this session's timings, then quit.
  Future<AppExitResponse> onExit() async {
    await UiTiming.instance.save(closing: true);
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Purrage',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: FutureBuilder<Workspace>(
        future: workspace,
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
          return Shell(workspace: open);
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
                  'The ${Mode.console.label} mode (${Mode.console.key}) holds the details '
                  'once a repository is open; '
                  'this one failed before that, so it is in the log only.',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      );
}
