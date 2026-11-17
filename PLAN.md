# Purrage

A small Flutter Windows desktop app for one job: look at `git status`, decide per file
whether to **track** it or **ignore** it, and **commit**. No diffs, no branches, no remotes.

Repo: `~/ws/Purrage`, exe `purrage.exe`, branch `main`. This file is the spec; where it
and the code disagree, fix one of them deliberately.

## Scope, version 1

- The loop: **status list → track / untrack / ignore → commit**.
- The file list fills the window. There is **no preview and no diff** - not the text of the file,
  not hunks, not history. Pressing a row does not open anything.
- No branches, no remotes, no fetch/pull/push, no stashes, no conflict resolution UI beyond
  showing conflicted paths in their own section.
- Project management lives in this repo: `backlog/` (Backlog.md) for tasks, `openspec/` for
  changes that need a design. The app does not read them in v1; they are for the people
  (and agents) working on it.

## Decisions already made

- Platform: **Windows only** for now (`flutter create --platforms=windows`).
- Git access: the **`git` package** (kevmoo, Dart team) for process plumbing and `GitDir`;
  Purrage owns only the **porcelain status parser** and the row/section model.
- Layout: **one file list across the window**, commit bar across the bottom.
- Keys and mouse: **the Ops contract**, copied (see Keys below).
- Commit message: **one summary line, nothing else**. No body, no trailer, no template.
- `.gitignore` is **not edited in the app**. The pane is read-only: it lists the patterns and
  shows which one matches the focused file; an **Open in editor** action hands the file to the
  user's editor. Per-file ignore actions still append patterns, done by the app, not typed.
- Ignore rules are **not all written to the root `.gitignore`**: the app can create and append to
  a `.gitignore` in the focused file's own folder, which is what git recommends for a subtree
  (see "Where a rule lives").
- Editor: auto-detected, chosen in a **Settings mode**, with **nvim-qt first**.
- A **Browse mode** lists the repositories found around the current directory, so the app can move
  between checkouts; the starting directory is not the only one it can manage (see "Browse").
- The look follows a quiet Linear-style sheet: near-black surfaces, hairline dividers, one indigo
  accent, compact rows. Directory base names take Windows Explorer's folder amber.

## The status model

- One call: `git status --porcelain=v1 -z --untracked-files=all --find-renames`, run through
  `GitDir.runCommand` so quoting, worktree paths and error text are handled once.
- Rows are split into sections, in this order: **Conflicts**, **Staged**, **Changed**,
  **Untracked**. A file can appear once per section (staged and changed are different rows, as
  in VS Code and GitHub Desktop).
- Parsing rules: `XY path` per record; `-z` means rename pairs arrive as two NUL-separated
  paths (new, then old); codes are `M A D R C T U` per column; the conflict codes
  `DD AU UD UA DU AA UU` go to Conflicts with a readable label.
- A row whose folder holds a `.git` of its own — an embedded repository, a gitlink, a submodule —
  carries a tiny **git** chip. Its ignore rules belong to that inner repository, not to this
  `.gitignore`. The check is one stat per distinct path, remembered for the session.
- Untracked **directories** are listed as a single row when git reports them that way
  (`--untracked-files=all` avoids most of it); a row that is a directory shows a trailing `/`.
- Refreshes: **only after an action** (`track`, `untrack`, `ignore`, `commit`) and on `r`. There is
  no timer: a periodic `git status` is what made the app feel sluggish, and every action already
  ends with a quiet refresh. Nothing is redrawn when the new list equals the old one.
- Actions are **optimistic**: the rows move (or leave) at once, git runs behind them, and a failure
  puts the previous list back and raises a notice. No click waits on a subprocess.

## Actions

- **Track** (`space` or the row button): `git add -- <path>`. For a deleted file this stages the
  deletion, which is what track means there.
- Track, Untrack and Ignore are **three discrete actions**: none of them does another's work, and
  none asks for confirmation (the app has no confirm dialogs).
- **Untrack** (`u`): `git rm --cached -- <path>`, at once. It **never removes a file from disk**:
  every path, including the `-f` retry for a nested repository, keeps `--cached`. Each untrack
  adds a console row; untracks within 900 ms of each other share one notice that names all
  their files.
