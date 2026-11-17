---
id: task-20
title: 'Design: one source for the look'
status: In Progress
assignee: []
created_date: '2026-11-17'
labels:
  - ui
  - design
dependencies: []
priority: high
---

## Description

**Merge 13 of 21** · stack B · branch `PR-design-tokens` · stacked on `PR-scan-off-ui-thread`

Measured against Ops' design principles (`~/ws/nvimos-ops/PLAN.md`, "Style and theme"): one
dark, flat, quiet theme, `ui/theme.dart` as the only place with a colour, font size, radius or
spacing step, a small scale for each, visible focus for a keyboard-first app, 4.5:1 text contrast,
and a colour never carrying a meaning alone.

Purrage has the palette right (`theme.dart`: near-black, one indigo accent, hairlines). The rest
of the look is still written inline:

- **Type**: 21 inline `fontSize:` values in `browse_view` (6), `ignore_pane` (5), `file_list` (4),
  `console_view` (3), `ignore_dialog` (2), `debug_bar` (1), next to five text-theme styles. The
  sizes in use are 9.5, 10, 10.5, 11.5, 12, 12.5 and 13. Text under 11 px (the row actions at 10.5,
  `labelSmall` 10, the `git` chip at 9.5) is below Ops' floor and hard to read on a dense sheet.
  Name a scale (`T.body` 12.5, `T.small` 11.5, `T.tiny` 11, `T.section`, `T.code`) and use only it.
- **Monospace**: 16 inline `fontFamily: 'monospace'`. On Windows, `monospace` is not a family
  DirectWrite knows, so check what it renders as (it may fall back to the UI font, and the folder
  column would then not be monospaced). Name the font: `Consolas`, with `Cascadia Mono` as
  fallback, in one `T.code` style.
- **Shapes and sizes**: radii 3, 4, 5, 6 and 8, icon sizes 15, 16, 17 and 18. Adopt Ops' proposed
  scale: radii 4 / 6 / pill, icons 14 / 16 / 20, gaps 2 / 4 / 6 / 8 / 12 / 16 / 24, fixed heights
  for row, section header, pane header and commit bar (task-4 needs the row height).
- **Inline colours**: `Colors.transparent` for the accent bar (`file_list.dart:237`,
  `browse_view.dart:229`), and alpha tints computed in widgets (`primaryContainer` at 0.55 and 0.45,
  `secondaryContainer` at 0.35). These become tokens: `chosen`, `cursor`, `current`, `hover`.
- **Hover and ripple**: rows use `InkWell`, so hover and splash come from Material's scheme, not
  the palette, and a click draws a ripple. Ops is flat: a `hover` colour, instant, and no ripple. Set
  `splashFactory: NoSplash.splashFactory` and a hover token in the theme.
- **Focus you can see**: nothing shows whether the list, the ignore pane or the commit field has
  the keys. Only a focused text field gets the accent border. Light the active pane's title or edge
  in accent (Ops: the active list's title). The cursor row of an inactive list reads weaker than an
  active one.
- **Contrast check**: verify `_muted` on `_surface` and on `_raised`, and the folder amber on the
  chosen tint, against 4.5:1. Verify `_line` against 3:1 where it is the only boundary (the `git`
  chip outline).
- **Never colour alone**: a folder is amber *and* has a trailing slash (good). The chosen and
  cursor rows differ by tint, plus the bar for the cursor (good). The Console error rows are only
  red: add the code badge or an icon to every failure.
- **Tooltips say the key**: the rail says "Changes", not "Changes (Alt+1)", and the row actions say
  "Track this file (git add)" without `space`. Every tooltip of an action that has a key names it
  (see task-10 for the single source).
- **Window title**: `MaterialApp.title` and the native title in `windows/runner/main.cpp` agree, and
  name the repository (task-13).

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 no `fontSize:`, `fontFamily:`, `Color(`, `Colors.` or `.withValues(` in `lib/ui/` outside `theme.dart` (a test greps for it)
- [x] #2 the text, radius, icon and gap scales, and the fixed heights, are named in `theme.dart`; no text under 11 px
- [ ] #3 monospace text renders in Consolas on Windows (checked by hand in `make run`)
- [x] #4 rows hover with the palette's colour and do not ripple
- [x] #5 the pane that has the keys is visibly marked; switching with Tab moves the mark
- [x] #6 every action tooltip names its key
- [x] #7 PLAN.md gets a short "Style" section with the scales (not normative for the colours, normative for "tokens only")
<!-- AC:END -->

## Notes

- Tokens live in `abstract final class T` in `theme.dart` (started by task-4 for the row
  heights): type `body`/`small`/`tiny`/`section`/`title`/`code`/`codeSmall`/`codeTiny`, radii,
  icons, gaps, heights, and the colours `chosen`, `cursor`, `current`, `hover`, `none`, `folder`,
  `tooltip`, `thumb`. `purrageFolder` became `T.folder`. Sizes raised to 11: `labelMedium`,
  `labelSmall`, the row actions, the status letter, the `git` chip, the console code badge.
- Code font: `Consolas`, fallback `Cascadia Mono`, `Courier New`. #3 stays for the user: look at
  the folder column and the console in `make run`.
- No ripple: `NoSplash` and `hoverColor: T.hover` in the theme (also for filled, text and icon
  buttons); rows' `InkWell`s set nothing of their own (tested).
- Contrast computed (WCAG): `_muted` on surface 5.8, raised 5.4, chosen 5.1, hover 5.1, tooltip
  4.8; folder amber on chosen 10.1; `_line` 1.3 (never the only boundary). In the theme comment.
- Console: a failure without a code gets an error icon, so red is never alone.
- Tooltips with keys: rail `Changes (Alt+1)` etc. (stack A's `mode_rail.dart`; task-10 makes it a
  single source), Add/Untrack/Ignore, reload (F5, Ctrl+R, r), clear filter (Esc), open ignore
  file (E), Commit (Enter, c), Browse up (Backspace, h) and rescan (F5, Ctrl+R).
- #5: `PaneMark` (an atom in `widgets.dart`) draws an accent line on top of a pane while one of
  its focus nodes has the keys: the list (`listFocus`) and the ignore pane (`railFocus`,
  `linesFocus`), task-9's Tab stops. A focused text field has its own accent border. Open: the
  inactive list's cursor row could read weaker.
- Joined onto stack A: the tokens went into A's atoms (`IconAction`, `SmallButton`,
  `LinkButton`, `IconToggle`, `Pill`) instead of the hand-built widgets; the commit button's
  tooltip goes through `Clickable`. A's tooltips already named most keys; added Space, Shift+I and
  right-click, F5/Ctrl+R/r, Esc, E, Backspace/h.
- Named but not yet applied: `T.paneHeaderHeight` (32) and `T.commitBarHeight` (48). The commit
  bar's outlined field with a floating label is taller than 48 minus padding; fixing it needs a
  decision on the label (task-13 polishes the commit bar).
- Not done: the window title (task-13).
