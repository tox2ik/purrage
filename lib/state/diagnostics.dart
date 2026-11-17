import 'dart:async';

import 'package:flutter/foundation.dart';

import 'console.dart';
import 'failure.dart';

/// The app-wide error sink.
///
/// Flutter, the platform dispatcher and the zone all funnel here, so a crash in a
/// build method or an unawaited future lands in the Console mode instead of only
/// on a stderr nobody is watching. The current interaction is kept as context, so
/// a report says what the user was doing when it broke.
class Diagnostics {
  Diagnostics._();

  static ConsoleLog? log;

  /// What the app is doing: `Changes: track (2 selected)`, `open in editor`.
  static String context = 'startup';

  static void enter(String what) => context = what;

  static void leave() => context = 'idle';

  /// One uncaught error, with the stack and the context that produced it.
  static ActionFailure describe(
    Object error,
    StackTrace? stack, {
    required String source,
    String? summary,
  }) {
    final text = error is Error && error is! Exception ? '$error' : '$error';
    final detail = StringBuffer()
      ..writeln('origin: $source')
      ..writeln('context: $context')
      ..writeln('time: ${DateTime.now().toIso8601String()}')
      ..writeln('type: ${error.runtimeType}')
      ..writeln('exception: $text')
      ..writeln('stack:');
    if (stack == null) {
      detail.writeln('  (none)');
    } else {
      for (final line in stack.toString().split('\n').take(14)) {
        detail.writeln('  $line');
      }
    }
    return ActionFailure(
      summary: summary ?? _firstLine(text),
      detail: detail.toString(),
      origin: source,
    );
  }

  static void record(Object error, StackTrace? stack, {required String source}) {
    log?.add(describe(error, stack, source: source), action: 'uncaught');
  }

  /// Install the three handlers Flutter offers for errors that escape a call.
  static void install(ConsoleLog console) {
    log = console;

    FlutterError.onError = (details) {
      log!.add(
        ActionFailure(
          summary: _firstLine('${details.exception}'),
          detail: [
            'origin: ${details.library ?? 'FlutterError'}',
            'context: $context',
            if (details.context != null) 'widget: ${details.context}',
            'type: ${details.exception.runtimeType}',
            'exception: ${details.exception}',
            if (details.informationCollector != null)
              'information: '
                  '${details.informationCollector!().map((node) => node.toStringDeep()).join('\n')}',
          ].join('\n'),
          origin: details.library,
        ),
        action: 'flutter',
      );
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, source: 'PlatformDispatcher.onError');
      return true;
    };
  }

  /// Everything started after this call runs inside the guard.
  static void guard(void Function() body) {
    runZonedGuarded(body, (error, stack) {
      record(error, stack, source: 'zone');
    });
  }

  static String _firstLine(String text) {
    final line = text.split(RegExp(r'\r?\n')).firstWhere(
          (line) => line.trim().isNotEmpty,
          orElse: () => text,
        );
    return line.length > 200 ? '${line.substring(0, 197)}…' : line;
  }
}
