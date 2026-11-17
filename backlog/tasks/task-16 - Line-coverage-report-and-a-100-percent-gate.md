---
id: task-16
title: Line coverage report and a 100% gate
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - tests
  - tooling
dependencies:
  - task-14
  - task-15
priority: high
---

## Description

**Merge 20 of 21** · stack D · branch `PR-coverage-gate` · stacked on `PR-name-the-repository` (started after the three stacks are joined, so it covers the final code)

Design: `openspec/changes/test-coverage-and-integration/`. This task is the unit test half:
the tooling, the exclusion policy, and the missing tests file by file, until `make coverage`
reports 100% of the lines that are not excluded.

Baseline (2026-11-17, `flutter test --coverage`) and the per-file gaps are in
`backlog/docs/doc-1 - Review-2026-11-17.md`.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `make coverage` runs the suite with `--coverage` and prints one line per file under 100% (terse, action-first, per the script output rules), nothing for covered files
- [ ] #2 `tool/coverage.dart` reads `coverage/lcov.info` with no extra package, honours `// coverage:ignore-line`, `-start/-end` and `-file`, and exits non-zero below the threshold (`MIN=100`)
- [ ] #3 every exclusion has a reason on the same line; `make coverage` lists the exclusions as well, so they stay few
- [ ] #4 every file in `lib/` is at 100% of its non-excluded lines
- [ ] #5 `coverage/` is in `.gitignore`
<!-- AC:END -->
