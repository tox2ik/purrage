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

## The status model

- One call: `git status --porcelain=v1 -z --untracked-files=all --find-renames`, run through
  `GitDir.runCommand` so quoting, worktree paths and error text are handled once.
- Rows are split into sections, in this order: **Conflicts**, **Staged**, **Changed**,
  **Untracked**. A file can appear once per section (staged and changed are different rows, as
  in VS Code and GitHub Desktop).
- Parsing rules: `XY path` per record; `-z` means rename pairs arrive as two NUL-separated
  paths (new, then old); codes are `M A D R C T U` per column; the conflict codes
  `DD AU UD UA DU AA UU` go to Conflicts with a readable label.
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
- **Untrack** (`u`): `git rm --cached -- <path>`; confirm first, and say in the dialog that the
  file stays on disk.
- **Ignore** (`i`, row menu): scope submenu — *this file* (`/path/to/file`), *this extension*
  (`*.ext`), *this folder* (`/path/to/folder/`) — and a *where* submenu: the repo root
  `.gitignore` (default), **a new `.gitignore` in the file's own folder**, `.git/info/exclude`,
  or the global ignore file.
- **Ignore + stop tracking** for a row that git already tracks: ignore rule plus
  `git rm --cached`, confirm dialog, mirroring GitKraken's two-step.
- Ignore writes are literal and anchored, escape glob characters (`*?[]!`) in names, skip a
  pattern already present, append after one blank line with a `# Purrage` comment and keep the
  file's existing line endings and final newline.
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

## Keys (the Ops contract)

- Modes: `Alt+1` Changes, `Alt+2` Settings, `Alt+3` Help; `Alt+]` / `Alt+[` cycle; `?` opens Help.
- Motion: Up/Down, `j`/`k`, and WASD via the shared `navKey(event)`; never bound per handler.
- Selection: `Shift`+Up/Down grows the highlight from the anchor, one row per press; `Ctrl+Enter`
  turns the cursor row's highlight on or off. The highlighted rows are what every action changes,
  keyboard or mouse. A success says nothing: the row moving between sections is the feedback. A
  refusal or a failure is said every time, with the file and the reason.

- Actions: `space` or `a` track (`git add`), `u` untrack, `i` ignore with the literal path, `Shift+I` the ignore
  dialog, `e` open file, `E` open `.gitignore`, `c` commit, `r` refresh, `/` filter, `Esc` close.
- Two-key commands go through `KeySequence`; plain keys are ignored while a text field has
  focus; every key is also listed in the Help table.

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
- Row-end buttons appear on hover: track, ignore (the literal path, no dialog), open. Right click
  opens the ignore dialog instead. File rows use the pointer cursor; there
  is no `SelectionArea` in the list.

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

- `lib/ui/shell.dart` — mode rail, app-wide keys, gives the keyboard to the shown mode.
- `lib/ui/` — `file_list.dart`, `filter_field.dart`, `ignore_dialog.dart`, `commit_bar.dart`,
  `settings_view.dart`, `help_view.dart` (with `keyTable`), `nav_keys.dart`, `key_sequence.dart`,
  `hover_row.dart`, `reveal.dart`, `error_view.dart`, `debug_bar.dart`, `confirm_dialog.dart`.
- `lib/state/` — `repo.dart` (the `git` package wrapper), `status.dart` (parser + model),
  `changes.dart` (ChangeNotifier: sections, selection, actions), `ignore_rules.dart`,
  `editors.dart`, `prefs.dart`, `timing.dart`.
- Follow `~/ws/nvimos-ops/declarative_ui_guidelines.md`: ≤3 levels of inline layout nesting,
  `build` under 50 lines, lists from data with builders, no logic in event handlers.

## Tests

- `dart_test.yaml`: `concurrency: 2`, `timeout: 55s`.
- Parsers get unit tests with fixture strings, no git needed.
- Repo tests build a throwaway repo per test (`makeRepo()` helper), set `core.fsmonitor=false`,
  and register cleanup so no `purrage_*` folder survives a run.
- Widget tests use a fake clock: `pump(duration)`, no `pumpAndSettle` with real timers.
- `make analyze` clean apart from the known `material.dart` deprecation infos.

## References used

- `git` package 2.5.0 (kevmoo.com) — `GitDir`, `runCommand`, `isWorkingTreeClean`.
- Status semantics modelled on VS Code's git extension and GitHub Desktop
  (`--porcelain=v1 -z --untracked-files=all`, rename pairs, conflict codes).
- Ignore behaviour modelled on GitKraken Desktop docs (file/extension/directory scopes, root
  `.gitignore` only, tracked-file "ignore and stop tracking", conflicts ignore-only) and
  GitHub Desktop docs (Repository Settings → Ignored Files, and the three ignore destinations).
- Keys, mouse and code shape copied from `~/ws/nvimos-ops`.
