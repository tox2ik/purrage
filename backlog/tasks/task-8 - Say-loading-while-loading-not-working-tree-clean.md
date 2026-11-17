---
id: task-8
title: Say loading while loading, not "working tree clean"
status: Done
assignee: []
created_date: '2026-11-17'
labels:
  - bug
  - ui
dependencies: []
priority: medium
---

## Description

**Merge 17 of 21** · stack C · branch `PR-say-loading-state` · stacked on `PR-discrete-ignore-actions`

`FileList.build` shows "Nothing to commit, working tree clean." whenever `changes.rows` is empty
(`lib/ui/file_list.dart:86`), including before the first `git status` has answered and after a
load that failed. On a big repository, or a home folder (`make live`), the first thing on screen is
a false statement. After switching repositories in Browse it is shown for the new checkout until
its status arrives.

Make the empty state depend on what is known: before the first load, a quiet "reading git status…"
line (no spinner flash under 150 ms); after a failed load, the error banner and nothing else; only
after a successful load with no rows, "working tree clean". The nested-repository probe
(`Changes._scanNested`) also notifies when it found nothing new: notify only when the set grew.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `Changes` has a `loaded` (or a load state enum) the view reads
- [x] #2 widget tests: a FakeRepo whose status is held open shows the loading line, a failing one shows only the banner, an empty one shows "working tree clean"
- [x] #3 `_scanNested` does not notify when no nested repository was found
<!-- AC:END -->

## Notes

- `Changes.loadState` (`LoadState.loading` / `loaded` / `failed`), set by `load()`; a reload of a
  loaded repo stays `loaded` while it runs, so the rows do not blink.
- `EmptyList` in `file_list.dart` decides the empty body: nothing for the first 150 ms, then a
  muted "reading git status…"; nothing after a failure (the banner speaks); "Nothing to commit,
  working tree clean." only after a successful load.
- Tests in `test/load_state_test.dart` (after the join: `FakeRepo.hold('status')` and
  `failures['status']` from stack A): the three widget states, and the probe notifying only
  when a nested repository was found (`_notify(rows: true)` only when the set grew).
- A Browse switch already awaits the new checkout's first load before it swaps the state in, so
  it never showed the new checkout as "clean" early; nothing changed there.
- `EmptyList` sits in B's `FileList._body`; the muted line uses `T.small`.
