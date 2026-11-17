---
id: task-18
title: Lints, pubspec and plan drift
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - chore
  - docs
dependencies: []
priority: low
---

## Description

Small things, one commit each:

- **Lints**: add `unawaited_futures`, `discarded_futures`, `prefer_final_locals`,
  `always_declare_return_types`, `avoid_void_async` to `analysis_options.yaml`. `move`, `click`,
  `extendSelection`, `toggleFocused`, `selectAll` and `setFilter` are `Future<void> async` and do
  nothing asynchronous. Every call site drops the future. Make them `void`.
- **pubspec**: `cupertino_icons` is unused, and the description is still "A new Flutter
  project.". The template comments can go.
- **Makefile**: `test` says "one file at a time", but `dart_test.yaml` runs `concurrency: 2`.
- **PLAN.md vs the code**, fix one side deliberately:
  - Commit: PLAN says `git commit -F -`, `Repo.commit` runs `-m`. `-F -` with stdin is the
    safer one for any summary text.
  - Ignore writes: PLAN says "append after one blank line with a `# Purrage` comment", CLAUDE.md
    and the code say no blank line, header only in a new file.
  - Untrack confirmation: see task-12.
  - PLAN "Shape of the code" has no `lib/timing/` and no `workspace.dart` yet (after task-1/14).
- **Formatting**: `file_list.dart:462` and `changes_view.dart:495` have two declarations on one
  line, and `repo.dart:198` a statement after `{`. Run `make format`.
- **Stray files**: `purrage.exe` in the repo root and `tool/*_probe.dart`. Are the probes still
  wanted? If they are, exclude them from analysis and coverage.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `make analyze` clean with the new lints
- [ ] #2 PLAN.md, CLAUDE.md and the code agree on commit, ignore append and untrack
<!-- AC:END -->
