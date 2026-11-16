import 'dart:io';

import 'package:flutter/material.dart';

import 'state/repo.dart';
import 'ui/shell.dart';

void main(List<String> args) {
  // `glustered [directory]`; with no argument, the folder it was started in.
  final target = args.isEmpty ? Directory.current.path : args.first;
  runApp(GlusteredApp(directory: target));
}

/// Opens the repository in [directory] and shows the shell; when that fails,
/// the error is the whole window, with git's text selectable.
class GlusteredApp extends StatefulWidget {
  const GlusteredApp({super.key, required this.directory});

  final String directory;

  @override
  State<GlusteredApp> createState() => _GlusteredAppState();
}

class _GlusteredAppState extends State<GlusteredApp> {
  late final Future<Repo> repo = Repo.open(widget.directory);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glustered',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4C6EF5),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: FutureBuilder<Repo>(
        future: repo,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _OpenError(message: snapshot.error.toString());
          }
          final open = snapshot.data;
          if (open == null) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return Shell(repo: open);
        },
      ),
    );
  }
}

class _OpenError extends StatelessWidget {
  const _OpenError({required this.message});

  final String message;

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
              ],
            ),
          ),
        ),
      );
}
