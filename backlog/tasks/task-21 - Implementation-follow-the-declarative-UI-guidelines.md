---
id: task-21
title: 'Implementation: follow the declarative UI guidelines'
status: Done
assignee: []
created_date: '2026-11-17'
labels:
  - ui
  - refactor
dependencies:
  - task-14
priority: high
---

## Description

**Merge 5 of 21** · stack A · branch `PR-ui-atoms-shortcuts` · stacked on `PR-serialize-actions`

Measured against `~/ws/nvimos-ops/declarative_ui_guidelines.md` (nesting at most 3, `build` under
50 lines, data-driven lists, no logic in handlers, dumb atoms and molecules) and the UI rules in Ops'
CLAUDE.md (Flutter's own names and classes for the job, a label is part of its control, an explicit
pointer cursor and tooltip on every clickable, no InheritedWidget lookup in `dispose`).

**Build length** (`build` from signature to closing brace):

- `_RepoRow.build` in `browse_view.dart:210`: 72 lines
- `_FileListState.build` in `file_list.dart:76`: 56 (three return shapes, and the flat list built inline, see task-3)
- `NoticeBar.build` in `notice_bar.dart:13`: 55
- `ChangesView.build`: 44, `_Entry`/`_Title` in `console_view.dart:141`: 43, close to the limit

**Nesting**: `RowTile.build` goes Tooltip → MouseRegion → InkWell → Container → Row → Expanded → Row
→ Expanded → Row → Flexible → Text across `build` and `_name`. `ShellState.build` goes Focus →
Scaffold → Stack → DebugBar → Row → Expanded. Extract named organisms: `FileRow` (badge, folder
cell, actions slot, name cell), `ShellLayout`.

**Logic in event handlers**: `_FileListState._item` (`file_list.dart:146`) has five closures of the
form `if (!changes.isSelected(row)) changes.click(index); widget.onTrack();`. That is a selection
rule in the view. Make it one state method (`changes.target(index)`, "act on this row unless
it is part of the selection") and pass method references. Also `browse_view.dart:138`
(`onChanged: (root) { … }`) and `filter_field.dart:84`.

**Atoms, written once**: the clickable atom "Tooltip + MouseRegion(click) + InkWell/IconButton" is
hand-built about 16 times, across `browse_view` (`_Button`), `settings_view` (`_ActionButton`),
`file_list` (`_TextAction`, the reload button), `console_view`, `ignore_pane`, `filter_field`,
`notice_bar`, `debug_bar` and `shell` (`_RailButton`). Each copy can forget the cursor or the
tooltip. Port Ops' `lib/ui/widgets.dart` set: `HoverRow` (row: hover, tap, secondary tap, double
tap, cursor, tooltip), `SmallButton`, `LinkButton` (the `Add`/`Ignore` text actions), `IconToggle`,
`Pill` (the `git` chip, the code badge), `PaneHeader`. These atoms take values and emit callbacks.
They make the "explicit cursor and tooltip" rule hold by construction.

**Flutter's own elements for the job**:

- Keys: `ShellState.onKey` / `_changesKey` is an if-chain over characters. Use `Shortcuts` +
  `Actions` with named `Intent`s (`TrackIntent`, `IgnoreIntent`, `ReloadIntent`, …). The help
  table (task-10) can then be generated from the shortcut map, and each mode (task-9) brings its
  own `Shortcuts`.
- The mode rail is a hand-built `Column` of buttons. `NavigationRail` is Flutter's element for
  it, or keep it custom and name it after that role.
- Section headers, row cells and the notice are fine as they are. Name the new ones after the
  Flutter role they play.

**A label is part of its control**: the ignore dialog's targets (`ListTile`) and the scope chips
already are. Check the Settings editor rows and the Browse drive picker. Section headers (`Staged
(3)`) could select their section on click, which would be the "label" of a range.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 every `build` in `lib/ui/` is under 50 lines (a test or tool script measures it, as in the review)
- [x] #2 no event handler closure in `lib/ui/` has more than one statement
- [x] #3 `lib/ui/widgets.dart` holds the atoms; no `MouseRegion(cursor: SystemMouseCursors.click` is left outside it
- [x] #4 app keys go through `Shortcuts`/`Actions`/`Intent`; the help table reads the same map
- [x] #5 widget tests for each atom: cursor, tooltip, the label triggers the action
<!-- AC:END -->

## Notes

- Atoms in `lib/ui/widgets.dart`: `Clickable` (cursor + tooltip, the only place
  `SystemMouseCursors.click` is set), `HoverRow`, `IconAction`, `SmallButton`, `LinkButton`,
  `IconToggle`, `Pill`, `PaneHeader`. Every view uses them; `RowTile` became `FileRow` with
  named cells, `_RepoRow` became `RepoRow` with cells, `NoticeBar` has a `_NoticeCard`.
- `Changes.target(index)` is the "this row unless it is in the selection" rule; the row
  buttons call named methods in `_FileListState`.
- Keys: `lib/ui/app_keys.dart` holds the intents and three binding lists (`appBindings` always,
  `changesBindings` in Changes without a focused text field, `plainBindings` like `?` in any mode
  without a focused text field). `GatedShortcutManager` lets letters reach text fields.
  `keyTable` is generated from the bindings (`helpLines(allBindings)`); `ShellState.onKey` is gone.
  `Ctrl+R`/`Ctrl+F` now match `logicalKey` (`SingleActivator`).
- The Help line "Tab / Shift+Tab" was dropped because nothing implements it yet; task-9 adds the
  key and the line. Help also lost the stale "Alt+1/2/3 = Changes, Settings, Help" (now generated
  from `Mode`), which overlaps task-10 in stack C: resolve at the join.
- `BrowseView(drives:)` takes the probe; the shell passes `browser.listDrives`, so widget tests
  no longer stat real drives.
- `test/ui_rules_test.dart` measures build length, handler statements and the cursor rule;
  `test/widgets_test.dart` the atoms; `test/app_keys_test.dart` the key map and the shell.
- Section headers do not select their section on click (optional in the description); the
  ignore dialog was left to task-12 (stack C).
