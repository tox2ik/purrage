# Glustered

Flutter Windows app: `git status` as a list, track or ignore each file, commit. `PLAN.md` is the
spec; where it and the code disagree, fix one of them deliberately.

Repo layout: `lib/ui/` is presentation, `lib/state/` is the work (`ChangeNotifier`, testable
without widgets). Project management lives here too: `backlog/` (Backlog.md tasks) and
`openspec/` (changes that need a design).

## Commands

`make help` lists the targets (pwsh, Windows):

- `make run`: `flutter run -d windows` against the folder it was started in
- `make live`: the same, on your home folder (`-a "$(USERPROFILE)"`, the app's first argument),
  with everything written to `out/live.log` (a new file per run)
- `make build`: release build, `build\windows\x64\runner\Release\glustered.exe`
- `make test`: the whole suite, one file at a time
- `make analyze`: `flutter analyze`
- `make format`: `dart format lib test`

Flutter is discovered by the Makefile (`make where` prints the pair it picked): it tries
`H:/flutter`, `C:/tools/flutter`, `C:/flutter`, `D:/flutter`, `%USERPROFILE%/flutter` and
`%LOCALAPPDATA%/flutter`, and only falls back to plain `flutter`/`dart` from `PATH`. That is why
`make live` works from Neovim, whose PATH does not have Flutter on it.

## Running tests

- `dart_test.yaml` sets `concurrency: 1` and `timeout: 55s`. A test that needs longer sets its
  own `timeout:`.
- Run only the files that cover the change while iterating, the whole suite before a commit.
- Widget tests run on a fake clock: `pump(duration)`, no `pumpAndSettle` with a real timer.
- A test cleans up after itself: temp repos go through the `makeRepo()` helper in
  `test/support/`, which registers cleanup, and they set `core.fsmonitor=false`. After a run the
  count of `glustered_*` folders in `%TEMP%` is the same as before.
- Parser tests use fixture strings and need no git at all.

## UI code

- Follow `~/ws/nvimos-ops/declarative_ui_guidelines.md`: at most 3 levels of inline layout
  nesting, `build` under 50 lines (extract named sub-widgets), lists from data with builders, no
  logic inside event handlers (call a named method on the state object).
- A view is a page (State) with named event handlers; the work lives in a `ChangeNotifier` under
  `lib/state/`, which tests drive without widgets.
- Interactive items get the pointer cursor and a tooltip, explicitly, not by trusting a default.
  A label is part of its control: clicking the text does what the control does.
- Errors: a failed load shows `ErrorPane` in place of the view, a failed action shows
  `showActionError` with the git text behind Details.

## Keys and mouse

- The Ops contract, copied: `navKey(event)` for Up/Down and `j`/`k`/WASD, `KeySequence` for
  two-key commands, Tab/Shift+Tab between panes with wrapping, plain keys ignored while a text
  field (the filter, the commit summary) has focus.
- A new key goes into three places: the handler, `keyTable` in `lib/ui/help_view.dart` (Help
  mode), and the Keys section of `PLAN.md`.
- The debug bar (bug button, bottom right) names the focused element by its role and shows the
  last key and mouse event.

## Git

- Access goes through the `git` package (`GitDir.runCommand`), never `Process.run('git', ...)`
  spread around the code; one wrapper in `lib/state/repo.dart`.
- Status is one call: `git status --porcelain=v1 -z --untracked-files=all --find-renames`; the
  parser in `lib/state/status.dart` owns the format and is unit-tested with fixtures.
- Ignore rules are written literally and anchored, escaped, deduplicated, and appended with the
  file's line endings preserved. Never write an over-broad glob.
- Never stage with `-a`, never run a command that can lose work without a confirm dialog.

## Git history

- Commit per feature, message `area: what changed` (lowercase area, no trailing period), the body
  says why, and end with `Co-Authored-By: agent <agent@it-agent.no>`.
- Push only when the user asks.
