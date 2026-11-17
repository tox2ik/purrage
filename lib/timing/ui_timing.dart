import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// How long the actions take, from the key or click to the screen and to git's
/// answer, recorded per session and summarized into a state file
/// (`%APPDATA%/Purrage/ui-timing.json`) when the app quits, and every minute in
/// between. Ported from Ops (`nvimos-ops/lib/timing/ui_timing.dart`).
///
/// On in debug and profile builds, off in release; `PURRAGE_TIMING=1` / `0`
/// overrides. When off, every call is a cheap no-op. The spans sit in the state
/// actions (`changes.track`, `browse.scan`, ...), so no widget knows about it.
class UiTiming {
  UiTiming({required this.enabled, this.file, DateTime? started})
      : started = started ?? DateTime.now();

  static final instance = UiTiming(enabled: _enabledByDefault(), file: _defaultFile());

  static bool _enabledByDefault() {
    final env = Platform.environment['PURRAGE_TIMING'];
    if (env == '1') return true;
    if (env == '0') return false;
    return !kReleaseMode;
  }

  static File? _defaultFile() {
    final base = Platform.environment['APPDATA'] ?? Platform.environment['HOME'];
    return base == null ? null : File('$base/Purrage/ui-timing.json');
  }

  final bool enabled;
  final File? file;
  final DateTime started;
  final _samples = <String, List<double>>{};
  Timer? _flush;

  /// Durations in ms recorded this session, by name.
  Map<String, List<double>> get samples => _samples;

  void record(String name, Duration elapsed) {
    if (!enabled) return;
    _samples.putIfAbsent(name, () => []).add(elapsed.inMicroseconds / 1000);
  }

  /// Start timing an action; mark its phases, end it.
  Span span(String name) => enabled ? Span._(this, name) : Span._off;

  T sync<T>(String name, T Function() body) {
    if (!enabled) return body();
    final clock = Stopwatch()..start();
    try {
      return body();
    } finally {
      record(name, clock.elapsed);
    }
  }

  Future<T> time<T>(String name, Future<T> Function() body) async {
    if (!enabled) return body();
    final clock = Stopwatch()..start();
    try {
      return await body();
    } finally {
      record(name, clock.elapsed);
    }
  }

  // App wiring ----------------------------------------------------------------

  /// Start the session: every pointer down and key down is timed to the end of
  /// the next frame (`input.click→frame`, `input.key→frame`), and the summary is
  /// written every minute.
  void start() {
    if (!enabled) return;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
    _flush = Timer.periodic(const Duration(minutes: 1), (_) => save());
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) _toFrame('input.click→frame');
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyUpEvent) _toFrame('input.key→frame');
    return false;
  }

  void _toFrame(String name) {
    final clock = Stopwatch()..start();
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => record(name, clock.elapsed))
      ..scheduleFrame();
  }

  /// Write this session's summary into the state file: the last 30 sessions,
  /// and running totals. A failure to write is not the user's problem.
  Future<void> save({bool closing = false}) async {
    final target = file;
    if (!enabled || target == null) return;
    if (closing) _flush?.cancel();
    final data = await _read(target);
    final sessions = (data['sessions'] as List? ?? []).cast<Map<String, Object?>>()
      ..removeWhere((session) => session['started'] == started.toIso8601String());
    sessions.add(summary(closing: closing));
    data['sessions'] = sessions.length > 30 ? sessions.sublist(sessions.length - 30) : sessions;
    data['totals'] = _totals(sessions);
    try {
      await target.parent.create(recursive: true);
      await target.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    } on FileSystemException {
      // Timing is a diagnostic; a locked or missing folder must not crash the app.
    }
  }

  static Future<Map<String, Object?>> _read(File target) async {
    try {
      return (jsonDecode(await target.readAsString()) as Map).cast<String, Object?>();
    } on Object {
      return {};
    }
  }

  /// This session: per action, count and p50 / p95 / max in ms.
  Map<String, Object?> summary({bool closing = false}) => {
        'started': started.toIso8601String(),
        'ended': closing ? DateTime.now().toIso8601String() : null,
        'actions': {
          for (final entry in (_samples.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
            entry.key: stats(entry.value),
        },
      };

  /// Across the kept sessions: per action, total count, the worst p95 and max.
  static Map<String, Object?> _totals(List<Map<String, Object?>> sessions) {
    final out = <String, Map<String, num>>{};
    for (final session in sessions) {
      final actions = (session['actions'] as Map? ?? {}).cast<String, Map>();
      for (final MapEntry(:key, :value) in actions.entries) {
        final total = out.putIfAbsent(key, () => {'n': 0, 'p95': 0, 'max': 0});
        total['n'] = total['n']! + (value['n'] as num);
        total['p95'] = math.max(total['p95']!, value['p95'] as num);
        total['max'] = math.max(total['max']!, value['max'] as num);
      }
    }
    return out;
  }

  static Map<String, num> stats(List<double> ms) {
    final sorted = [...ms]..sort();
    double at(double q) => sorted[((sorted.length - 1) * q).round()];
    double round(double value) => (value * 10).round() / 10;
    return {
      'n': sorted.length,
      'p50': round(at(.5)),
      'p95': round(at(.95)),
      'max': round(sorted.last),
    };
  }

  /// One line per action, `name  n  p50  p95  max`, for a test or a log.
  String table({String filter = ''}) {
    final names = _samples.keys.where((name) => name.contains(filter)).toList()..sort();
    if (names.isEmpty) return '';
    final width = names.map((name) => name.length).reduce(math.max);
    final lines = ['${'action'.padRight(width)}      n      p50      p95      max'];
    for (final name in names) {
      final s = stats(_samples[name]!);
      lines.add('${name.padRight(width)} ${'${s['n']}'.padLeft(6)} '
          '${'${s['p50']}'.padLeft(8)} ${'${s['p95']}'.padLeft(8)} ${'${s['max']}'.padLeft(8)}');
    }
    return lines.join('\n');
  }
}

/// One timed action. Phases are recorded as `name/phase`, the whole as `name`.
class Span {
  Span._(this._timing, this.name) : _clock = Stopwatch()..start();

  static final _off = Span._(UiTiming(enabled: false), '');

  final UiTiming _timing;
  final String name;
  final Stopwatch _clock;

  void mark(String phase) => _timing.record('$name/$phase', _clock.elapsed);

  /// Mark [phase] when the next frame is on screen: what the user sees after the
  /// key or the click.
  void markPainted([String phase = 'frame']) {
    if (!_timing.enabled) return;
    try {
      SchedulerBinding.instance
        ..addPostFrameCallback((_) => mark(phase))
        ..scheduleFrame();
    } on Object {
      // No binding (plain unit tests): nothing is painted.
    }
  }

  void end() => _timing.record(name, _clock.elapsed);
}
