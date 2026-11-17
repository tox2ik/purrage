---
id: task-10
title: One source for mode keys and the help table
status: Done
assignee: []
created_date: '2026-11-17'
labels:
  - docs
  - usability
dependencies: []
priority: high
---

## Description

**Merge 14 of 21** · stack C · branch `PR-mode-keys-source` · stacked on `PR-design-tokens` (built on `main`, rebased onto stack B when the stacks are joined)

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
- [x] #1 no hard-coded `Alt+<digit>` string is left in `lib/` outside the Mode enum
- [x] #2 keyTable matches the handlers; a test walks a list of (key, expected action) pairs and checks each has a row
- [x] #3 CLAUDE.md and PLAN.md Keys agree with the enum
<!-- AC:END -->

## Notes

- `Mode` moved to `lib/state/modes.dart` (so `editors.dart` can name Settings without importing
  UI) and carries `label`, `number`, `key` (`Alt+3`) and `named` (`Settings (Alt+3)`).
  `mode_rail.dart` re-exports it and keeps the look (`icon`, `digit` as a key); the rail tooltips
  are `mode.named`.
- Joined onto stacks A+B: the key map and the help table are already one source there
  (`app_keys.dart` bindings, task-21), which covers "keyTable matches the handlers"; my
  hand-written table and `handled` list were dropped. The mode line of that map is built from
  `Mode.key`.
- `test/help_keys_test.dart` now checks the enum, the mode help line, and that no string in
  `lib/` spells out an `Alt+<digit>` (`app_keys_test.dart` covers the handlers and the table).
