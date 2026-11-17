---
id: task-14
title: Move the work out of ShellState into a Workspace
status: Done
assignee: []
created_date: '2026-11-17'
labels:
  - refactor
  - tests
dependencies: []
priority: high
---

## Description

**Merge 3 of 21** · stack A · branch `PR-workspace-out-of-shell` · stacked on `PR-process-env-seams`

`lib/ui/shell.dart` is 730 lines, and most of it is work, not presentation:
`openRepository` (new `Repo`, `Changes`, ignore pane, rescan, console rows), `reloadAll`,
`report`/`say`, the ignore flows, `newIgnoreHere`, the editor opening, and the 250 ms ignore probe.
CLAUDE.md says that work belongs in a `ChangeNotifier` under `lib/state/` that tests drive without
widgets. Today it can only be reached through `testWidgets`, which cannot touch git. That is the
largest block of untestable code standing between the suite and 100% coverage.

Ops has the same split: `lib/tasks/workspace.dart` / `lib/state/session.dart` hold the work, and
`shell.dart` holds keys and layout.

- `lib/state/workspace.dart`: `Workspace extends ChangeNotifier` owns `repo`, `changes`,
  `ignorePane`, `browser`, `console`, `notices`, `editors`, `prefs`. It has
  `open(path)`, `reloadAll()`, `track()`, `untrack()`, `ignoreQuick()`,
  `ignore(choice)`, `commit(summary)`, `openFocused()`, `newIgnoreHere()`, `say()`, `report()`.
  A factory function opens a `GitRepo` (real `Repo.open` in the app, FakeRepo in tests).
- The ignore dialog stays in the UI: the shell asks `workspace.ignoreTargets()`, shows the dialog
  and passes the choice in.
- `ShellState` keeps the focus nodes, controllers, `onKey` and `build`. `ModeRail` moves to
  `lib/ui/mode_rail.dart`, as in Ops.
- `Shell(seeded:)` becomes `Shell(workspace:)`.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `ShellState` has no git, file or console logic, only calls on `Workspace`
- [x] #2 `test/workspace_test.dart` covers open (success, failure, seeded), reload, each action's report/say path, newIgnoreHere, with FakeRepo
- [x] #3 `shell.dart` under 300 lines; every `build` under 50 lines
<!-- AC:END -->

## Notes

- `lib/state/workspace.dart` (the API is listed in its class doc). `Workspace(repo:, opener:)`;
  no `opener` means a seeded session that Browse cannot switch. `start()` once, `idle()`,
  `dispose()`. `ignoreQuestion()` + `ignore(scope:, target:, stopTracking:)` split the dialog
  flow so the dialog stays in the UI. Every action reports through `say`/`report`, never throws
  for a git or file failure.
- `Shell(workspace:)` owns and disposes the workspace; `main.dart` builds it once with
  `opener: Repo.open`. `shell.dart` is 238 lines; `Mode` and `ModeRail` are in
  `lib/ui/mode_rail.dart` (re-exported from `shell.dart`), with `Mode.digit` for `Alt+<n>`.
- Tests: `test/support/fake_workspace.dart` (`fakeWorkspace`, `MemoryPrefs`) builds a workspace
  with no git, file or process; `FakeRepo` gained `failures`, `calls`, `commits`, `ignored`.
- AC #3 read as "in `shell.dart`"; the builds over 50 lines elsewhere are task-21's.
- Open for the user: `CLAUDE.md` "Running tests" still says `Shell(repo: …, seeded: changes)`;
  it is now `Shell(workspace: fakeWorkspace(repo, changes: changes))`. Not edited here.
- `BrowseView` still probes the real drives in widget tests (`RepoBrowser.drives()`); task-9 or
  task-21 can pass the workspace's lister.
