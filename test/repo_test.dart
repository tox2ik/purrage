import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glustered/state/repo.dart';
import 'package:glustered/state/status.dart';

import 'support/temp_repo.dart';

void main() {
  group('Repo', () {
    test('opens a repository and reports a clean tree', () async {
      final temp = await TempRepo.make();
      final repo = await Repo.open(temp.path);
      expect(repo.path.toLowerCase(), endsWith(temp.path.split('/').last.toLowerCase()));
      expect(await repo.status(), isEmpty);
    });

    test('an untracked file shows up as one untracked row', () async {
      final temp = await TempRepo.make();
      await temp.write('notes.md', 'hello\n');
      final repo = await Repo.open(temp.path);
      final rows = await repo.status();
      expect(rows.single.section, Section.untracked);
      expect(rows.single.path, 'notes.md');
    });

    test('an ignored file is not listed', () async {
      final temp = await TempRepo.make();
      await temp.write('build/out.txt', 'x\n');
      final repo = await Repo.open(temp.path);
      expect(await repo.status(), isEmpty);
    });

    test('track stages a file, commit empties the list', () async {
      final temp = await TempRepo.make();
      await temp.write('a.txt', 'a\n');
      final repo = await Repo.open(temp.path);
      await repo.track(['a.txt']);
      final staged = await repo.status();
      expect(staged.single.section, Section.staged);
      await repo.commit('add a');
      expect(await repo.status(), isEmpty);
      final log = await temp.git(['log', '--oneline', '-1']);
      expect(log.stdout.toString(), contains('add a'));
    });

    test('untrack stops tracking but leaves the file on disk', () async {
      final temp = await TempRepo.make();
      await temp.write('keep.txt', 'k\n');
      final repo = await Repo.open(temp.path);
      await repo.track(['keep.txt']);
      await repo.commit('add keep');
      await repo.untrack('keep.txt');
      final rows = await repo.status();
      // The deletion is staged, and the file is back to being untracked.
      expect(rows.map((r) => r.section), [Section.staged, Section.untracked]);
      expect(rows.first.kind, RowKind.deleted);
      expect(await File('${temp.path}/keep.txt').exists(), isTrue);
    });

    test('checkIgnore names the file, line and pattern', () async {
      final temp = await TempRepo.make();
      await temp.write('.gitignore', 'build/\n*.log\n');
      await temp.write('run.log', 'x\n');
      final repo = await Repo.open(temp.path);
      final match = await repo.checkIgnore('run.log');
      expect(match, isNotNull);
      expect(match!.pattern, '*.log');
      expect(match.line, 2);
      expect(match.source, endsWith('.gitignore'));
    });

    test('checkIgnore returns null for a tracked path', () async {
      final temp = await TempRepo.make();
      final repo = await Repo.open(temp.path);
      expect(await repo.checkIgnore('.gitignore'), isNull);
    });

    test('preview reads text, marks binary and truncates', () async {
      final temp = await TempRepo.make();
      await temp.write('text.md', 'line one\nline two\n');
      await temp.write('data.bin', 'a\u0000b');
      final repo = await Repo.open(temp.path);
      expect((await repo.preview('text.md')).text, contains('line two'));
      expect((await repo.preview('data.bin')).binary, isTrue);
      expect((await repo.preview('text.md', maxBytes: 3)).truncated, isTrue);
    });
  });
}
