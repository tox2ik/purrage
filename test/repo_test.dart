import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/git_repo.dart';
import 'package:purrage/state/repo.dart';
import 'package:purrage/state/status.dart';

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
      await repo.untrack(['keep.txt']);
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

    test('appendIgnoreLine creates a file with a header and then appends', () async {
      final temp = await TempRepo.make();
      final repo = await Repo.open(temp.path);
      final nested = '${temp.path}/lib/generated/.gitignore';

      expect(await repo.appendIgnoreLine(nested, '/cache/'), IgnoreAppend.added);
      expect(await repo.appendIgnoreLine(nested, '*.g.dart'), IgnoreAppend.added);
      expect(await repo.appendIgnoreLine(nested, '*.g.dart'), IgnoreAppend.duplicate);

      final text = await File(nested).readAsString();
      expect(text, startsWith('# Purrage\n'));
      expect(text.split('\n').where((line) => line.isNotEmpty), [
        '# Purrage',
        '/cache/',
        '*.g.dart',
      ]);
    });

    test('appendIgnoreLine keeps CRLF and adds no blank line between rules', () async {
      final temp = await TempRepo.make();
      await temp.write('.gitignore', 'build/\r\n*.log\r\n');
      final repo = await Repo.open(temp.path);
      await repo.appendIgnoreLine('${temp.path}/.gitignore', '/notes.md');
      final text = await File('${temp.path}/.gitignore').readAsString();
      expect(text, 'build/\r\n*.log\r\n/notes.md\r\n');
    });

    test('a nested rule can be written and git honours it', () async {
      final temp = await TempRepo.make();
      await temp.write('lib/generated/a.g.dart', 'x\n');
      final repo = await Repo.open(temp.path);
      final targets = await repo.gitignoreFiles();
      expect(targets, contains('.gitignore'));
      final nested = '${temp.path}/lib/generated/.gitignore';
      await repo.appendIgnoreLine(nested, '/a.g.dart');
      expect(await repo.checkIgnore('lib/generated/a.g.dart'), isNotNull);
      final rows = await repo.status();
      expect(rows.map((r) => r.path), isNot(contains('lib/generated/a.g.dart')));
    });
  });

  group('one git call per action', () {
    test('untrack takes paths with spaces and non-ASCII in one call', () async {
      final temp = await TempRepo.make();
      await temp.write('my notes.txt', 'n\n');
      await temp.write('ærø/blåbær.txt', 'b\n');
      final repo = await Repo.open(temp.path);
      await repo.track(['my notes.txt', 'ærø/blåbær.txt']);
      await repo.commit('add two');
      await repo.untrack(['my notes.txt', 'ærø/blåbær.txt']);
      expect(repo.lastCommand, startsWith('git rm --cached -- '));
      final rows = await repo.status();
      expect(
        rows.where((r) => r.section == Section.staged).map((r) => r.path),
        unorderedEquals(['my notes.txt', 'ærø/blåbær.txt']),
      );
      expect(await File('${temp.path}/ærø/blåbær.txt').exists(), isTrue);
    });

    test('a batch with a nested repository is retried with -f, and both leave the index', () async {
      final temp = await TempRepo.make();
      await temp.write('plain.txt', 'p\n');
      final inner = await TempRepo.nested(temp, 'inner');
      await inner.write('a.txt', 'one');
      await inner.git(['add', '-A']);
      await inner.git(['commit', '-qm', 'one']);
      await temp.git(['add', 'plain.txt', 'inner']);
      await temp.git(['commit', '-qm', 'add inner']);
      // The staged gitlink now differs from HEAD and from the working tree.
      await inner.write('a.txt', 'two');
      await inner.git(['add', '-A']);
      await inner.git(['commit', '-qm', 'two']);
      await temp.git(['add', 'inner']);

      final repo = await Repo.open(temp.path);
      await repo.untrack(['plain.txt', 'inner']);
      expect(repo.lastCommand, contains('-f'));
      final index = (await temp.git(['ls-files', '--stage'])).stdout.toString();
      expect(index, isNot(contains('plain.txt')));
      expect(index, isNot(contains('inner')));
      expect(await Directory('${temp.path}/inner/.git').exists(), isTrue);
    });

    test('checkIgnoreAll answers every path from one process, keyed as asked', () async {
      final temp = await TempRepo.make();
      await temp.write('.gitignore', 'build/\n*.log\n');
      await temp.write('run.log', 'x\n');
      await temp.write('logs dir/åpen.log', 'x\n');
      await temp.write('keep.txt', 'x\n');
      await temp.write('cache/a.bin', 'x\n');
      await temp.write('build/out.txt', 'x\n');
      final repo = await Repo.open(temp.path);
      final found = await repo.checkIgnoreAll(
        ['run.log', 'logs dir/åpen.log', 'keep.txt', 'cache/', 'build/'],
      );
      expect(repo.lastCommand, contains('--stdin'));
      expect(found.keys, unorderedEquals(['run.log', 'logs dir/åpen.log', 'build/']));
      expect(found['run.log']!.line, 2);
      expect(found['logs dir/åpen.log']!.pattern, '*.log');
      // The trailing slash is stripped before asking, and the answer is keyed
      // by the path as it was given.
      expect(found['build/']!.pattern, 'build/');
    });

    test('checkIgnoreAll reads a source that starts with a drive letter', () async {
      final temp = await TempRepo.make();
      final excludes = '${temp.path}/excludes.txt';
      await temp.write('excludes.txt', '*.tmp\n');
      await temp.git(['config', 'core.excludesFile', excludes]);
      await temp.write('scratch.tmp', 'x\n');
      final repo = await Repo.open(temp.path);
      final found = await repo.checkIgnoreAll(['scratch.tmp']);
      expect(found['scratch.tmp']!.source.toLowerCase(), excludes.toLowerCase());
      expect(found['scratch.tmp']!.line, 1);
      expect(found['scratch.tmp']!.pattern, '*.tmp');
    });

    test('appendIgnoreLines reads and writes once, dropping duplicates, keeping CRLF', () async {
      final temp = await TempRepo.make();
      await temp.write('.gitignore', 'build/\r\n*.log\r\n');
      final repo = await Repo.open(temp.path);
      final answers = await repo.appendIgnoreLines(
        '${temp.path}/.gitignore',
        ['/a.txt', '*.log', '/b.txt', '/a.txt'],
      );
      expect(answers, [
        IgnoreAppend.added,
        IgnoreAppend.duplicate,
        IgnoreAppend.added,
        IgnoreAppend.duplicate,
      ]);
      final text = await File('${temp.path}/.gitignore').readAsString();
      expect(text, 'build/\r\n*.log\r\n/a.txt\r\n/b.txt\r\n');
    });
  });

  group('IgnoreMatch.parseZ', () {
    test('reads NUL records, with a C:/ source, and drops the non-matching ones', () {
      const raw = 'C:/Users/me/.config/git/ignore\u00003\u0000*.log\u0000run.log\u0000'
          '\u0000\u0000\u0000keep.txt\u0000'
          '.gitignore\u00001\u0000build/\u0000build\u0000';
      final found = IgnoreMatch.parseZ(raw);
      expect(found, hasLength(2));
      expect(found.first.source, 'C:/Users/me/.config/git/ignore');
      expect(found.first.line, 3);
      expect(found.first.pattern, '*.log');
      expect(found.first.path, 'run.log');
      expect(found.last.path, 'build');
    });

    test('an empty pattern is not a rule', () {
      const raw = '.gitignore\u000012\u0000\u0000es/inner\u0000';
      expect(IgnoreMatch.parseZ(raw), isEmpty);
    });

    test('empty output is no match', () {
      expect(IgnoreMatch.parseZ(''), isEmpty);
    });
  });

  group('Repo.argumentBatches', () {
    test('a short list is one batch', () {
      expect(Repo.argumentBatches(['a', 'b', 'c']), [
        ['a', 'b', 'c'],
      ]);
    });

    test('a long list is split under the limit, keeping the order', () {
      final paths = [for (var i = 0; i < 1000; i++) 'folder/sub/file_$i.dart'];
      final batches = Repo.argumentBatches(paths, limit: 3000);
      expect(batches.length, greaterThan(1));
      expect(batches.expand((batch) => batch), paths);
      for (final batch in batches) {
        expect(batch.fold<int>(0, (sum, path) => sum + path.length + 3), lessThanOrEqualTo(3000));
      }
    });

    test('nothing is no batch', () {
      expect(Repo.argumentBatches(const []), isEmpty);
    });
  });
}
