---
id: task-4
title: Fixed row height and index-based reveal
status: Done
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
- [x] #1 the row height and the header height are tokens in `lib/ui/theme.dart`
- [x] #2 the list builds with a fixed extent, and `FileList` holds no GlobalKey
- [x] #3 a widget test puts the cursor on row 400 of 500 (seeded FakeRepo) and finds it on screen
- [x] #4 a move inside the viewport does not scroll (the existing rule)
<!-- AC:END -->

## Notes

- Tokens: `T.rowHeight` (24) and `T.sectionHeaderHeight` (30) in `theme.dart`, in a new
  `abstract final class T` that task-20 extends with the rest of the scales.
- `lib/ui/reveal.dart` is Ops' `revealRange` (jumpTo, the least scroll). The row's top is
  `headersAbove(index) * header + index * row` (`Changes.headersAbove` reads the cached section
  counts). When a reload grew the list and its new length is not laid out yet, the reveal runs
  again after the frame.
- `FileList` re-subscribes in `didUpdateWidget` when Browse swaps the `Changes` (it kept
  listening to the old one).
- Tests (`test/reveal_test.dart`): row 400 of 500, a reload far down after scrolling away, a
  reload that grows the list, no scroll inside the viewport and the least scroll past it, the
  fixed extent, and a source grep for `GlobalKey`.
- Measure (2,000 rows, debug, CPU shared with two other test runs, so noisy): inside the
  viewport `changes.move/frame` p50 ~76 ms -> ~56 ms. Past the viewport the old code queued an
  animation the frame never ran (the list did not move); now every move scrolls, ~95 ms p50.
