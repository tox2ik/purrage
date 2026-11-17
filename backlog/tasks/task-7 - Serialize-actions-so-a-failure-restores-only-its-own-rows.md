---
id: task-7
title: Serialize actions so a failure restores only its own rows
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - bug
dependencies: []
priority: high
---

## Description

**Merge 4 of 21** · stack A · branch `PR-serialize-actions` · stacked on `PR-workspace-out-of-shell`

Every optimistic action keeps `final before = _rows;` and puts it back on failure
(`lib/state/changes.dart:287`, `:325`). Nothing stops a second action from starting while git
still runs the first:

1. Press `space` on `a.txt`. The row moves to Staged, and `git add` starts.
2. Press `i` on `b.log` before it ends. The row leaves, and the ignore runs.
3. `git add` fails. `_setRows(before)` brings back the list from before step 1, so `b.log` comes
   back as untracked, although its rule is written.

The following `refresh()` usually puts it right, but the screen lies in between, and `lastFailure`,
`lastCommand` and `lastOrigin` belong to whichever action wrote them last. The shell's `report()`
can then print one action's command under another's verb.

Fix: run actions through a queue in `Changes`, one at a time, so the screen is still optimistic
and each git step runs after the previous one. A failure reverts by applying the inverse of its
own change to the current rows, not by restoring a snapshot. Each action returns its own result
object (summary, failure, command, origin, changed), and the shell reports from that, not from
fields on `Changes`.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 FakeRepo can hold a call open (a Completer) and fail it on demand
- [ ] #2 a test runs track (held, then failed) and ignore, and the ignored row stays gone
- [ ] #3 `lastCommand`/`lastOrigin`/`lastChanged` are replaced by a per-action result; report() reads it
<!-- AC:END -->