- **Ignore** (`i`, row menu): scope submenu — *this file* (`/path/to/file`), *this extension*
  (`*.ext`), *this folder* (`/path/to/folder/`) — and a *where* submenu: the repo root
  `.gitignore` (default), **a new `.gitignore` in the file's own folder**, `.git/info/exclude`,
  or the global ignore file. `i` writes the literal path to the root file at once; `Shift+I` opens
  the dialog, which is complete by keys: `1`/`2`/`3` (or `f`/`x`/`d`) for the scope, `j`/`k` through
  the targets, `Enter` writes, `Esc` cancels. Its preview lists each rule once (`3 files → 1
  rule`) and names the rows git already ignores, with the rule and line, before the click.
  Ignoring a file git already tracks writes the rule and nothing else; untracking it is `u`.
- Ignore writes are literal and anchored, escape glob characters (`*?[]!`) in names, and skip a
  pattern already present anywhere in the file. The app's rules live in a **`# Purrage`
  section**: a new rule goes directly after the section's last rule, one per line, with no blank
  lines between them. A file without the section gets `# Purrage` appended at its end, then the
  rule; a new file is just the section. The file's line endings and final newline are kept.
- **Open in editor** (`e` on a row, `E` for `.gitignore`): hands `{file}` to the chosen editor.
- **Commit** (`c`): enabled only when something is staged and no merge is in progress; runs
  `git commit -F -` with the summary line, then refreshes. Failure shows the git text.
- A conflicted row offers only ignore and open, never track/commit.

## Where a rule lives

Git reads `.gitignore` at every level: a file in `lib/generated/.gitignore` only affects that
folder and below. The app should prefer the **narrowest file that already covers the path**:

1. If the focused file sits in a folder that already has its own `.gitignore`, offer that file
   first (it is where the rule belongs, next to the things it affects).
2. Otherwise offer the repo root `.gitignore`, and a **new `.gitignore` in this file's folder**
   when the folder is a subtree worth its own rules (generated output, build artefacts, vendor
   dumps). The app creates the file with one `# Purrage` line and then the pattern.
3. `.git/info/exclude` for rules that must not be committed, and the global ignore for rules that
   apply to every repo, stay available under *More places*.

Pattern shape depends on the file it goes into:

- Root `.gitignore`: the pattern is repo-relative and anchored (`/build/`, `/vendor/ffmpeg.log`).
- A nested `.gitignore`, in the folder `F`: the pattern is **relative to `F`** (`*.log`,
  `/cache/`), never prefixed with `F` — that is the mistake git's docs warn about.
- Directory scope in a nested file is `name/`, file scope is `/name` when it must not match
  deeper, and a name that starts with `!`, `#` or ends in a space is escaped.

Guards the app enforces before writing a nested file:

- **Already ignored higher up**: run `git check-ignore -v <path>`; if a rule in a parent
  `.gitignore` already ignores the folder, a nested file cannot re-include anything — say so, and
  offer to edit the parent rule instead of silently writing a dead rule.
- **Not in the repo**: a folder outside the working tree, or a symlinked folder, gets an error
  rather than a file.
- **Already ignored here**: if `check-ignore` already reports a rule in the target file, do
  nothing and say which line matches.

The ignore pane becomes a list of `.gitignore` files, not one file:

- Discovered with `git ls-files --cached --others --exclude-standard -- '**/.gitignore'` plus the
  root one (untracked nested files included, ignored ones skipped), shown flat with a short
  `root`, `lib/generated`, … label.
- Selecting one shows its lines read-only, with the focused file's matching rule highlighted
  (from `git check-ignore -v`, which names the file and the line).
- **Open in editor** opens the selected file; a **New here** button creates a `.gitignore` in the
  focused file's folder.
- A nested `.gitignore` the app just created shows up as an untracked row in the list, so tracking
  it is the same gesture as tracking anything else.

## Browse (Alt+2)

