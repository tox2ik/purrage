---
id: task-5
title: A cursor move redraws only the list
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - perf
dependencies:
  - task-3
priority: medium
---

## Description

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
- [ ] #1 a widget test counts builds: one `j` rebuilds no CommitBar and no IgnorePane
- [ ] #2 the task-1 numbers for `changes.move` (frame phase) are lower than before, recorded in the commit body
<!-- AC:END -->
