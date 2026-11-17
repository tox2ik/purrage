---
id: task-12
title: Ignore dialog from the keyboard, and the untrack confirmation
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

`IgnoreDialog` (`lib/ui/ignore_dialog.dart`) is mouse-first:

- The scope chips and the target tiles cannot be chosen by key. Wanted: `1`/`2`/`3` (or `f`/`x`/`d`)
  for the scope, `j`/`k` through the targets, `Enter` confirms, `Esc` cancels.
- The target `ListTile`s rely on Material's default cursor and have no tooltip. The project rule
  is an explicit pointer cursor and a tooltip on every clickable.
- With several rows and the *extension* scope, the preview lists the same `*.log` once per row.
  `ignorePreviews` should deduplicate, and say "3 files → 1 rule".
- The preview does not say when a row is already ignored. That is only discovered after the
  click, as a refusal. `checkIgnoreAll` (task-2) can answer it while the dialog is open.

Untrack: PLAN.md says "**Untrack** (`u`): `git rm --cached`; confirm first, and say in the dialog
that the file stays on disk". The code untracks at once. Either add the confirm (Ops
`confirm_dialog.dart`, `Enter` confirms) or change PLAN.md on purpose: untrack only touches the
index and is undone by `Add`, so a notice with **Undo** might fit the "instant" rule better.
This is the user's decision.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the ignore dialog can be completed with keys only (widget test)
- [ ] #2 targets have an explicit pointer cursor and a tooltip
- [ ] #3 previews are deduplicated and show already-ignored rows
- [ ] #4 PLAN.md and the code agree about the untrack confirmation
<!-- AC:END -->