- On start it scans the directory the app was started in, up to **five levels deep**, and lists
  every folder that holds a `.git` (folder for a clone, file for a worktree or submodule). The entry
  is the **working directory**, never `.git`; a found repository is not descended into — except the
  browsed directory itself, which is usually a repository and whose children are the point — links
  are never followed, and `node_modules`, `build`, `.dart_tool`, `target`, `dist`, `.venv`, `.gradle`,
  `.idea`, `.vscode` and `.cache` are skipped so a home folder stays walkable.
- Clicking an entry opens that repository — a fresh `Repo`, `Changes` and ignore pane — and the row
  stays marked (tinted, accent bar, `open`): the app stays in Browse, because jumping to Changes made
  the switch look like nothing had happened; `Alt+1` shows the new checkout. Every click writes an
  `opening …` row to the console, and `opened …` with the row count once the checkout is loaded, so a
  failed switch is visible there too.
- **Up one level** moves the browse root to the parent and rescans; a **refresh** button rescans the
  same directory; the header shows the path, a spinner while scanning and the repository count.
- Rows use the file list's two columns: the containing path right-aligned in monospace, the base name
  left-aligned in Explorer's folder amber, so the names line up down the list.
- Each scan writes one console row: the directory, the depth, directories visited and skipped,
  repositories found, elapsed time, and the six slowest and six widest listings — evidence for
  tuning the skip rules rather than guessing.
- Whole trees are never walked on Windows: `C:/Windows`, `C:/Program Files`,
  `C:/Program Files (x86)`, `C:/ProgramData`, `C:/$Recycle.Bin`, `C:/System Volume Information`,
  `C:/Recovery`, `C:/PerfLogs` (matched as path prefixes), plus the name-based skip set
  (`node_modules`, `build`, `.dart_tool`, `target`, `dist`, `obj`, `bin`, `out`, `vendor`, caches,
  …). A path with a `.git` segment is never walked, in any casing: objects and refs are not a
  checkout and are expensive to enumerate.
- `AppData` is **not** skipped: it is entered and walked only **two levels in**
  (`AppData/Local/<one more>`), since a stray checkout can live there but the per-application cache
  trees below hold none. The scan report counts how many `AppData` folders it met.
- On Windows a **drive picker** lists every mounted drive (`A:`…`Z:` that exists) and switches the
  browse root. On Linux this would have to detect real mount points and skip pseudo filesystems;
  out of scope for now.
- A scan that runs while another is in flight is folded into one; the UI never waits on it.

## Console (Alt+4) and failure reporting

- One `ConsoleLog` for the process. It is created in `main()` and shared by the window, the error
  handlers and the Shell, so a failed `Repo.open` and an uncaught exception land in the same list.
- Every failure carries an `ActionFailure`: a one-line summary, a detail block (origin chain,
  parameters, `cwd`, command line) and the tool's own code (`exit 1`, `errno 5`).
- `Shell.say()` shows a notice **and** adds a console row, tagged with the action that failed;
  `Shell.report()` adds a console row for a success — `tracked 3 files`,
  `command: git add -- …` — because a command that ran should be inspectable.
- App-wide handlers: `FlutterError.onError`, `PlatformDispatcher.instance.onError` and a
  `runZonedGuarded` wrapper; each entry carries the interaction in progress
  (`Changes: ignore dialog for <path>`) and the first 14 stack frames.
- The console is newest-first, bounded at 200 rows, has a Clear button, and expands a row to its
  selectable detail. A success prints normally, a failure in the error colour, and only a real
  tool code gets a badge.

## Notices

- A failure shows a bar above the commit strip whose countdown **pauses while the mouse is over
  it** and resumes with the time that was left. It can be dismissed with its close button.
- Successes are silent on screen: the row moving between sections is the feedback. The one
  exception is untrack, whose row leaves the list: untracks within 900 ms share one notice (not in
  the error colours) that names every file and says they are kept on disk.

## Keys (the Ops contract)

- Modes: `Alt+1` Changes, `Alt+2` Browse, `Alt+3` Settings, `Alt+4` Console, `Alt+5` Help; `Alt+]` /
  `Alt+[` cycle; `?` opens Help. The number is the mode's place in the `Mode` enum
  (`lib/state/modes.dart`); the key map, the help table, the rail tooltips and every "(Alt+N)" in
  a message are built from it.
