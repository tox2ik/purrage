import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/browser.dart';
import 'package:purrage/state/editors.dart';
import 'package:purrage/state/git_repo.dart';
import 'package:purrage/state/hidden_write.dart';
import 'package:purrage/state/prefs.dart';
import 'package:purrage/state/repo.dart';
import 'package:purrage/state/system.dart';

import 'support/fake_system.dart';
import 'support/temp_dirs.dart';
import 'support/temp_repo.dart';

/// `attrib` output for [path] with [flags], in its fixed-width form.
ProcessOutput attribOut(String path, String flags) =>
    ProcessOutput(0, stdout: '${flags.padRight(19)}$path\r\n');

/// An `attrib` that reports [before] until a `-H -S` call succeeds, then
/// [after]; `+` calls answer [restoreOk].
FakeRunner attribMachine({
  required String path,
  String before = 'A  H',
  String after = 'A',
  bool clearOk = true,
  bool restoreOk = true,
}) {
  var cleared = false;
  return FakeRunner((call) {
    if (call.args.length == 1) return attribOut(path, cleared ? after : before);
    if (call.args.first == '-H') {
      cleared = clearOk;
      return ProcessOutput(clearOk ? 0 : 1);
    }
    return ProcessOutput(restoreOk ? 0 : 1);
  });
}

Matcher gitMessage(String text) =>
    throwsA(isA<GitException>().having((e) => e.message, 'message', contains(text)));

