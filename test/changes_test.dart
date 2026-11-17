import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/ignore_rules.dart';

import 'support/temp_repo.dart';

void main() {
  group('Changes ignore actions', () {
    test('the quick ignore writes the literal path into the root .gitignore', () async {
      final temp = await TempRepo.make();
      await temp.write('notes.md', 'x\n');
      final changes = await temp.changes();
      await changes.load();
      expect(changes.visible.single.path, 'notes.md');

      final problem = (await changes.ignoreQuick()).problem;
      expect(problem, isNull, reason: problem);

      final text = await File('${temp.path}/.gitignore').readAsString();
      expect(text, contains('/notes.md'));
      expect(changes.visible.map((row) => row.path), isNot(contains('notes.md')));
    });

    test('the dialog target writes its rule and the path is gone from the list', () async {
      final temp = await TempRepo.make();
      await temp.write('lib/generated/a.g.dart', 'x\n');
      final changes = await temp.changes();
      await changes.load();
      expect(changes.visible.single.path, 'lib/generated/a.g.dart');

      final targets = await changes.ignoreTargets();
      final nested = targets.firstWhere((t) => t.kind == IgnoreTargetKind.folderGitignore);
      expect(nested.path, endsWith('lib/generated/.gitignore'));

      final problem = (await changes.ignoreSelected(scope: IgnoreScope.file, target: nested)).problem;
      expect(problem, isNull, reason: problem);

      final text = await File(nested.path).readAsString();
      expect(text, contains('/a.g.dart'));
      expect(changes.visible.map((row) => row.path), isNot(contains('lib/generated/a.g.dart')));
    });

    test('a rule that would never match is refused, not written', () async {
      final temp = await TempRepo.make();
      await temp.write('Makefile', 'x\n');
      final changes = await temp.changes();
      await changes.load();
      final root = changes.rootTarget;
      final result = await changes.ignoreSelected(scope: IgnoreScope.extension, target: root);
      expect(result.ok, isFalse);
      final text = await File('${temp.path}/.gitignore').readAsString();
      expect(text, isNot(contains('*.')));
    });

    test('every target path is shown with forward slashes', () async {
      final temp = await TempRepo.make();
      await temp.write('notes.md', 'x\n');
      final changes = await temp.changes();
      await changes.load();
      final targets = await changes.ignoreTargets();
      expect(targets, isNotEmpty);
      for (final target in targets) {
        expect(target.path.contains(r'\'), isFalse, reason: target.path);
      }
    });
  });
}
