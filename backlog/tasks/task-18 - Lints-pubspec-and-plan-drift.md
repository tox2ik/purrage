---
id: task-18
title: Lints, pubspec and plan drift
status: Done
assignee: []
created_date: '2026-11-17'
labels:
  - chore
  - docs
dependencies: []
priority: low
---

## Description

**Merge 15 of 21** · stack C · branch `PR-lints-plan-drift` · stacked on `PR-mode-keys-source`

Small things, one commit each. Decisions from the user on 2026-11-17 are marked **Decided**.

- **Lints** (**Decided**: all five): add `unawaited_futures`, `discarded_futures`,
  `prefer_final_locals`, `always_declare_return_types`, `avoid_void_async` to
  `analysis_options.yaml`, and fix what they flag. The template comments in that file can go.
- **Selection methods** (**Decided**: make them `void`): `move`, `click`, `extendSelection`,
  `toggleFocused`, `selectAll` and `setFilter` are `Future<void> async` and do nothing
  asynchronous. Every call site drops the future.
- **pubspec**: `cupertino_icons` is unused, and the description is still "A new Flutter
  project.". The template comments can go.
- **Makefile**: `test` says "one file at a time", but `dart_test.yaml` runs `concurrency: 2`.
- **PLAN.md vs the code**, fix one side deliberately:
  - Commit (**Decided**: the code changes): PLAN says `git commit -F -`, `Repo.commit`
    (`repo.dart:107`) runs `-m`. Pipe the message on stdin, so a summary can never be read as an
    option. PLAN stays.
  - Ignore writes (**Decided**: both change). PLAN says "append after one blank line with a
    `# Purrage` comment"; the code and CLAUDE.md say no blank line, header only in a new file;
    the doc comment on `appendIgnoreLine` says "one blank line". The rule from now on:
    - every ignore file the app writes to has a **`# Purrage` section**: the `# Purrage` line and
      the app's rules right under it;
    - a new rule goes **directly after the section's last rule**, one per line, **no blank
      lines** between them, even when other rules follow the section further down;
    - a file without the section gets `# Purrage` appended at its end, then the rule. A new file
      is just the section. Line endings and the final newline are kept, as today;
    - a rule already present anywhere in the file is still a duplicate.
    PLAN.md "Actions", CLAUDE.md "Git" and the doc comment say the same; repo tests cover a file
    without the section, with it at the end, with it in the middle, and CRLF.
  - Untrack and "Ignore + stop tracking": decided, see task-12 (three discrete actions, no
    dialog, grouped notice).
  - PLAN "Shape of the code" has no `lib/timing/` and no `workspace.dart` yet (after task-1/14).
- **Formatting**: `file_list.dart:462` and `changes_view.dart:495` have two declarations on one
  line, and `repo.dart:198` a statement after `{`. Run `make format`.
- **Probes** (**Decided**: keep all five, as study material for learning Flutter and Dart). Each
  one in `tool/`:
  - takes its inputs as arguments, with no hard-coded paths or filters. The old values
    (`es/buss-sjekk/`, `hs/it-agent/`, the `mattpocock` and `es/` filters) move into the header
    comment as usage examples;
  - gets a short "why this exists" paragraph: the bug it was written to hunt and the commit that
    fixed it (`6f3f52f` trailing slash for `checkignore_`; `3be68ca` untrack for `untrack_`;
    the nested-repo marker for `nested_`; the empty-pattern refusal for `ignore_`; "Open in
    editor" for `editors_`);
  - is excluded from coverage (task-16), not from analysis.
  `purrage.exe` in the root is already ignored (`.gitignore:53`); nothing to do.
- **Two repo tests from the probes** (**Decided**), in `test/repo_test.dart`, so `make test`
  asserts what the probes only print:
  - *ignore an untracked nested repository* (from `ignore_probe`): `git check-ignore` answers
    with an empty pattern; the rule must be written and `git status` must no longer list the
    folder. Guards against the false "already ignored" refusal coming back.
  - *untrack a nested repository* whose staged content differs from HEAD and the disk (from
    `untrack_probe`): plain `git rm --cached` refuses, the app retries with `-f --cached`. The
    row must leave Staged, and **the folder and its files must still be on disk**. Guards
    against untrack failing on nested repositories, and against any change that would delete
    files (the user's top priority, task-12).

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `make analyze` clean with the five new lints; the six selection methods are `void`
- [x] #2 `Repo.commit` uses `git commit -F -`
- [x] #3 ignore appends follow the `# Purrage` section rule, with repo tests for the four shapes
- [x] #4 PLAN.md, CLAUDE.md and the code agree on commit, ignore append and untrack
- [x] #5 the five probes take arguments, keep the old paths as examples, and say which bug they hunted
- [x] #6 the two nested-repository repo tests exist and pass; the untrack one checks the folder on disk
<!-- AC:END -->

## Notes

- Lints: the five rules are on; only `discarded_futures` fired (shell key handlers, `initState`
  in shell / browse / settings), each now an explicit `unawaited(...)` or a named async method.
  The six selection methods are `void`; two tests dropped their `await`.
- Commit: `Repo.commit` runs `git commit -F -` through the `ProcessRunner` (stdin), like
  `checkIgnoreAll`; CLAUDE.md "Git" says so. Repo test: a summary starting with `--amend` is
  committed as text.
- Joined onto stacks A+B: the selection methods became `void` again on top of B's timing (the
  tests that awaited them were changed), `appendIgnoreLines` (B's one write per file) folds
  `IgnoreRules.appendToSection` over its patterns, and the probe and nested test call A/B's
  `untrack([...])`.
- Ignore section: `IgnoreRules.appendToSection` (pure, unit-tested) does the work,
  `Repo.appendIgnoreLine` reads and writes. Repo tests: no section, section at end, section in
  the middle, CRLF with no final newline, duplicate outside the section.
- Probes: each requires its arguments (exit 64 with usage otherwise), the old values are in the
  header as examples, and each says the bug and commit. Coverage exclusion waits for task-16.
- Nested-repository repo tests: the untrack one makes the staged gitlink differ from HEAD and
  disk, asserts `git rm --cached -f -- inner` ran, and that the folder, its `.git` and its file
  (with the newest content) are still on disk.
- **Formatting, for the user to decide**: `make format` with this SDK (tall style, 80 columns)
  rewrote 40 files, while the code is written at ~100 columns. That would conflict with every
  file stacks A and B touch, so I fixed the slips by hand instead (`file_list.dart` `RowEntry`,
  `ignore_rules.dart` `_folderOf`, `repo.dart` `appendIgnoreLine`) and did not run it. The
  `changes_view.dart:495` slip does not exist (the file has 135 lines). Suggest: after the stacks
  are joined, add `formatter: page_width: 100` to `analysis_options.yaml` and run `make format`
  once, as its own commit.
- PLAN "Shape of the code": `lib/timing/` and `workspace.dart` belong to task-1 / task-14 (stacks
  B and A); nothing to add on this stack.
- CLAUDE.md "never run a command that can lose work without a confirm dialog" now reads "…the
  app has no confirm dialogs", to agree with the decision.
