---
id: task-1
title: Time the actions before optimizing
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - perf
  - tooling
dependencies: []
priority: high
---

## Description

Ops measures before it optimizes (`lib/timing/ui_timing.dart`, `make timings`, `test/timing_measure_test.dart`).
Purrage has one `Stopwatch` in `Shell.reloadAll` and one in the browse scan, and nothing else.
The perf tasks (task-2 to task-6) need a number before and after.

Port `UiTiming` (span / sync / time, samples, summary, a state file in `%APPDATA%/Purrage/`,
on in debug and profile, off in release, `PURRAGE_TIMING=0|1` overrides). Give every action a
span named `<area>.<action>`: `changes.load`, `changes.refresh`, `changes.track`,
`changes.untrack`, `changes.ignore`, `changes.commit`, `changes.move`, `browse.scan`,
`ignorePane.load`, `ignorePane.focus`. Add a frame-to-screen phase the way Ops does.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `lib/timing/ui_timing.dart` exists, with tests for span, sync and summary
- [ ] #2 every Changes action and the browse scan records a span
- [ ] #3 `make timings` prints ms per action from the state file (WHICH=last|totals)
- [ ] #4 `test/timing_measure_test.dart` (a plain `test()`, FakeRepo) times move/track/ignore over 2,000 rows and prints the summary, so a perf change has a before and an after
<!-- AC:END -->
