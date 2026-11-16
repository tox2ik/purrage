import 'package:flutter_test/flutter_test.dart';
import 'package:glustered/state/ignore_rules.dart';

void main() {
  group('IgnoreRules.pattern', () {
    test('file scope at the root is repo-relative and anchored', () {
      expect(
        IgnoreRules.pattern(scope: IgnoreScope.file, targetDir: '', path: 'lib/a.dart'),
        '/lib/a.dart',
      );
    });

    test('file scope in a nested file drops the folder', () {
      expect(
        IgnoreRules.pattern(scope: IgnoreScope.file, targetDir: 'lib', path: 'lib/a.dart'),
        '/a.dart',
      );
    });

    test('extension scope is the same wherever it lives', () {
      expect(
        IgnoreRules.pattern(scope: IgnoreScope.extension, targetDir: '', path: 'a/b/log.txt'),
        '*.txt',
      );
      expect(
        IgnoreRules.pattern(scope: IgnoreScope.extension, targetDir: 'a/b', path: 'a/b/log.txt'),
        '*.txt',
      );
    });

    test('extension scope on a file without one makes no rule', () {
      expect(IgnoreRules.pattern(scope: IgnoreScope.extension, targetDir: '', path: 'Makefile'), isNull);
      expect(IgnoreRules.pattern(scope: IgnoreScope.extension, targetDir: '', path: 'a/.env'), isNull);
    });

    test('folder scope points at the folder, relative to the target', () {
      expect(
        IgnoreRules.pattern(scope: IgnoreScope.folder, targetDir: '', path: 'build/out/x.o'),
        '/build/out/',
      );
      expect(
        IgnoreRules.pattern(scope: IgnoreScope.folder, targetDir: 'build', path: 'build/out/x.o'),
        '/out/',
      );
    });

    test('a folder at the repo root makes no folder rule from the root', () {
      expect(IgnoreRules.pattern(scope: IgnoreScope.folder, targetDir: '', path: 'x.o'), isNull);
    });

    test('a folder row ignores itself', () {
      expect(IgnoreRules.pattern(scope: IgnoreScope.folder, targetDir: '', path: 'build/'), '/build/');
    });

    test('glob characters in a real name are escaped', () {
      expect(
        IgnoreRules.pattern(scope: IgnoreScope.file, targetDir: '', path: 'a[1]*.txt'),
        r'/a\[1\]\*.txt',
      );
    });

    test('a leading ! or # is escaped', () {
      expect(IgnoreRules.pattern(scope: IgnoreScope.file, targetDir: '', path: '!important.txt'),
          r'/\!important.txt');
      expect(IgnoreRules.pattern(scope: IgnoreScope.file, targetDir: '', path: '#tag.md'),
          r'/\#tag.md');
    });

    test('trailing spaces are escaped', () {
      expect(IgnoreRules.pattern(scope: IgnoreScope.file, targetDir: '', path: 'odd '),
          r'/odd\ ');
    });
  });

  group('IgnoreRules.targets', () {
    const repo = 'C:/work/repo';

    test('the folder comes first, then root, then the uncommitted ones', () {
      final targets = IgnoreRules.targets(
        repoPath: repo,
        gitignoreFiles: ['lib/.gitignore'],
        localExclude: 'C:/work/repo/.git/info/exclude',
        globalIgnore: 'C:/Users/me/.config/git/ignore',
        path: 'lib/generated/a.g.dart',
      );
      expect(targets.map((t) => t.kind), [
        IgnoreTargetKind.folderGitignore,
        IgnoreTargetKind.rootGitignore,
        IgnoreTargetKind.localExclude,
        IgnoreTargetKind.globalIgnore,
      ]);
      expect(targets.first.path, '$repo/lib/generated/.gitignore');
      expect(targets.first.dir, 'lib/generated');
      expect(targets.first.exists, isFalse);
    });

    test('at the root only the root file is committed', () {
      final targets = IgnoreRules.targets(
        repoPath: repo,
        gitignoreFiles: ['.gitignore'],
        localExclude: '$repo/.git/info/exclude',
        globalIgnore: 'g',
        path: 'notes.md',
      );
      expect(targets, hasLength(3));
      expect(targets.first.path, '$repo/.gitignore');
      expect(targets.first.exists, isTrue);
      expect(targets.first.isCommitted, isTrue);
    });
  });
}
