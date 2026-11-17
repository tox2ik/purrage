---
id: task-11
title: The ignore pane follows the match, and can be resized
status: Done
assignee: []
created_date: '2026-11-17'
labels:
  - ui
  - usability
dependencies: []
priority: medium
---

## Description

**Merge 18 of 21** · stack C · branch `PR-ignore-pane-follows` · stacked on `PR-say-loading-state`

The pane answers "why is this file ignored, or not?", but only when the user has already picked
the right file in its rail. `IgnorePaneState.matchLine` returns null when the matching rule lives in
another file (`lib/state/ignore_files.dart:65`), so a match in `lib/generated/.gitignore` while the
root file is selected shows nothing. A rule from `.git/info/exclude` or the global file is never
shown, because neither is in the rail.

- When the cursor settles and `check-ignore` names a source, select that file and scroll its lines
  so the matching line is in view (with the task-4 reveal). The user's own pick wins until the
  cursor moves again.
- A match in `info/exclude` or the global file: show a one-line "ignored by `<pattern>` in
  `<file>:<line>`" with an Open button, instead of nothing.
- "Not ignored" is said as such, not left blank.
- The pane is a fixed 360 px with a 180 px rail (`changes_view.dart:63`, `ignore_pane.dart:49`).
  On a narrow window the file list shrinks first. Port Ops' `resizable_pane.dart`, remember the
  width in prefs, and collapse the pane under about 900 px window width (with a key to toggle it).

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 state tests: a match in a nested file selects it; a match in exclude/global sets an outside-match the view shows
- [x] #2 the pane width is draggable and remembered; it collapses on a narrow window
- [x] #3 the drag handle has the resize cursor and a tooltip
<!-- AC:END -->

## Notes

- `IgnorePaneState.focusPath` selects the rail file the match is in. The rail calls `pick`
  (not `select`), which holds the user's file until `focusPath` gets a different path.
  `outsideMatch` (`OutsideMatch`: pattern, line, file, absolute path) covers exclude and the
  global file; `verdict` says `line N`, `not ignored`, `ignored elsewhere` or `matched in …`.
- The line list has a fixed 20 px extent and scrolls the matching line to the middle only when
  it is out of view. This is a local reveal; task-4's index-based reveal (stack B) can replace it.
- Resize: `lib/ui/resizable_pane.dart` (Ops' pane, mirrored for a right-hand pane, the width in
  `PaneLayout` instead of widget state); `PaneLayout` (`lib/state/pane_layout.dart`) clamps to
  240 px .. 60% of the window, saves through `Prefs.setIgnorePaneWidth` when a drag ends, and
  hides the pane under 900 px. The rail takes half the pane up to its old 180 px.
- Toggle key: `p` (plain, Changes mode), in the handler, `keyTable`, `handled` and PLAN Keys.
  **For the user**: `p` was my choice; say if you want another key.
- "Open" on an outside match calls the new `Shell.openIgnoreFile`.
- Widget tests run in an 800 px window, so the pane is hidden there by default now; the tests
  that need it set the window size.
- Joined onto A+B: `PaneLayout` lives in `Workspace` (restored from prefs in `start`), `p` is a
  `Binding` (`TogglePaneIntent`) so Help lists it, the outside match's Open is a `SmallButton`,
  and B's `PaneMark` is the child of the resizable pane (the accent line and the drag edge
  coexist; one resize implementation, `lib/ui/resizable_pane.dart`). The rail's j/k
  (`selectBy`) counts as the user's pick. Tab now skips stops that are not on screen, so with
  the pane hidden it goes list → commit → filter; A's Tab test runs in a 1400 px window.
