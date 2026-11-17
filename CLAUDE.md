# Purrage

Flutter Windows app: `git status` as a list, track or ignore each file, commit. `PLAN.md` is the
spec; where it and the code disagree, fix one of them deliberately.

Repo layout: `lib/ui/` is presentation, `lib/state/` is the work (`ChangeNotifier`, testable
without widgets). Project management lives here too: `backlog/` (Backlog.md tasks) and
`openspec/` (changes that need a design).

## Working rhythm (the user's rules, learned the hard way)

- **Do not run the test suite or build unless asked.** Edit, then `flutter analyze` (a few
  seconds) as the compile check, then commit. Build (`make build`, `flutter build windows --debug`)
  and tests (`make test`) happen when the user says so, or when a change cannot be verified any
  other way — say which and why.
- **Change files with the `edit` and `write` tools, never with a shell string replacement.** A
  PowerShell `.Replace` on `-Raw` content does not preserve line endings, expands `$name` in the
  replacement, and turns a backticked `r` into a carriage return; each of those wrote broken Dart
  here. The shell runs commands and reads state, nothing else.
- One commit per feature, `area: what changed`, body says why, `Co-Authored-By: agent
  <agent@it-agent.no>`. Push only when the user asks.
- Planned work is in `backlog/tasks/` (map: `backlog/docs/doc-1 - Review-2026-11-17.md`) and
  is done in a worktree per task, in its own session, created from the **local** `main`
  (`git worktree add -b <branch> <path> main`), never `origin/main`: local main has commits that
  are not pushed. Plans and suggestions themselves go on `main`.
- Stacked branches: each task is one `PR-<slug>` branch, started from the branch before it in
  the stack, and its commits carry `Stacked-On: PR-<previous>`. Each task file opens with its
  merge position (`Merge N of 21`); merge in that order, which is then a fast-forward each time.
- The user reads code; do not paste diffs into the chat. Report what changed and where.

## Commands

`make help` lists the targets (pwsh, Windows):

