---
id: task-4
title: Fixed row height and index-based reveal
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - perf
  - bug
dependencies:
  - task-3
priority: high
---

## Description

**Merge 10 of 21** · stack B · branch `PR-fixed-row-reveal` · stacked on `PR-row-model-once`

`_FileListState._reveal` (`lib/ui/file_list.dart:59`) finds the focused row through a
`GlobalKey` per index. That has three problems:

- **Bug:** a row that is not built has no context, and `_reveal` returns without scrolling. The
  cursor can leave the viewport and stay out: after a reload keeps the cursor on a path far down,
  after a long Shift+wheel run, and with Page Down / End once those exist (task-9).
- The `keys` map grows with every index ever shown and is never pruned. GlobalKeys are the most
  expensive kind of key: each registers with the owner, and the key for index N moves to another
  row when the list changes.
- `Scrollable.ensureVisible` animates (90 ms), so holding `j` queues animations.

Do it the Ops way (`~/ws/nvimos-ops/lib/ui/reveal.dart`, `tasks/rows.dart`): every row and section
header has a fixed height from `theme.dart`, the list uses `itemExtent` (or `itemExtentBuilder`
for the headers), and reveal computes the row's top from its flat index and calls
`revealRange(controller, top, height)` with `jumpTo`. No GlobalKeys.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the row height and the header height are tokens in `lib/ui/theme.dart`
- [ ] #2 the list builds with a fixed extent, and `FileList` holds no GlobalKey
- [ ] #3 a widget test puts the cursor on row 400 of 500 (seeded FakeRepo) and finds it on screen
- [ ] #4 a move inside the viewport does not scroll (the existing rule)
<!-- AC:END -->
