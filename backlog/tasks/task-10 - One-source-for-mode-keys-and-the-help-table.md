---
id: task-10
title: One source for mode keys and the help table
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - docs
  - usability
dependencies: []
priority: high
---

## Description

The mode numbers changed when Browse arrived (`Mode` enum: Changes 1, Browse 2, Settings 3,
Console 4, Help 5), and four places still say the old ones:

- `lib/ui/help_view.dart:13`: `Alt+1 / Alt+2 / Alt+3` = "Changes, Settings, Help"
- `lib/main.dart:107`: "The Console mode (Alt+3)"
- `lib/state/editors.dart:184`: "Pick one in Settings (Alt+2)"
- `CLAUDE.md` (Reporting, Keys): Console `Alt+3`, Settings `Alt+2`, Help `Alt+4`

The help table is stale in other places too. `i` is described as "pick scope and which ignore
file", but `i` is the one-key literal ignore and `Shift+I` opens the dialog. `Shift+I`, `a`, `E`
and Shift+wheel are not listed. `Tab / Shift+Tab` is listed and does not exist (task-9). `r` and
`F5` are two entries with different wording for the same action.

Fix it at the source: `Mode` carries its label and digit, the help table's mode line and every
"(Alt+N)" in a message are built from it, and a test fails when a key handled in `ShellState`
has no `keyTable` row.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 no hard-coded `Alt+<digit>` string is left in `lib/` outside the Mode enum
- [ ] #2 keyTable matches the handlers; a test walks a list of (key, expected action) pairs and checks each has a row
- [ ] #3 CLAUDE.md and PLAN.md Keys agree with the enum
<!-- AC:END -->