- Motion: Up/Down, `j`/`k`, and WASD from the one `motionBindings` list; never bound per handler.
- Selection: `Shift`+Up/Down grows the highlight from the anchor, one row per press; `Ctrl+Enter`
  turns the cursor row's highlight on or off. The highlighted rows are what every action changes,
  keyboard or mouse. A success says nothing: the row moving between sections is the feedback. A
  refusal or a failure is said every time, with the file and the reason.

- Actions: `space` or `a` track (`git add`), `u` untrack, `i` ignore with the literal path, `Shift+I` the ignore
  dialog, `e` open file, `E` open `.gitignore`, `c` commit, `r` / `F5` / `Ctrl+R` re-read the state,
  `/` or `Ctrl+F` filter, `Esc` close.
- Every list (Changes, Browse, Console, Settings, the ignore rail): `Home` / `End`, `PageUp` /
  `PageDown` (15 rows until the list has a fixed row height to measure a viewport with); in Changes
  the `Shift` forms extend the highlight, `Ctrl+A` highlights every row and `Esc` shrinks the
  highlight to the cursor row.
- Panes: `Tab` / `Shift+Tab` visit the shown mode's stops in visual order and wrap. Changes:
  filter, list, ignore rail, ignore lines, commit message. Every mode switch gives the keyboard to
  that mode's list; the debug bar names each stop.
- Browse: `Enter` opens the repository under the cursor, `Backspace` / `h` go up one level,
  `F5` / `Ctrl+R` rescan, `/` / `Ctrl+F` filter the list.
- Console: `Enter` / `l` unfold or fold the row, `Ctrl+C` copies its summary and detail.
- Settings: `j` / `k` through the detected editors, `Enter` uses one.
- Keys with `Ctrl` match the key (`logicalKey`), never `event.character`, which Windows may send
  as a control character or not at all.
- Keys are `Shortcuts` / `Actions` / `Intent`s built from the binding lists in
  `lib/ui/app_keys.dart`; the Help table is generated from the same lists. Plain keys are
  ignored while a text field has focus. `test/help_keys_test.dart` fails when a string in `lib/`
  spells out an `Alt+<digit>` instead of asking `Mode`.

## Mouse

- Every interactive element shows the pointer cursor and has a tooltip: rows, buttons, their
  labels, the mode rail.
- Single click selects a row (list keeps it in view), double click opens the file in the editor,
  right click opens the same menu as `i`.
- A path longer than the window is cut with an ellipsis; the row tooltip still holds the whole
  path.
- Shift + the wheel steps the cursor five rows at a time and keeps the list from scrolling; the
  plain wheel scrolls.
- A row reads folder first, then name, in two fixed shares of the row, so names line up under each
  other whatever the folder depths are.
- Every row carries two text actions between the folder and the name: **Add** (or **Untrack** when
  staged) and **Ignore**, each with the pointer cursor and a tooltip. A conflict shows only Ignore.
  The slot has a fixed width, so the file names stay aligned across rows.
- The list's top strip is the filter field with a **reload** button right after it; the button does
  exactly what `F5` does (re-read the state and the ignore files).

## Editor detection and Settings

- Order: the user's saved choice, then `nvim-qt` (PATH, then
  `%ProgramFiles%\neovim-qt*\bin\nvim-qt.exe`), then a **resolvable** `git var GIT_EDITOR`
  (skip `vi`/`vim` when no `vi` is on PATH — that is what this machine reports), then
  `VISUAL`, then `EDITOR`, then known editors on PATH (`code`, `nvim`, `gvim`, `notepad++`,
  `zed`, `hx`, `subl`, `cursor`, `idea64`), then `notepad`.
- Settings mode: the detected list with which one is in use, **Detect again**, a command field
  with `{file}` and `{line}` placeholders, and a **Test** button that opens this PLAN.md.
- Launching copies the Ops pattern (`lib/state/nvim_launcher.dart`): `where` to resolve, then
  `Process.start(..., mode: ProcessStartMode.detached)`, with `cmd /c start` for `.cmd` shims.
- The choice is stored in the app's own prefs file, not in git.

## Shape of the code

- `lib/ui/shell.dart` — mode rail, app-wide keys, gives the keyboard to the shown mode, and owns the
  repository it shows (Browse can replace it: a new `Repo`, `Changes`, ignore pane and scan).
