---
id: task-2
title: One git call per action
status: To Do
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
- [ ] #1 untracking N rows starts one git process (or a few, for a very long argument list)
- [ ] #2 ignoring N rows starts one check-ignore process and writes each target file once
- [ ] #3 FakeRepo counts calls, and tests assert the counts
- [ ] #4 repo tests cover the `-f` retry, a path with spaces and non-ASCII, and the stdin parser with a `C:/...` source
- [ ] #5 timing numbers before and after are in the commit body
<!-- AC:END -->
