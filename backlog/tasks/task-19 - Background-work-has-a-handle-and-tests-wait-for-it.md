---
id: task-19
title: Background work has a handle, and tests wait for it
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - bug
  - tests
dependencies: []
priority: high
---

## Description

Found while taking the coverage baseline: `test/changes_test.dart` "a rule that would never match is
refused, not written" fails on every run. The test body passes, and the teardown fails:

```
PathAccessException: Deletion failed, path = '...\Temp\purrage_8f919bce'
(OS Error: The process cannot access the file because it is being used by another process, errno = 32)
```

Cause: `Changes.load()` ends with `unawaited(_scanNested(_rows))`, which runs `git ls-files -s -z` in
the repository (`lib/state/changes.dart:148`, `Repo.gitlinks`). The refusal path does no git work of
its own, so the test returns while that git process still has the temp folder as its working
directory. Windows will not delete a directory that is a process's cwd. The folder stays in `%TEMP%`.
The project rule says it must not: two were left after two runs.

The same pattern is elsewhere: `ShellState.initState` starts `browser.scan()` and `prefs.load()`
without awaiting, `openRepository` starts a rescan, and `onChangesChanged` starts a timer.

Fix:

- `Changes` keeps the running probe (`Future<void>? _nestedScan`) and exposes `Future<void> idle()`,
  which completes when every background job it started is done. `dispose()` stops further probes.
  The same goes for `RepoBrowser` (`idle()`, and cancel, see task-6) and `IgnorePaneState`.
- `TempRepo.make` registers its delete teardown, so it runs last. The tests that create a `Changes`
  call `addTearDown(changes.idle)`, which runs first.
- Port Ops' `test/flutter_test_config.dart` + `support/temp_dirs.dart`: one place that removes the
  temp folders of a test file, retrying a delete that fails with errno 32 a few times, and a check
  that the `purrage_*` count is the same before and after.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `test/changes_test.dart` passes 20 runs in a row
- [ ] #2 after `make test`, the number of `purrage_*` folders in `%TEMP%` is unchanged (the Makefile target checks and says so)
- [ ] #3 no `unawaited(...)` in `lib/` without a handle that a test or `dispose` can wait on
<!-- AC:END -->
