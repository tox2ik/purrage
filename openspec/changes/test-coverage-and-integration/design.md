# Design

## Three layers, and which one may touch what

| layer | where | clock | git / files | runs in |
|---|---|---|---|---|
| unit | `test/*_test.dart`, plain `test()` | real | fixtures, fakes; `makeRepo()` for `Repo` | `make test` |
| widget | `test/*_test.dart`, `testWidgets` | fake | never: `FakeRepo`, seeded `Workspace` | `make test` |
| integration | `integration_test/*_test.dart` | real (live binding) | real git, real temp repos | `make itest` |

The existing rule, "never drive git, sockets or file watchers from a widget test", stays as it is.
The integration binding (`IntegrationTestWidgetsFlutterBinding`) runs frames on the real clock, so
real I/O completes there. Waiting is done by pumping until a condition holds, with a deadline:

```dart
Future<void> until(WidgetTester t, bool Function() done, {Duration max = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(max);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('timed out');
    await t.pump(const Duration(milliseconds: 30));
  }
}
```

Never `pumpAndSettle`: the notice countdown and the ignore probe are timers.

## Coverage

### Tool

`flutter test --coverage` writes `coverage/lcov.info`, but only for libraries a test loaded. A file
no test imports (today `main.dart`) is missing, not at 0%. `tool/coverage.dart`:

1. Lists every `lib/**/*.dart`, so a missing file is reported as `   never lib/main.dart`.
2. Reads `lcov.info` (`SF:`, `DA:line,hits`) without the `coverage` package.
3. Drops lines inside `// coverage:ignore-start` … `-end`, lines with `// coverage:ignore-line`,
   and files with `// coverage:ignore-file`, and checks that each marker has a reason after it
   (`// coverage:ignore-line: GitDir throws only on a broken install`).
4. Prints, per the script output rules, one line per file under 100%, and the uncovered line ranges:
   ```
    missed lib/state/browser.dart 214-218, 301
   ignored lib/main.dart 12 (runApp entry point)
     never lib/ui/foo.dart
   ```
   No line for a covered file, no summary banner. Exit code 1 below `MIN` (default 100).

Makefile:

```make
##@ checks
coverage: ## unit and widget tests with line coverage; lists files under MIN (100) percent
	& "$(FLUTTER)" test --coverage --timeout 22s
	& "$(DART)" run tool/coverage.dart --min $(MIN)
```

### Exclusion policy

Excluded with a reason, and nothing else:

- `main()` itself (process entry, zone setup). `PurrageApp` is tested through a widget test with an
  opener function passed in.
- Lines that exist only for the debugger or for a platform other than Windows, when the seam
  (task-15) cannot sensibly fake them.

Not excluded: `catch` branches, error messages, `dispose`. Those are what the fakes are for:
`FakeRepo` gains failure switches per call, and `ProcessRunner` and `Env` fakes come from task-15.

### Plan per file

| file | what is missing | how |
|---|---|---|
| `state/changes.dart` | untrack, ignore partial failures, commit via `_run`, `selectAll`, `toggleFocused`, `click` ctrl/shift, `_targetFor` | `FakeRepo` with failure switches; plain tests |
| `ui/shell.dart` | `openRepository`, `reloadAll`, `newIgnoreHere`, editor errors, key branches | most of it moves to `Workspace` (task-14), with plain tests; the remaining keys get widget tests per key |
| `state/browser.dart` | the walk, skip rules, AppData depth, the 20,000 stop, rescan folding | a `DirectoryLister` fake (task-15) with a tree in memory |
| `state/editors.dart` | `where` ordering, `GIT_EDITOR` resolution, env fallbacks, nvim-qt probe | `ProcessRunner` + `Env` fakes |
| `state/diagnostics.dart` | install, guard, record, enter/leave | plain tests with a `ConsoleLog`; restore the handlers in `tearDown` |
| `state/notices.dart`, `ui/notice_bar.dart` | countdown, hover pause and resume, dismiss | `fakeAsync` for the state; a widget test with `pump(duration)` for the bar |
| `state/failure.dart`, `state/console.dart` | `fromError` per exception type, `fromSkips`, limit trimming | plain tests |
| `ui/browse_view.dart`, `ui/settings_view.dart`, `ui/filter_field.dart` | buttons, drive picker, field keys | widget tests with fakes |
| `state/repo.dart` | status failure, attrib failure branches, `globalIgnorePath` fallbacks | `ProcessRunner`/`Env` fakes; the happy paths stay in the `makeRepo()` tests |
| `ui/theme.dart` | never called in tests | widget tests pump `MaterialApp(theme: buildTheme())`, one helper for all |
| `main.dart` | never loaded | `PurrageApp` widget test (open failure shows `_OpenError`, success shows `Shell`) |

