---
id: task-8
title: Say loading while loading, not "working tree clean"
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - bug
  - ui
dependencies: []
priority: medium
---

## Description

`FileList.build` shows "Nothing to commit, working tree clean." whenever `changes.rows` is empty
(`lib/ui/file_list.dart:86`), including before the first `git status` has answered and after a
load that failed. On a big repository, or a home folder (`make live`), the first thing on screen is
a false statement. After switching repositories in Browse it is shown for the new checkout until
its status arrives.

Make the empty state depend on what is known: before the first load, a quiet "reading git status…"
line (no spinner flash under 150 ms); after a failed load, the error banner and nothing else; only
after a successful load with no rows, "working tree clean". The nested-repository probe
(`Changes._scanNested`) also notifies when it found nothing new: notify only when the set grew.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `Changes` has a `loaded` (or a load state enum) the view reads
- [ ] #2 widget tests: a FakeRepo whose status is held open shows the loading line, a failing one shows only the banner, an empty one shows "working tree clean"
- [ ] #3 `_scanNested` does not notify when no nested repository was found
<!-- AC:END -->
