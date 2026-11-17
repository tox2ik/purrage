---
id: task-5
title: A cursor move redraws only the list
status: Done
assignee: []
created_date: '2026-11-17'
labels:
  - perf
dependencies:
  - task-3
priority: medium
---

## Description

**Merge 11 of 21** · stack B · branch `PR-list-only-redraw` · stacked on `PR-fixed-row-reveal`

`ChangesView` wraps the whole mode in one `ListenableBuilder(changes)`
(`lib/ui/changes_view.dart:43`). Every `notifyListeners()` (each `j`, each click, `busy` going on
and off twice per load) rebuilds the error banner, the filter header, the commit bar
(`TextField`, `FilledButton`), the ignore pane wrapper and the list. Each `Changes` notify also
restarts the 250 ms ignore probe timer in the shell, which is right, and redraws, which is not
needed when only the selection changed.

Split what changes:

- `Changes` exposes narrower listenables: `cursor` (index and selection: the list listens), `rows`
  (rows, filter, nested markers: the list and the section counts listen), `status` (busy, error,
  staged count: the commit bar and banner listen).
- The ignore pane and the commit bar do not listen to cursor moves at all.
- The shell's ignore probe listens to `cursor` only.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 a widget test counts builds: one `j` rebuilds no CommitBar and no IgnorePane
- [x] #2 the task-1 numbers for `changes.move` (frame phase) are lower than before, recorded in the commit body
<!-- AC:END -->

## Notes

- `Changes.cursor`, `Changes.rowsChanged` and `Changes.status` are the narrow listenables.
  The rows one is `rowsChanged`, not `rows`, because `rows` is already the row list.
  `Changes` itself still notifies on everything, for the listeners that want it all.
- `ChangesView` has no builder of its own; `FileList` listens to rows + cursor below its filter
  field, `_ErrorBanner` and `CommitBar` to status, the reveal and the shell's ignore probe to
  cursor (four one-line edits in `shell.dart`; stack A moves that code into `Workspace`).
- The build count uses Flutter's `debugOnRebuildDirtyWidget`; the test calls `changes.move(1)`
  on a `ChangesView` with a FakeRepo instead of sending `j` to the whole Shell (whose startup
  does real file I/O).
- `refresh` clears a stale error even when the rows did not change (it used to clear it after
  `_setRows` had already redrawn, or not at all).
- `_notify` does nothing after `dispose`: the unawaited nested scan (task-19) can finish after
  Browse dropped this `Changes`.
- Measure, 2,000 rows (debug, shared CPU): `changes.move/frame` inside the viewport p50
  ~56 ms -> ~46 ms; while scrolling ~95 ms -> ~50 ms.
