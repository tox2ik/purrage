import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/git_repo.dart';
import 'package:purrage/state/ignore_files.dart';
import 'package:purrage/state/status.dart';
import 'package:purrage/ui/ignore_pane.dart';

/// An in-memory repository: no git, no files, no clock.
class IgnoreFakeRepo implements GitRepo {
  IgnoreFakeRepo({
    this.ignoreFiles = const ['.gitignore'],
    this.contents = const {},
    this.matches = const {},
    this.failLoad = false,
  });

  final List<String> ignoreFiles;
  final Map<String, String> contents;
  final Map<String, IgnoreMatch?> matches;
  final bool failLoad;

  @override
  String get path => 'C:/repo';

  @override
  Future<List<String>> gitignoreFiles() async {
    if (failLoad) throw GitException('git ls-files failed');
    return ignoreFiles;
  }

  @override
  Future<IgnoreMatch?> checkIgnore(String path) async => matches[path];

  @override
  Future<String> readTextFile(String absolutePath) async => contents[absolutePath] ?? '';

  @override
  Future<List<StatusRow>> status() async => const [];

  @override
  Future<void> track(Iterable<String> paths) async {}

  @override
  Future<void> untrack(String path) async {}

  @override
  Future<void> commit(String summary) async {}

  @override
  Future<String> localExcludePath() async => 'C:/repo/.git/info/exclude';

  @override
  Future<String> globalIgnorePath() async => 'C:/home/.config/git/ignore';

  @override
  Future<IgnoreAppend> appendIgnoreLine(String absolutePath, String pattern) async =>
      IgnoreAppend.added;

  @override
  Future<void> createIgnoreFile(String absolutePath) async {}

}

IgnoreFakeRepo fixture() => IgnoreFakeRepo(
      ignoreFiles: const ['lib/generated/.gitignore', '.gitignore'],
      contents: const {
        'C:/repo/.gitignore': 'build/\r\n*.log\r\n',
        'C:/repo/lib/generated/.gitignore': '# generated\n*.g.dart\n',
      },
      matches: const {
        'lib/generated/a.g.dart': IgnoreMatch(
          source: 'C:/repo/lib/generated/.gitignore',
          line: 2,
          pattern: '*.g.dart',
          path: 'lib/generated/a.g.dart',
        ),
      },
    );

Future<IgnorePaneState> opened(IgnoreFakeRepo repo) async {
  final state = IgnorePaneState(repo);
  await state.load();
  return state;
}

void main() {
  group('IgnorePaneState', () {
    test('root first, nested sorted by path, lines read', () async {
      final state = await opened(fixture());

      expect(state.files.map((file) => file.path), ['.gitignore', 'lib/generated/.gitignore']);
      expect(state.files.first.root, isTrue);
      expect(state.files.last.root, isFalse);
      expect(state.files.first.lines, ['build/', '*.log']);
      expect(state.files.last.lines, ['# generated', '*.g.dart']);
      expect(state.selected?.path, '.gitignore');
      expect(state.selectedText, 'build/\n*.log');
    });

    test('a nested file is selected by path', () async {
      final state = await opened(fixture());

      state.select('lib/generated/.gitignore');

      expect(state.selected?.path, 'lib/generated/.gitignore');
      expect(state.selectedText, '# generated\n*.g.dart');
    });

    test('the match line resolves only in the file that owns the rule', () async {
      final state = await opened(fixture());
      await state.focusPath('lib/generated/a.g.dart');

      expect(state.match?.pattern, '*.g.dart');
      expect(state.matchLine, isNull, reason: 'root file is selected');

      state.select('lib/generated/.gitignore');
      expect(state.matchLine, 2);

      state.select('.gitignore');
      expect(state.matchLine, isNull, reason: 'the rule is not in this file');
    });

    test('a relative match source is normalised too', () async {
      final repo = IgnoreFakeRepo(
        contents: const {'C:/repo/.gitignore': '*.log\n'},
        matches: const {
          'debug.log': IgnoreMatch(
            source: r'.gitignore',
            line: 1,
            pattern: '*.log',
            path: 'debug.log',
          ),
        },
      );
      final state = await opened(repo);
      await state.focusPath('debug.log');

      expect(state.matchLine, 1);
    });

    test('load failure is stored in error, not thrown', () async {
      final state = await opened(IgnoreFakeRepo(failLoad: true));

      expect(state.error, 'git ls-files failed');
      expect(state.files, isEmpty);
      expect(state.selected, isNull);
    });
  });

  group('IgnorePane', () {
    Future<IgnorePaneState> pumpPane(
      WidgetTester tester,
      IgnoreFakeRepo repo, {
      VoidCallback? onOpen,
      VoidCallback? onNew,
    }) async {
      final state = await opened(repo);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: IgnorePane(
              state: state,
              onOpenInEditor: onOpen ?? () {},
              onNewHere: onNew ?? () {},
            ),
          ),
        ),
      );
      await tester.pump();
      return state;
    }

    testWidgets('the rail names .gitignore and the nested folder', (tester) async {
      await pumpPane(tester, fixture());

      expect(find.text('.gitignore'), findsWidgets);
      expect(find.text('lib/generated'), findsOneWidget);
      expect(find.text('build/'), findsOneWidget);
    });

    testWidgets('the matched line is highlighted, others are not', (tester) async {
      final state = await pumpPane(tester, fixture());
      await state.focusPath('lib/generated/a.g.dart');
      state.select('lib/generated/.gitignore');
      await tester.pump();

      final matched = find.byKey(const ValueKey('ignore-matched-line'));
      expect(matched, findsOneWidget);
      expect(
        find.descendant(of: matched, matching: find.text('*.g.dart')),
        findsOneWidget,
      );
      expect(tester.widget<Container>(matched).color, isNotNull);
      expect(find.byKey(const ValueKey('ignore-line-1')), findsOneWidget);
      expect(find.text('line 2'), findsOneWidget);
    });

    testWidgets('no match says so', (tester) async {
      await pumpPane(tester, fixture());

      expect(find.text('no file matches'), findsOneWidget);
      expect(find.byKey(const ValueKey('ignore-matched-line')), findsNothing);
    });

    testWidgets('both buttons fire their callbacks', (tester) async {
      var opened = 0;
      var created = 0;
      await pumpPane(tester, fixture(), onOpen: () => opened++, onNew: () => created++);

      await tester.tap(find.text('Open in editor'));
      await tester.pump();
      await tester.tap(find.text('New here'));
      await tester.pump();

      expect(opened, 1);
      expect(created, 1);
    });
  });
}
