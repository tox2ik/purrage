## 1. Build

### 1.1 Groundwork (task-19, task-15, task-14)

- [ ] 1.1.1 `Changes.idle()`, `RepoBrowser.idle()`, `IgnorePaneState.idle()`; tests wait on them in teardown
- [ ] 1.1.2 `test/flutter_test_config.dart` + `test/support/temp_dirs.dart` (Ops pattern), delete retried on errno 32
- [ ] 1.1.3 `ProcessRunner`, `Env`, `DirectoryLister` seams with real defaults and test fakes
- [ ] 1.1.4 `FakeRepo`: per-call failure switches, held calls (Completer), call counters
- [ ] 1.1.5 `Workspace` extracted from `ShellState`; `Shell(workspace:)`

### 1.2 Coverage tooling (task-16)

- [ ] 1.2.1 `tool/coverage.dart`: all lib files, lcov parse, ignore markers with reasons, terse output, `--min`
- [ ] 1.2.2 `make coverage` (`MIN ?= 100`), `coverage/` in `.gitignore`
- [ ] 1.2.3 tests for `tool/coverage.dart` itself (fixture lcov strings)

### 1.3 Unit and widget tests to 100% (task-16)

- [ ] 1.3.1 `failure.dart`, `console.dart`, `notices.dart`, `diagnostics.dart`
- [ ] 1.3.2 `changes.dart` (every action, success, partial and failure)
- [ ] 1.3.3 `workspace.dart` (everything moved out of the shell)
- [ ] 1.3.4 `browser.dart` with the lister fake
- [ ] 1.3.5 `editors.dart`, `repo.dart` fallbacks and attrib branches with the runner fake
- [ ] 1.3.6 widgets: `notice_bar`, `filter_field`, `browse_view`, `settings_view`, `shell` keys, `PurrageApp`
- [ ] 1.3.7 `make coverage` passes at `MIN=100`

### 1.4 Integration tests (task-17)

- [ ] 1.4.1 `integration_test` dev dependency, `integration_test/support/` (`until`, app launcher, temp repos)
- [ ] 1.4.2 `make itest` with the leak check
- [ ] 1.4.3 flows 1–10 from the design, one test each

### 1.5 Docs

- [ ] 1.5.1 CLAUDE.md "Running tests": the three layers, `make coverage`, `make itest`
- [ ] 1.5.2 PLAN.md "Tests" section to match

## 2. Verify

- [ ] 2.1 `make test` is green 5 runs in a row, and the `purrage_*` count in `%TEMP%` is unchanged
- [ ] 2.2 `make coverage` prints nothing and exits 0; the exclusions it lists are few and each has a reason
- [ ] 2.3 `make itest` is green on the user's machine in under 3 minutes and leaks nothing
- [ ] 2.4 break one thing on purpose (e.g. drop the CRLF handling in `appendIgnoreLine`) and see both a unit test and an integration test fail
