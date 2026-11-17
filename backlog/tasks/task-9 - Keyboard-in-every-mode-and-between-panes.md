---
id: task-9
title: Keyboard in every mode, and between panes
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - usability
  - keys
dependencies: []
priority: high
---

## Description

`ShellState.onKey` hands keys only to Changes (`lib/ui/shell.dart:232`). Everywhere else the mouse
is the only way in, which breaks the Ops contract the plan copies:

- **Browse**: no key moves through the list or opens a repository. Wanted: `j`/`k`/arrows via
  `navKey`, `Enter` opens, `Backspace` / `h` goes up one level, `F5` rescans, `/` filters the list.
- **Console**: `j`/`k` move, `Enter` / `l` expands the row, `Ctrl+C` copies its detail.
- **Settings**: `j`/`k` through the detected editors, `Enter` picks one.
- **Tab / Shift+Tab between panes**: Help lists it, and nothing does it. In Changes the stops are
  filter, list, ignore rail, ignore lines, commit field. The ignore pane cannot be reached from the
  keyboard at all today.
- **List keys**: `Home`/`End`, `PageUp`/`PageDown` (a viewport of rows; needs task-4), `Ctrl+A`
  (`Changes.selectAll` exists and nothing calls it), `Esc` in the list collapses the selection
  to the cursor row.
- `Ctrl+R` and `Ctrl+F` are matched on `event.character` (`shell.dart:242`, `:260`). With Ctrl
  held, Windows can deliver a control character (`\x12`) or none, depending on the layout. Match
  `logicalKey` (`keyR`, `keyF`) instead, like F5.

Each mode gets its own `FocusNode` with a `debugLabel` and a `focusRoles` entry, no `autofocus`
inside an IndexedStack child, and the shell gives the keyboard to the shown mode on every switch
(Ops: "Keys").

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Browse, Console and Settings are fully usable without a mouse (widget tests per mode)
- [ ] #2 Tab/Shift+Tab visit every stop in visual order and wrap; the debug bar names each
- [ ] #3 Home/End/PageUp/PageDown/Ctrl+A/Esc work in the Changes list, with Shift variants extending the selection
- [ ] #4 Ctrl+R and Ctrl+F match on logicalKey; a test sends them with `character: null`
- [ ] #5 every new key is in the handler, `keyTable` and PLAN.md Keys (see task-10)
<!-- AC:END -->