- `make run`: `flutter run -d windows` against the folder it was started in
- `make live`: the same, on your home folder (`-a "$(USERPROFILE)"`, the app's first argument),
  with everything written to `out/live.log` (a new file per run)
- `make build`: release build, `build\windows\x64\runner\Release\purrage.exe`
- `make test`: the whole suite, two files at a time (`concurrency: 2`)
- `make analyze`: `flutter analyze`
- `make format`: `dart format lib test`

Flutter is discovered by the Makefile (`make where` prints the pair it picked): it tries
`H:/flutter`, `C:/tools/flutter`, `C:/flutter`, `D:/flutter`, `%USERPROFILE%/flutter` and
`%LOCALAPPDATA%/flutter`, and only falls back to plain `flutter`/`dart` from `PATH`. That is why
`make live` works from Neovim, whose PATH does not have Flutter on it. Recipes use the call
operator (`& "$(FLUTTER)" …`) because a quoted `.bat` path is not a command in `pwsh`.

## Running tests

- `dart_test.yaml` sets `concurrency: 2` and `timeout: 22s`; `make test` passes `--timeout 22s`
  too (keep the two equal). **Every test runs with a 22 second timeout** — never wait on a test
  that hangs, and a test that genuinely needs longer sets its own `timeout:` explicitly.
- The timeout cannot save a `testWidgets` that waits on real I/O. Widget tests run on a fake clock,
  and a body parked in `tester.runAsync` (or on a real `Future.delayed`) leaves the runner's own
  timer advancing nowhere: the test hangs past the timeout and has to be killed. So:
  - never drive git, sockets or file watchers from a widget test;
  - parser and state tests are plain `test()`s, repo tests use a throwaway repo in a plain
    `test()` (`makeRepo()`), and a widget test gets a state object already built from fixtures.
- If a test does hang, kill it: `Get-Process flutter_tester,dart | Stop-Process -Force`; `Ctrl+C`
  in the running terminal is not enough once the fake clock owns the timers.
- A test cleans up after itself: temp repos go through the `makeRepo()` helper in
  `test/support/`, which registers cleanup, and they set `core.fsmonitor=false`. After a run the
  count of `purrage_*` folders in `%TEMP%` is the same as before.
- Parser tests use fixture strings and need no git at all.
- `test/support/fake_repo.dart` implements `GitRepo` in memory; `Shell(repo: …, seeded: changes)`
  makes the real shell drivable without git, files or a clock.

## UI code

- Follow `~/ws/nvimos-ops/declarative_ui_guidelines.md`: at most 3 levels of inline layout
  nesting, `build` under 50 lines (extract named sub-widgets), lists from data with builders, no
  logic inside event handlers (call a named method on the state object).
- A view is a page (State) with named event handlers; the work lives in a `ChangeNotifier` under
  `lib/state/`, which tests drive without widgets.
- Interactive items get the pointer cursor and a tooltip, explicitly, not by trusting a default.
  A label is part of its control: clicking the text does what the control does.
- Colours and sizes come from `lib/ui/theme.dart` (near-black surface, one indigo accent, hairline
  dividers, compact density). Do not introduce a raw colour in a widget; add a token instead.
  `colorScheme.outline` is a *line* colour — text uses `onSurface` / `onSurfaceVariant`.
- The list is a `ListView.builder` over a flat list of headers and rows. A rebuild must cost the
  visible tiles, never every row in the repo.
- Row actions are text (`Add`/`Untrack`, `Ignore`) in a fixed slot between the folder and the name,
  and they call the shell, which reports; they must never call `Changes` directly, or a failure
  has nowhere to go.

## Responsiveness (the app must feel instant)

- **Actions are optimistic**: `track`, `untrack`, `ignore` move or remove the rows first, run git
  behind them, and restore the previous list on failure. A click is a redraw, not a round trip.
- **No timers, no polling.** Nothing reads `git status` on an interval. Refresh happens after an
  action, and on `r` / `F5` / `Ctrl+R`. A refresh whose result equals the current list does not
  redraw.
- **Never run git from a cursor move.** The ignore pane's `git check-ignore` is debounced 250 ms
  after the cursor settles; that subprocess per keypress was the sluggish navigation.
- Reveal scrolls only when the focused row is outside the viewport; re-centring every step makes
  the list drag behind the cursor.

## Reporting and the Console mode

- `Changes` keeps `lastFailure` (`ActionFailure`: summary, detail, code, origin, error flag) plus
  `lastCommand`, `lastOrigin`, `lastChanged`, set by every action.
- `Shell.say()` shows a notice **and** adds a console row; `Shell.report()` adds a console row for
  successes. Both go through `ActionFailure`, so the notice and the console never disagree.
- The notice bar (`lib/state/notices.dart`, `lib/ui/notice_bar.dart`) pauses its countdown while
  the mouse is over it. Successes say nothing on screen; failures always speak, with the file and
  the reason.
- The Console mode (`Alt+4`) is newest-first: time, code badge, action, summary, and an expandable
  detail with the origin chain, parameters, `cwd` and the command line.
- A refusal is a failure: "`es/x/` is already ignored by `/es/` in `.gitignore:135`". Never return
  silently — a no-op that looks like a success is the worst outcome.

## Keys and mouse

- The Ops contract, copied: `navKey(event)` for Up/Down and `j`/`k`/WASD, Tab/Shift+Tab between
  panes with wrapping, plain keys ignored while a text field has focus.
- Selection is the contract: `Shift+Up/Down` extends from the anchor, `Ctrl+Enter` toggles the
  cursor row, `Ctrl`/`Shift` click do the same with the mouse, and **every action acts on the
  highlighted rows** (no silent fallback to the cursor). Rows that are chosen are tinted; the
  cursor keeps its accent bar.
- Modes: `Alt+1` Changes, `Alt+2` Browse, `Alt+3` Settings, `Alt+4` Console, `Alt+5` Help;
  `Alt+]` / `Alt+[` cycle. The number lives only in the `Mode` enum (`lib/state/modes.dart`); the
  key map, the help table, the rail tooltips and every "(Alt+N)" in a message are built from it.
- A new key goes into two places: a `Binding` in `lib/ui/app_keys.dart` (the `Shortcuts` and the
  Help table are both built from it) and the Keys section of `PLAN.md`.
- The debug bar (bug button, bottom right) names the focused element by its role and shows the
  last key and mouse event.

## Git

- Access goes through the `git` package (`GitDir.runCommand`), never `Process.run('git', ...)`
  spread around the code; one wrapper in `lib/state/repo.dart`. The calls that need stdin or raw
  UTF-8 go through its `ProcessRunner` instead: `status()` (`-z` output), `checkIgnoreAll()`
  (paths on stdin) and `commit()` (the summary on stdin, `git commit -F -`, so a summary can never
  be read as an option).
- Status is one call: `git status --porcelain=v1 -z --untracked-files=all --find-renames`; the
  parser in `lib/state/status.dart` owns the format and is unit-tested with fixtures.
- Ignore rules are written literally and anchored, escaped, deduplicated, with the file's line
  endings preserved, into the file's **`# Purrage` section**: right after its last rule, **no
  blank line between rules**, the section appended at the end when missing. Never write an
  over-broad glob.
- Track, Untrack and Ignore are discrete actions with no confirm dialogs. Untrack is always
  `--cached`: **never remove a file from disk**.
- `git check-ignore -v` output is `<source>:<line>:<pattern>\t<path>` and `<source>` starts with a
  drive letter on Windows: parse from the right (`^(.*):(\d+):(.*)$`), never at the first colon.
- **Never pass a trailing slash to `check-ignore`**: `git status` prints an untracked directory as
  `dir/`, and `git check-ignore -v -- dir/` then answers with an empty pattern and the last line it
  scanned, i.e. a match that does not exist, while `dir` and `git status` agree it is untracked.
  Strip the slash first, and treat an empty pattern as "no rule" as well.
- Never stage with `-a`, never run a command that can lose work: the app has no confirm dialogs,
  so such a command has no place in it.

## Windows quirks this app already handles

- **Hidden/System files cannot be overwritten**: `CreateFileW(CREATE_ALWAYS)` returns
  `ERROR_ACCESS_DENIED` (errno 5) for a Hidden file, which is why every dot file here (`.gitignore`,
  `.config/git/ignore`, `.git/info/exclude`) failed. `Repo.writeTextFile` tries the plain write
  first, then clears `H`/`S` with `attrib`, re-reads to confirm, writes, and restores exactly the
  flags that were set — the same repair as `~/AppData/Local/nvim/plugin/hidden-write.lua`.
- `where <name>` may list a `.bat` wrapper before the real `.exe`; a `.bat` has to start through
  `cmd /c start`, which shows a console. Prefer `.exe`, then `.cmd`/`.bat`, then anything.
- Editor order: saved choice, `nvim-qt`, a *resolvable* `git var GIT_EDITOR` (skip `vi` without
  `vi` on PATH), `VISUAL`, `EDITOR`, known editors, Notepad. `tool/editors_probe.dart` prints the
  result without starting the app.
