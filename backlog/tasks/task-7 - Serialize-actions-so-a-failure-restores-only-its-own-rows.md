---
id: task-7
title: Serialize actions so a failure restores only its own rows
status: Done
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
- [x] #1 FakeRepo can hold a call open (a Completer) and fail it on demand
- [x] #2 a test runs track (held, then failed) and ignore, and the ignored row stays gone
- [x] #3 `lastCommand`/`lastOrigin`/`lastChanged` are replaced by a per-action result; report() reads it
<!-- AC:END -->

## Notes

- `Changes` queues the git step of every action (`_enqueue`); the optimistic change is applied
  at once, outside the queue. A failure undoes its own `_RowChange` (rows it removed come back,
  rows it added go) on the current list. `lastReport`, `lastFailure`, `lastCommand`,
  `lastOrigin`, `lastChanged` and `ActionReport` are gone; `trackSelected`, `untrackSelected`,
  `ignoreSelected`, `ignoreQuick` and `commit` return an `ActionResult` (action, failure,
  origin, command, changed; `ok`, `problem`). `Workspace.report(result)` reads only that.
- While another action is still queued, a finished one does not re-read `git status` (the answer
  would not hold the queued change yet, and its row would flicker back); the last one does.
- An ignore whose rule could not be written puts back that row only (before, it waited for the
  refresh).
- `commit` joins the queue too, so it runs after pending adds; a refused commit says why
  (`the summary is empty`, `nothing is staged`) instead of a bare `commit failed`.
- The `check-ignore` pre-check of an ignore runs before the optimistic step, outside the queue
  (read-only). task-2 changes that code anyway (one `--stdin` call).
- `FakeRepo.hold(method)` returns the completer; `failures`, `calls` were added in task-14.
- Tests: `test/serialize_test.dart`.
