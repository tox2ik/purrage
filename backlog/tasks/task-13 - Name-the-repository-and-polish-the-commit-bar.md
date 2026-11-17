---
id: task-13
title: Name the repository, and polish the commit bar
status: Done
assignee: []
created_date: '2026-11-17'
labels:
  - ui
  - usability
dependencies: []
priority: low
---

## Description

**Merge 19 of 21** · stack C · branch `PR-name-the-repository` · stacked on `PR-ignore-pane-follows`

After a switch in Browse, nothing in the Changes mode says which repository it shows. The window
title is always "Purrage", and the only path on screen is in the Browse list. With several
checkouts of the same project, that is how a commit lands in the wrong one.

- The window title becomes `<repo folder> - Purrage`, and the Changes header shows the path, plus
  the current branch, read-only (`git branch --show-current`, read with status). The plan rules
  out branch *operations*, not naming the branch.
- Commit bar:
  - `Ctrl+Enter` in the message commits. Enter already does (`onSubmitted`); keep both.
  - A summary over 72 characters gets a quiet counter.
  - After a commit, the keyboard goes back to the list.
  - The button reads `Commit 0` when nothing is staged. Make it `Commit`, with a tooltip that says
    why it is disabled.
  - The field is read-only when nothing is staged, but typing still looks possible. Show the
    reason as the hint.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 window title and header name the repository, and update on a Browse switch
- [x] #2 commit bar behaviour covered by widget tests (seeded FakeRepo)
<!-- AC:END -->

## Notes

- Header: `RepoHeader` at the top of Changes shows the path and `on <branch>` (or `detached
  HEAD`). The branch comes from the new `GitRepo.currentBranch()` (`git branch --show-current`),
  read in `Changes.load()` right after status; it never fails a load.
- Window title: `lib/ui/window_title.dart` sends the folder over a `purrage/window` channel, and
  the runner (`windows/runner/flutter_window.cpp`) sets `<folder> - <base title>`, keeping the
  `(dev)` / `(live)` suffix of a debug build. Shell calls it at start and after a Browse switch.
  A widget test checks the channel call.
- The runner change compiles: `flutter build windows --debug` built
  `build\windows\x64\runner\Debug\purrage.exe` (the first try failed on a full disk), and again
  after the join. **Left for the user**: a look at the real window title at start and after a
  Browse switch; no test can see the native title.
- Joined onto A+B: the title follows `Workspace` (Shell names the window at start and whenever
  the workspace's repository changes); the commit bar keeps B's status-only listener and A's
  `Clickable`; after a commit the keys go to the file list; a refused commit is said by
  `Workspace.report` (A's `ActionResult.refused`).
- Commit bar: `Commit` with no count when nothing is staged; the tooltip and the field hint say
  why it is disabled (`Changes.commitBlockedReason`). Ctrl+Enter commits (Enter still does), a
  summary over 72 characters shows `73/72`, and after a commit the keys go back to the list.
  An empty or blocked commit now says why instead of "commit failed".
- Tests: `test/commit_bar_test.dart` (7 tests) passes; after the join the whole suite passes.
