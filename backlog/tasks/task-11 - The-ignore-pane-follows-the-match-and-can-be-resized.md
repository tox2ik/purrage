---
id: task-11
title: The ignore pane follows the match, and can be resized
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - ui
  - usability
dependencies: []
priority: medium
---

## Description

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
- [ ] #1 state tests: a match in a nested file selects it; a match in exclude/global sets an outside-match the view shows
- [ ] #2 the pane width is draggable and remembered; it collapses on a narrow window
- [ ] #3 the drag handle has the resize cursor and a tooltip
<!-- AC:END -->