## Integration tests

### Setup

- `pubspec.yaml` dev dependency: `integration_test: { sdk: flutter }`.
- `integration_test/support/` reuses `test/support/temp_repo.dart` (import by relative path)
  and the cleanup from task-19.
- Every test starts `PurrageApp(directory: repo.path, console: ConsoleLog())` with
  `tester.pumpWidget`, and drives it with `tester.sendKeyEvent` / `tester.tap`. Real keys, with
  `HardwareKeyboard` state, so Shift and Ctrl combinations go through the same path as for the user.
- Assertions check both sides: the screen (finders) and git (`repo.git(['status', '--porcelain'])`,
  `git log -1 --format=%s`, file contents, `attrib`).
- `make itest`:
  ```make
  itest: ## integration tests: the real app on Windows against temp repositories
  	& "$(FLUTTER)" test integration_test -d windows --timeout 60s
  ```
  The target also compares the `purrage_*` count in `%TEMP%` before and after, and says
  `   leaked <n> purrage_* folders` when it grew.

### The critical flows

Each flow is one `testWidgets` in a file named after the area:

1. **start** (`start_test.dart`): a repository with conflict, staged, changed and untracked
   files shows four sections with the right counts. A folder that is not a repository shows the
   open error. A non-ASCII path and a path with spaces show correctly.
2. **track and untrack** (`track_test.dart`): `space` on two highlighted rows stages exactly
   those (`git diff --cached --name-only`). The row's `Add` stages one. `u` unstages it, and the
   file stays on disk. Shift+Down ×2 then `a` stages three. A filtered list stages only what is
   visible and highlighted.
3. **quick ignore** (`ignore_test.dart`): `i` writes `/path` to the root `.gitignore` with CRLF
   kept, the row leaves, and `git check-ignore` agrees. A path that is already ignored by a parent
   rule gives a notice naming `.gitignore:<line>`, and the file is unchanged.
4. **ignore dialog**: `Shift+I` with *this extension* and *.gitignore in the file's folder* creates
   `sub/.gitignore` with the header and `*.log`. The new file appears as an untracked row, and the
   ignore pane lists it.
5. **hidden ignore file**: `attrib +H .gitignore`, then `i`. The rule is written and `H` is set
   again afterwards.
6. **commit** (`commit_test.dart`): stage, `c`, type, Enter. `git log -1` has the summary, the
   Staged section is gone, the field is empty. With nothing staged, the button is disabled and
   Enter does nothing.
7. **failure reporting** (`failure_test.dart`): with `.git/index.lock` present, `space` moves the
   row, then puts it back. The notice says why, and the Console (`Alt+4`) has the row with the
   exit code, the command and the cwd.
8. **reload**: a file created behind the app's back appears after `F5`, `r` and `Ctrl+R`, and
   not before. That is the "no polling" rule.
9. **browse** (`browse_test.dart`): a temp folder with two repositories and a `node_modules` holding
   a third. Browse lists two. Clicking the second loads its rows. `Alt+1` shows them, and the
   Console has `opening` and `opened`.
10. **nested repository**: an embedded repo shows the `git` chip. Untracking a gitlink runs with
    `-f`, and the console shows the command that actually ran.

### Time budget

The ten flows should finish in under 3 minutes on the user's machine. Each test has a 60 s
limit. Repositories are created with `core.fsmonitor=false`, so no daemon outlives a test.
