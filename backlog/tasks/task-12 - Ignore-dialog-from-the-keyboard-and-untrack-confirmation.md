---
id: task-12
title: 'Ignore dialog from the keyboard, and three discrete actions'
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

**Merge 16 of 21** · stack C · branch `PR-discrete-ignore-actions` · stacked on `PR-lints-plan-drift`

`IgnoreDialog` (`lib/ui/ignore_dialog.dart`) is mouse-first:

- The scope chips and the target tiles cannot be chosen by key. Wanted: `1`/`2`/`3` (or `f`/`x`/`d`)
  for the scope, `j`/`k` through the targets, `Enter` confirms, `Esc` cancels.
- The target `ListTile`s rely on Material's default cursor and have no tooltip. The project rule
  is an explicit pointer cursor and a tooltip on every clickable.
- With several rows and the *extension* scope, the preview lists the same `*.log` once per row.
  `ignorePreviews` should deduplicate, and say "3 files → 1 rule".
- The preview does not say when a row is already ignored. That is only discovered after the
  click, as a refusal. `checkIgnoreAll` (task-2) can answer it while the dialog is open.

### Decided 2026-11-17 (the user)

**Add, Untrack and Ignore are three discrete actions.** No action does two of them.

- **Drop the "stop tracking" checkbox** from the ignore dialog (`ignore_dialog.dart:43`, `:123`),
  `IgnoreChoice.stopTracking`, the `stopTracking` parameter of `Changes.ignoreSelected`
  (`changes.dart:444`, `:506`) and its pass-through in `shell.dart:449`. Ignoring a tracked file
  writes the rule and nothing else.
- **Untrack has no dialog**, and none is coming: no confirm anywhere in the app. It stays what the
  code does today: at once, optimistic, `git rm --cached`.
- **Untrack never removes a file from disk.** That is the top priority. Every untrack path uses
  `--cached`, including the `-f` retry for a nested repository; a repo test checks the file or
  folder is still there (task-18).
- **Feedback**: every untrack adds a console row. The notice stays, but it is grouped: untracks
  within **900 ms** of each other share one notice that lists all their files, not one notice per
  file. The window restarts with each untrack; the notice goes up when it closes.
- **PLAN.md**: "Untrack (`u`)" loses "confirm first, and say in the dialog…" and gains the grouped
  notice. The "Ignore + stop tracking" bullet (lines 71–72) is removed. The loop on line 11 and
  the row action on line 208 stay.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 the ignore dialog can be completed with keys only (widget test)
- [ ] #2 targets have an explicit pointer cursor and a tooltip
- [ ] #3 previews are deduplicated and show already-ignored rows
- [ ] #4 the ignore dialog has no "stop tracking" checkbox, and `ignoreSelected` never untracks
- [ ] #5 untrack shows no dialog; several untracks within 900 ms give one notice naming every file (fake-clock test), and each adds a console row
- [ ] #6 PLAN.md and the code agree: three discrete actions, no confirm, no "Ignore + stop tracking"
<!-- AC:END -->
