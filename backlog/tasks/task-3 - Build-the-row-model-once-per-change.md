---
id: task-3
title: Build the row model once per change, not per frame
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

**Merge 9 of 21** · stack B · branch `PR-row-model-once` · stacked on `PR-one-git-call`

A cursor move does far more than redraw the visible tiles:

- `FileList.build` (`lib/ui/file_list.dart:106`) rebuilds the flat header/row list on every
  notify: `changes.section()` is called four times, and each call filters all visible rows into a
  new list. That is O(rows) allocations per keypress.
- `Changes.selectedRows` / `selectionCount` walk every visible row and build a string key for
  each (`_key` concatenates section and path). `selectionCount` is called on every action for
  the diagnostics label.
- `StatusRow.name` and `.folder` are getters that slice the path on every call. The sort
  comparator (`Changes._compare`) calls both and lower-cases both sides on every comparison.
  `filterRows` lower-cases every path on every keystroke.

Do instead:

- `StatusRow` computes `name`, `folder`, `sortKey` (lower-case folder and name) and `key`
  (section + path) once, as `late final` fields or in the parser.
- `Changes` owns the flat list (`items`: headers and rows with their flat index) and the section
  counts, rebuilt only in `_setRows` / `_applyFilter`. `FileList` reads it.
- The selection is a set of keys plus a cached count; `selectedRows` is only built when an action
  runs.
- `move()`, `click()`, `extendSelection()` touch only the index and the selection set.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 a cursor move allocates nothing proportional to the row count (checked with the task-1 measure test at 2,000 rows)
- [x] #2 sorting 5,000 rows does no per-comparison string work
- [x] #3 `FileList.build` has no loop over rows
- [x] #4 existing changes, filter and shell tests still pass unchanged
<!-- AC:END -->

## Notes

- `StatusRow` is no longer `const`: `name`, `folder`, `folderLower`, `nameLower`, `pathLower`
  and `key` are `late final`, computed on first use. Nothing built it as `const`.
- `StatusRow.compare` replaces `Changes._compare`; the filter reads `pathLower`.
- `Changes.items` (`HeaderItem` / `RowItem`, sealed `ListItem`) and `stagedCount` are rebuilt in
  `_applyFilter` / `_takeRows` only. `Changes.section()` and `RowEntry` are gone.
- `selectionCount` is the selection set's size (it only ever holds visible keys);
  `selectedRows` is still a walk, asked for by actions only.
- Measure, 2,000 rows: `changes.move` state stays ~0.0 ms; `changes.move/frame` p50 ~98 ms ->
  ~90 ms. The rest of the frame is the whole-mode rebuild (task-5) and the GlobalKeys (task-4).
  The row test checks that a move keeps the identical `items` list.
