# Unit tests to 100% line coverage, integration tests for the critical flows

Tasks: task-16 (coverage), task-17 (integration). Prerequisites: task-14 (Workspace), task-15
(seams), task-19 (background work and temp folder cleanup).

## Why

Purrage changes files on disk and the git index for the user, and it does this on Windows, where
file attributes, locked folders, drive-letter paths and `.bat` shims all behave differently. Only
two layers of the suite can catch a regression today:

- **Fake-clock tests** (parsers, `Changes` with `FakeRepo`, widgets with `Shell(seeded:)`). They
  are fast, but they never see real git or the real file system.
- **Repo tests** (`makeRepo()`, real git in a plain `test()`). They test `Repo` one call at a time,
  never a whole user flow through the window.

Nothing tests what the user does: start the app on a folder, press keys, and see git's state change.
The coverage baseline also shows large untested areas. Most of them sit in code that the test
seams cannot reach: `ShellState`, `Diagnostics`, the browse walk, the editor detection, the
notice timing.

Baseline, 2026-11-17, `flutter test --coverage`, 105 tests:

| file | lines hit | |
|---|---|---|
| total | 1602 / 2511 | **63.8%** |
| `main.dart` | never loaded | 0% |
| `ui/theme.dart` | 0 / 25 | 0% |
| `state/diagnostics.dart` | 2 / 46 | 4% |
| `state/notices.dart` | 5 / 38 | 13% |
| `state/browser.dart` | 28 / 135 | 21% |
| `ui/notice_bar.dart` | 7 / 26 | 27% |
| `state/failure.dart` | 10 / 35 | 29% |
| `ui/browse_view.dart` | 49 / 106 | 46% |
| `ui/filter_field.dart` | 17 / 36 | 47% |
| `state/changes.dart` | 162 / 331 | 49% |
| `ui/shell.dart` | 185 / 347 | 53% |
| `state/editors.dart` | 80 / 148 | 54% |
| `ui/settings_view.dart` | 72 / 125 | 58% |
| `state/console.dart` | 11 / 16 | 69% |
| `state/repo.dart` | 109 / 139 | 78% |
| `ui/file_list.dart` | 159 / 200 | 80% |
| everything else | | 84–100% |

The same run had one failing test, a teardown that could not delete its temp repository (task-19).

## What changes

- A `make coverage` target and a small `tool/coverage.dart`, with no new package. It prints the
  files under the threshold one per line and fails the target below it. The threshold is 100% of
  the lines that are not excluded, and every exclusion carries its reason.
- Unit and widget tests per file, until the gate passes. Most of the new tests become possible
  after the Workspace extraction (task-14) and the process, environment and file seams (task-15).
- An `integration_test/` suite that starts the real app on Windows against throwaway
  repositories, presses the real keys, and checks the screen and git's own answer. It runs with
  `make itest`, locally, when asked. It does not run in `make test`.
- The test rules in `CLAUDE.md` and `PLAN.md` say which layer may touch git. Fake-clock widget
  tests still never do. Integration tests run on a real clock and do.

## What does not change

- `make test` stays the fast default and does not start the app.
- No CI. Everything runs locally on the user's Windows machine.
