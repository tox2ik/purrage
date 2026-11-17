---
id: task-2
title: One git call per action
status: Done
assignee: []
created_date: '2026-11-17'
labels:
  - perf
dependencies:
  - task-1
priority: high
---

## Description

**Merge 8 of 21** · stack B · branch `PR-one-git-call` · stacked on `PR-time-the-actions`

The optimistic redraw is instant, but git behind it scales with the selection:

- `Changes.untrackSelected` runs `git rm --cached` once per row (`lib/state/changes.dart:333`).
  With 300 rows that is 300 processes, and the list is only confirmed when the last one ends.
- `Changes.ignoreSelected` runs `git check-ignore -v` once per row before it writes anything
  (`changes.dart:461`), then reads and rewrites the ignore file once per row
  (`Repo.appendIgnoreLine`), and with `stopTracking` runs another `git rm` per row.

Do instead:

- `GitRepo.untrack(Iterable<String>)`: one `git rm --cached -- a b c`. On the `-f` hint, retry
  the same batch with `-f` (the hint is per batch anyway). Split the arguments at about 30,000
  characters, the Windows command line limit.
- `GitRepo.checkIgnoreAll(paths)`: one `git check-ignore -v -n -z --stdin`, with the paths on
  stdin (no length limit). Parse the NUL records, still from the right for the drive letter, and
  keep the no-trailing-slash and empty-pattern rules.
- `GitRepo.appendIgnoreLines(file, patterns)`: one read and one write per target file, duplicates
  dropped in the same pass, line endings kept.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 untracking N rows starts one git process (or a few, for a very long argument list)
- [x] #2 ignoring N rows starts one check-ignore process and writes each target file once
- [x] #3 FakeRepo counts calls, and tests assert the counts
- [x] #4 repo tests cover the `-f` retry, a path with spaces and non-ASCII, and the stdin parser with a `C:/...` source
- [x] #5 timing numbers before and after are in the commit body
<!-- AC:END -->

## Notes

- `GitRepo.untrack` takes an `Iterable<String>`; `checkIgnoreAll` and `appendIgnoreLines` are new.
  `checkIgnore` and `appendIgnoreLine` stay for the ignore pane, the probes and the tests
  (`appendIgnoreLine` is now `appendIgnoreLines` with one pattern).
- `track` uses the same `Repo.argumentBatches` split (30,000 characters): `git add` of a few
  thousand paths had the same command line limit.
- `checkIgnoreAll` is the second place that starts git without the `git` package
  (`GitDir.runCommand` cannot write stdin). On a fatal answer (exit 128, e.g. a path inside a
  submodule) it falls back to one call per path, so one bad path cannot hide the others. When
  task-15's `ProcessRunner` lands (stack A), this call should go through it.
- Ignore with "stop tracking" untracks only the rows that were tracked, in one call; an untracked
  row used to fail `git rm` and be reported as skipped. task-12 removes the checkbox anyway.
- Real git, 100 files, this machine: check-ignore 23.7 s per row -> 0.16 s with stdin;
  untrack 22.5 s per row -> 0.44 s in one call; 100 appends 11.6 s -> one write 3 ms.