void main() {
  const file = r'C:\repo\.gitignore';

  group('HiddenWrite.clearHiddenAndSystem', () {
    test('clears H, and the returned call sets exactly H again', () async {
      final runner = attribMachine(path: file);
      final restore = await HiddenWrite(runner: runner).clearHiddenAndSystem(file);
      await restore();
      expect(runner.calls.map((call) => call.line), [
        'attrib $file',
        'attrib -H -S $file',
        'attrib $file',
        'attrib +H $file',
      ]);
    });

    test('a file that is neither Hidden nor System is refused with the reason', () {
      final runner = attribMachine(path: file, before: 'A');
      expect(HiddenWrite(runner: runner).clearHiddenAndSystem(file), gitMessage('not Hidden or System'));
    });

    test('a failing attrib -H -S names the manual command', () {
      final runner = attribMachine(path: file, clearOk: false);
      expect(HiddenWrite(runner: runner).clearHiddenAndSystem(file), gitMessage('`attrib -H -S` failed'));
    });

    test('still Hidden after attrib -H -S is said', () {
      final runner = attribMachine(path: file, after: 'A  H');
      expect(HiddenWrite(runner: runner).clearHiddenAndSystem(file), gitMessage('still Hidden or System'));
    });

    test('a restore that fails names both flags and the command', () async {
      final runner = attribMachine(path: file, before: 'A SH', restoreOk: false);
      final restore = await HiddenWrite(runner: runner).clearHiddenAndSystem(file);
      expect(restore(), gitMessage('could not set H and S again'));
    });

    test('attributes reads nothing from a failing attrib', () async {
      final runner = FakeRunner((_) => const ProcessOutput(1));
      expect(await HiddenWrite(runner: runner).attributes(file), isEmpty);
    });

    test('off Windows an access-denied write is rethrown, no attrib runs', () async {
      final runner = FakeRunner();
      final dir = keepForCleanup(await Directory.systemTemp.createTemp('purrage_'));
      addTearDown(() => deleteWithRetry(dir));
      // A directory cannot be written as a file: the write throws, and the
      // non-Windows path must not try the repair.
      final writer = HiddenWrite(runner: runner, isWindows: false);
      await expectLater(writer.write(File(dir.path), 'x'), throwsA(isA<FileSystemException>()));
      expect(runner.calls, isEmpty);
    });
  });

  group('where', () {
    test('.exe first, then .cmd/.bat, then anything', () {
      expect(
        Editors.pickFromWhere('C:\\a\\code\r\nC:\\b\\code.cmd\r\nC:\\c\\code.exe\r\n'),
        'C:\\c\\code.exe',
      );
      expect(Editors.pickFromWhere('C:\\a\\code\r\nC:\\b\\code.bat\r\n'), 'C:\\b\\code.bat');
      expect(Editors.pickFromWhere('C:\\a\\code\r\n'), 'C:\\a\\code');
      expect(Editors.pickFromWhere('\r\n'), isNull);
    });

    test('a failing or missing where answers null', () async {
      expect(await Editors.whichWith(FakeRunner((_) => const ProcessOutput(1)))('code'), isNull);
      expect(await Editors.whichWith(FakeRunner((_) => null))('code'), isNull);
      final found = FakeRunner((_) => const ProcessOutput(0, stdout: 'C:\\x\\code.exe\r\n'));
      expect(await Editors.whichWith(found)('code'), 'C:\\x\\code.exe');
      expect(found.calls.single.line, 'where code');
    });

    test('git var GIT_EDITOR: the text, or null for blank, failure or no git', () async {
      final ok = FakeRunner((_) => const ProcessOutput(0, stdout: 'nvim\n'));
      expect(await Editors.gitEditorWith(ok)(), 'nvim');
      expect(await Editors.gitEditorWith(FakeRunner((_) => const ProcessOutput(0)))(), isNull);
      expect(await Editors.gitEditorWith(FakeRunner((_) => const ProcessOutput(1)))(), isNull);
      expect(await Editors.gitEditorWith(FakeRunner((_) => null))(), isNull);
    });
  });

  group('nvim-qt probe', () {
    test('lists neovim-qt* under both Program Files, skipping unreadable ones', () async {
      final lister = FakeLister(dirs: {
        'C:/PF': [
          const DirEntry(r'C:\PF\Neovim-Qt 0.2', isDirectory: true),
          const DirEntry(r'C:\PF\Other', isDirectory: true),
        ],
      });
      final env = Env(const {'ProgramFiles': r'C:\PF', 'ProgramFiles(x86)': r'C:\PF86'});
      expect(await Editors.nvimQtCandidatesIn(env, lister), ['C:/PF/Neovim-Qt 0.2/bin/nvim-qt.exe']);
      expect(lister.listed, ['C:/PF', 'C:/PF86']);
    });

    test('no Program Files variables, no candidates', () async {
      expect(await Editors.nvimQtCandidatesIn(const Env({}), FakeLister()), isEmpty);
    });
  });

  group('Editors.open', () {
    Editors with1(String command, FakeRunner runner) => Editors(
          which: (exe) async => exe == 'code' ? command : null,
          exists: (_) => false,
          gitEditor: () async => null,
          nvimQtCandidates: () async => const [],
          env: const Env({}),
          runner: runner,
        );

    test('a .cmd shim starts through cmd /c start, detached', () async {
      final runner = FakeRunner();
      await with1(r'C:\bin\code.cmd', runner).open(file: 'a.txt');
      expect(runner.calls.single.detached, isTrue);
      expect(runner.calls.single.line, r'cmd /c start  C:\bin\code.cmd a.txt');
    });

    test('an exe starts directly; a start failure is an EditorException', () async {
      final runner = FakeRunner((_) => null);
      await expectLater(
        with1(r'C:\bin\code.exe', runner).open(file: 'a.txt'),
        throwsA(isA<EditorException>()),
      );
      expect(runner.calls.single.exe, r'C:\bin\code.exe');
    });
  });

  group('environment fallbacks', () {
    test('prefs live in APPDATA, else the home folder', () {
      expect(Prefs.defaultDirectory(const Env({'APPDATA': r'C:\AD', 'USERPROFILE': r'C:\U'})), 'C:/AD/Purrage');
      expect(Prefs.defaultDirectory(const Env({'APPDATA': ' ', 'USERPROFILE': r'C:\U'})), 'C:/U/Purrage');
      expect(Prefs.defaultDirectory(const Env({'HOME': '/home/u'})), '/home/u/Purrage');
      expect(Prefs(env: const Env({'APPDATA': 'C:/AD'})).path, 'C:/AD/Purrage/prefs.json');
    });

    test('the global ignore file: core.excludesFile, XDG, then home', () {
      const env = Env({'USERPROFILE': r'C:\U'});
      expect(Repo.globalIgnoreFrom('~/my.ignore', env), 'C:/U/my.ignore');
      expect(Repo.globalIgnoreFrom(r'D:\x\ignore', env), 'D:/x/ignore');
      expect(Repo.globalIgnoreFrom('', env), 'C:/U/.config/git/ignore');
      expect(
        Repo.globalIgnoreFrom('', const Env({'XDG_CONFIG_HOME': '/xdg', 'HOME': '/h'})),
        '/xdg/git/ignore',
      );
      expect(Repo.globalIgnoreFrom('', const Env({})), '/.config/git/ignore');
    });
  });

  group('drives and the walk', () {
    test('the drive probe asks A: to Z: and keeps the ones that exist', () async {
      final lister = FakeLister(existing: {'C:/', 'H:/'});
      expect(await RepoBrowser.drives(lister: lister, env: const Env({})), ['C:/', 'H:/']);
    });

    test('off Windows there are no drives', () async {
      final lister = FakeLister(existing: {'C:/'});
      expect(await RepoBrowser.drives(lister: lister, env: const Env({}, isWindows: false)), isEmpty);
    });

    test('the walk skips links, skip-list folders and unreadable ones', () async {
      final lister = FakeLister(
        dirs: {
          'C:/root': [
            const DirEntry(r'C:\root\app', isDirectory: true),
            const DirEntry(r'C:\root\link', isDirectory: true, isLink: true),
            const DirEntry(r'C:\root\node_modules', isDirectory: true),
            const DirEntry(r'C:\root\locked', isDirectory: true),
            const DirEntry(r'C:\root\file.txt', isDirectory: false),
          ],
        },
        existing: {'C:/root/app/.git', 'C:/root/link/.git', 'C:/root/node_modules/.git'},
      );
      final browser = RepoBrowser(startDirectory: 'C:/root', lister: lister, env: const Env({}));
      addTearDown(browser.dispose);
      await browser.scan();
      expect(browser.repos.map((repo) => repo.toLowerCase()), ['c:/root/app']);
      expect(lister.listed, ['C:/root', 'C:/root/locked']);
    }, skip: !Platform.isWindows ? 'Windows paths' : false);
  });

  group('the real runner', () {
    test('stdin is written and stdout read back', () async {
      const runner = SystemProcessRunner();
      final out = await runner.run('git', ['hash-object', '--stdin'], stdin: 'x');
      expect(out.ok, isTrue);
      expect(out.stdout.trim(), matches(RegExp(r'^[0-9a-f]{40}$')));
      final other = await runner.run('git', ['hash-object', '--stdin'], stdin: 'y');
      expect(other.stdout, isNot(out.stdout), reason: 'the hash is of what stdin carried');
    });

    test('Env.system reads the process environment', () {
      expect(Env.system().values, same(Platform.environment));
      expect(const Env({'A': ' '})['A'], isNull);
    });
  });

  group('Repo with a fake runner', () {
    test('a failing git status is a GitException with git\'s words', () async {
      final temp = await TempRepo.make();
      final runner = FakeRunner((_) => const ProcessOutput(128, stderr: 'fatal: index file corrupt'));
      final repo = await Repo.open(temp.path, runner: runner, env: const Env({}));
      await expectLater(repo.status(), gitMessage('index file corrupt'));
      expect(runner.calls.single.args, contains('--porcelain=v1'));
      expect(runner.calls.single.cwd, repo.path);
    });
  });
}
