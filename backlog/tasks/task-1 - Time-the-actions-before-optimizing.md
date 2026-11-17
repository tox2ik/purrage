---
id: task-1
title: Time the actions before optimizing
status: Done
assignee: []
created_date: '2026-11-17'
labels:
  - perf
  - tooling
dependencies: []
priority: high
---

## Description

**Merge 7 of 21** · stack B · branch `PR-time-the-actions` · stacked on `PR-keys-every-mode` (built on `main`, rebased onto stack A when the stacks are joined)

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
- [x] #1 `lib/timing/ui_timing.dart` exists, with tests for span, sync and summary
- [x] #2 every Changes action and the browse scan records a span
- [x] #3 `make timings` prints ms per action from the state file (WHICH=last|totals)
- [x] #4 `test/timing_measure_test.dart` (a plain `test()`, FakeRepo) times move/track/ignore over 2,000 rows and prints the summary, so a perf change has a before and an after
<!-- AC:END -->

## Notes

- Spans: `changes.load`, `.refresh`, `.track`, `.untrack`, `.ignore`, `.commit`, `.move`,
  `browse.scan`, `ignorePane.load`, `ignorePane.focus`. Actions mark `optimistic` (rows moved),
  `frame` (that frame is on screen), `git`; ignore also `check`. `changes.move/frame` is the
  key-to-screen phase; `UiTiming.start()` adds `input.click→frame` and `input.key→frame`.
- The state file is read and written async (no `*Sync`), ahead of task-6's grep.
- `make measure` runs the measure test. Besides the plain `test()` it has one `testWidgets` that
  pumps `ChangesView` (FakeRepo, no I/O) so `changes.move/frame` has a number.
- Baseline at 2,000 rows (this machine, debug): `changes.move` p50 0.0 ms state,
  `changes.move/frame` p50 ~98 ms, p95 ~200-250 ms; `changes.track` p50 ~26-41 ms;
  `changes.untrack` (300 rows) ~55-87 ms; `changes.ignore` (300 rows) p95 ~140-150 ms.
- Open: the summary is flushed every minute by a `Timer.periodic` (as Ops does). It writes a
  file, it does not poll git, so it does not break the "no timers" rule; it is off in release.