- `lib/ui/` — `file_list.dart`, `filter_field.dart`, `ignore_dialog.dart`, `ignore_pane.dart`,
  `browse_view.dart`, `console_view.dart`, `notice_bar.dart`, `commit_bar.dart`, `settings_view.dart`,
  `help_view.dart` (with `keyTable`), `debug_bar.dart`, `theme.dart` (every colour and size),
  `nav_keys.dart`.
- `lib/state/` — `repo.dart` (the `git` package wrapper), `git_repo.dart` (the seam the UI talks to),
  `status.dart` (parser + model), `changes.dart` (sections, selection, optimistic actions),
  `browser.dart` (repository scan), `modes.dart` (the modes and their keys), `failure.dart` + `console.dart` + `diagnostics.dart` (reporting),
  `notices.dart`, `ignore_rules.dart`, `ignore_files.dart`, `editors.dart`, `prefs.dart`.
- Follow `~/ws/nvimos-ops/declarative_ui_guidelines.md`: ≤3 levels of inline layout nesting,
  `build` under 50 lines, lists from data with builders, no logic in event handlers.

## Style

One dark, flat, quiet sheet, as in Ops. **Normative: tokens only.** `lib/ui/theme.dart` (the `T`
class and the colour scheme) is the only place with a colour, a font size or family, a radius, an
icon size, a gap or a fixed height; a test greps `lib/ui/` for `fontSize:`, `fontFamily:`,
`Color(`, `Colors.` and `.withValues(`. A new look is a new token. The values below describe the
current palette and scales; they are not normative.

- Type: `T.body` 12.5, `T.small` 11.5, `T.tiny` 11, `T.section` 11 (spaced), `T.title` 13 bold,
  `T.code` 12 / `codeSmall` 11.5 / `codeTiny` 11 in Consolas (fallback Cascadia Mono). Nothing
  under 11 px.
- Radii 4 / 6 / pill; icons 14 / 16 / 20; gaps 2 / 4 / 6 / 8 / 12 / 16 / 24.
- Fixed heights: row 24, section header 30, pane header 32, commit bar 48, row action 20. The file
  list places rows by index, so the row and header heights are exact.
- Colours with a meaning: `chosen`, `cursor`, `current`, `hover`, `folder`. None carries the
  meaning alone: the cursor has its bar, a folder its trailing slash, a failure its code badge or
  icon.
- Hover is a palette colour, instant; nothing ripples (`NoSplash`).
- The pane that has the keys has an accent line on top; a text field that has them, its accent
  border.
- Text contrast at least 4.5:1 (`_muted` on the surface 5.8:1); a hairline is never the only
  boundary of a control.
- Every tooltip of an action that has a key names the key.

## Tests

- `dart_test.yaml`: `concurrency: 2`, `timeout: 22s`; `make test` passes the same.
- Tests and builds run **when asked**: the working rhythm in `CLAUDE.md` wins over any habit here.
- Parsers get unit tests with fixture strings, no git needed.
- Repo tests build a throwaway repo per test (`makeRepo()` helper), set `core.fsmonitor=false`,
  and register cleanup so no `purrage_*` folder survives a run.
- Widget tests use a fake clock: `pump(duration)`, no `pumpAndSettle` with real timers, and no real
  git or file I/O — `test/support/fake_repo.dart` plus `Shell(seeded:)` is the seam for that.
- `make analyze` clean apart from the known `material.dart` deprecation infos.

## References used

- `git` package 2.5.0 (kevmoo.com) — `GitDir`, `runCommand`, `isWorkingTreeClean`.
- Status semantics modelled on VS Code's git extension and GitHub Desktop
  (`--porcelain=v1 -z --untracked-files=all`, rename pairs, conflict codes).
- Ignore behaviour modelled on GitKraken Desktop docs (file/extension/directory scopes, root
  `.gitignore` only, tracked-file "ignore and stop tracking", conflicts ignore-only) and
  GitHub Desktop docs (Repository Settings → Ignored Files, and the three ignore destinations).
- Keys, mouse and code shape copied from `~/ws/nvimos-ops`.
