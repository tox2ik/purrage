---
id: task-14
title: Move the work out of ShellState into a Workspace
status: To Do
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
- [ ] #1 `ShellState` has no git, file or console logic, only calls on `Workspace`
- [ ] #2 `test/workspace_test.dart` covers open (success, failure, seeded), reload, each action's report/say path, newIgnoreHere, with FakeRepo
- [ ] #3 `shell.dart` under 300 lines; every `build` under 50 lines
<!-- AC:END -->
