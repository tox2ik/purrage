---
id: task-9
title: Keyboard in every mode, and between panes
status: Done
assignee: []
created_date: '2026-11-17'
labels:
  - usability
  - keys
dependencies: []
priority: high
---

## Description

**Merge 6 of 21** · stack A · branch `PR-keys-every-mode` · stacked on `PR-ui-atoms-shortcuts`

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
- [x] #1 Browse, Console and Settings are fully usable without a mouse (widget tests per mode)
- [x] #2 Tab/Shift+Tab visit every stop in visual order and wrap; the debug bar names each
- [x] #3 Home/End/PageUp/PageDown/Ctrl+A/Esc work in the Changes list, with Shift variants extending the selection
- [x] #4 Ctrl+R and Ctrl+F match on logicalKey; a test sends them with `character: null`
- [x] #5 every new key is in the handler, `keyTable` and PLAN.md Keys (see task-10)
<!-- AC:END -->

## Notes

- Each mode has its own `FocusNode` (`file list`, `browse list`, `editor list`, `console list`,
  `help`), named in `appFocusRoles`; `show(mode)` gives the keyboard to it after the frame that
  shows it (no `autofocus` inside the IndexedStack). Changes has five Tab stops: filter, list,
  ignore rail, ignore lines, commit message (`ShellState.stops`).
- Per-mode keys are a `KeyScope` (`app_keys.dart`: Shortcuts + Actions + Focus, off while a text
  field has focus). New lists: `motionBindings` (j/k/arrows/WASD, Home/End, PageUp/PageDown, Shift
  forms), `browseBindings`, `consoleBindings`, `settingsBindings`; Tab/Shift+Tab are in
  `appBindings`. Enter uses Flutter's own `ActivateIntent`. Help is grouped by section
  (`helpGroups`).
- State: `RepoBrowser` has `filter`, `visible`, `index`, `selected`, `move`; `Changes` has
  `collapseSelection`; `IgnorePaneState.selectBy`; a small `ListCursor` serves Console and
  Settings. Browse got a filter field (`/`); `FilterField(onDone:)` hands the keyboard back to the
  list, and Tab in the field now moves to the next pane instead of just leaving it.
- PageUp/PageDown move 15 rows (`pageRows`) until task-4 gives a fixed row height for a real
  viewport page. Open: switch to the viewport once task-4 lands.
- AC #4: Flutter's test helpers derive a character when none is given, so the test sends Ctrl+R
  and Ctrl+F with the control characters Windows produces (`\x12`, `\x06`); `SingleActivator`
  ignores the character either way.
- `lib/ui/nav_keys.dart` (`navDelta`, `isPlain`) had no caller left and was removed; CLAUDE.md
  still names `navKey(event)` in "Keys and mouse" (for the coordinator at the join).
- Tests: `test/keys_every_mode_test.dart`, `test/app_keys_test.dart`. `make test`: 181 passed.
