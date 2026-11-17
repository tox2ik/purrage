---
id: task-17
title: Integration tests for the critical flows on Windows
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - tests
dependencies:
  - task-19
priority: high
---

## Description

Design: `openspec/changes/test-coverage-and-integration/`. This task is the integration half:
`integration_test/` driving the real app on `-d windows` against throwaway repositories, real git,
real files and real keys, run locally with `make itest`.

The flows to cover are listed in the design (start, track, untrack, quick ignore, ignore dialog
into a nested file, a hidden `.gitignore`, commit, a failure reaching the notice and the console,
Browse switching, filter and multi-select).

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `make itest` builds once and runs every flow in `integration_test/` on Windows
- [ ] #2 each flow asserts the screen and git's own answer (`git status`, file contents)
- [ ] #3 no `purrage_*` folder and no git fsmonitor daemon is left behind (checked by the target)
- [ ] #4 the whole run takes under 3 minutes; a hang is killed by the per-test timeout
<!-- AC:END -->
