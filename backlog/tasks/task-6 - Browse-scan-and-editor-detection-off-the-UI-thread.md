---
id: task-6
title: Browse scan and editor detection off the UI thread
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - perf
dependencies:
  - task-1
priority: medium
---

## Description

`RepoBrowser._scan` (`lib/state/browser.dart:235`) runs on the UI isolate. It already yields every
8 directories, but:

- `queue.removeAt(0)` on a `List` is O(n), and the queue reaches thousands of entries on a home
  folder: use `Queue` from `dart:collection`.
- `FileSystemEntity.isLinkSync(child.path)` is a synchronous stat per child, on the UI thread.
  `Directory.list(followLinks: false)` already returns links as `Link`, so `child is! Directory`
  covers them. Check that a junction comes back as `Link` on Windows, and drop the sync call.
- Nothing shows until the whole walk ends. Publish found repositories as they come (notify at most
  every 100 ms).
- A new `goTo`/`up` during a scan sets `_again`, but the old walk runs to the end first (up to
  20,000 directories). A new directory should cancel the old walk.
- Better: run the walk in `Isolate.run`, and send back found paths and the report. The UI isolate
  then does no file system work for Browse at all.

`Editors` detection uses `File.existsSync` and `Directory.listSync` over `Program Files`
(`lib/state/editors.dart:372`, `:402`), on the UI isolate, when Settings opens. Make them async.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 no `*Sync` file system call is left in `lib/` (a grep in a test, or a lint)
- [ ] #2 Browse shows the first repositories before the scan ends
- [ ] #3 `up` during a scan cancels it; a test with a fake directory lister checks it
- [ ] #4 the scan report still names the slowest and widest listings
<!-- AC:END -->
