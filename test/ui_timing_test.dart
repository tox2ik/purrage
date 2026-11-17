import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/timing/ui_timing.dart';

Future<Directory> tempDir() async {
  final dir = await Directory.systemTemp.createTemp('purrage_timing_');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

void main() {
  test('stats: count, p50, p95, max in ms', () {
    final stats = UiTiming.stats([for (var i = 1; i <= 100; i++) i.toDouble()]);
    expect(stats, {'n': 100, 'p50': 51, 'p95': 95, 'max': 100});
  });

  test('a span records the whole action and each phase', () {
    final timing = UiTiming(enabled: true);
    final span = timing.span('changes.track');
    span.mark('optimistic');
    span.mark('git');
    span.end();
    expect(
      timing.samples.keys,
      unorderedEquals(['changes.track', 'changes.track/optimistic', 'changes.track/git']),
    );
    // Without a binding there is no frame to wait for, and nothing is recorded.
    span.markPainted();
    expect(timing.samples.containsKey('changes.track/frame'), isFalse);
  });

  test('sync and time return the body result and record one sample', () async {
    final timing = UiTiming(enabled: true);
    expect(timing.sync('a', () => 7), 7);
    expect(await timing.time('b', () async => 'x'), 'x');
    expect(timing.samples['a'], hasLength(1));
    expect(timing.samples['b'], hasLength(1));
  });

  test('time records even when the body throws', () async {
    final timing = UiTiming(enabled: true);
    await expectLater(timing.time('boom', () async => throw StateError('x')), throwsStateError);
    expect(timing.samples['boom'], hasLength(1));
  });

  test('summary lists the actions sorted, with their stats', () {
    final timing = UiTiming(enabled: true, started: DateTime(2026, 11, 17));
    timing.record('z.last', const Duration(milliseconds: 4));
    timing.record('a.first', const Duration(milliseconds: 2));
    timing.record('a.first', const Duration(milliseconds: 6));
    final summary = timing.summary(closing: true);
    final actions = summary['actions'] as Map<String, Object?>;
    expect(actions.keys, ['a.first', 'z.last']);
    expect(actions['a.first'], {'n': 2, 'p50': 6, 'p95': 6, 'max': 6});
    expect(summary['ended'], isNotNull);
    expect(timing.table(), contains('a.first'));
    expect(timing.table(filter: 'z.'), isNot(contains('a.first')));
  });

  test('save keeps one entry per session, the last 30, and totals', () async {
    final dir = await tempDir();
    final file = File('${dir.path}/sub/ui-timing.json');
    for (var i = 0; i < 32; i++) {
      final timing = UiTiming(enabled: true, file: file, started: DateTime(2026, 1, 1, 0, i));
      timing.record('changes.move', Duration(milliseconds: i));
      await timing.save();
      await timing.save(closing: true); // the same session again: replaced, not added
    }
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final sessions = data['sessions'] as List;
    expect(sessions, hasLength(30));
    expect(sessions.last['ended'], isNotNull);
    expect(sessions.first['actions']['changes.move']['max'], 2);
    expect(data['totals']['changes.move'], {'n': 30, 'p95': 31, 'max': 31});
  });

  test('off: records nothing, writes nothing', () async {
    final dir = await tempDir();
    final file = File('${dir.path}/ui-timing.json');
    final timing = UiTiming(enabled: false, file: file);
    timing.record('changes.move', const Duration(milliseconds: 5));
    timing.span('a')
      ..mark('b')
      ..markPainted()
      ..end();
    await timing.save(closing: true);
    expect(timing.samples, isEmpty);
    expect(await file.exists(), isFalse);
  });

  test('a broken state file is replaced, not fatal', () async {
    final dir = await tempDir();
    final file = File('${dir.path}/ui-timing.json');
    await file.writeAsString('{ not json');
    final timing = UiTiming(enabled: true, file: file);
    timing.record('changes.load', const Duration(milliseconds: 3));
    await timing.save();
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(data['sessions'], hasLength(1));
  });
}
