---
id: task-6
title: Browse scan and editor detection off the UI thread
status: Done
assignee: []
created_date: '2026-11-17'
labels:
  - perf
dependencies:
  - task-1
priority: medium
---

## Description

**Merge 12 of 21** · stack B · branch `PR-scan-off-ui-thread` · stacked on `PR-list-only-redraw`

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
- [x] #1 no `*Sync` file system call is left in `lib/` (a grep in a test, or a lint)
- [x] #2 Browse shows the first repositories before the scan ends
- [x] #3 `up` during a scan cancels it; a test with a fake directory lister checks it
- [x] #4 the scan report still names the slowest and widest listings
<!-- AC:END -->

## Notes

- The walk stays on the UI isolate, made cheap and cancellable: a `Queue` instead of
  `List.removeAt(0)`, no `isLinkSync` (checked by hand: with `followLinks: false` a Windows
  junction lists as `Link`; task-15's `DirEntry.isLink` carries it), found repositories
  published at once and then at most every 100 ms, and a generation number so a scan of another
  directory (`up`, `goTo`, a drive) stops the old walk at its next step (it emits no report).
- Joined onto stack A: a request for the directory already being walked still joins that walk
  (A's `idle()` handle and its test); the old "scan again at the end" fold-in is gone. `idle()`
  also waits for a cancelled walk to reach its next step.
- Open, not done: `Isolate.run` for the walk. Streaming results and cancelling across an
  isolate needs ports and `Isolate.kill`; the async walk already yields every 8 directories.
  Worth doing if `browse.scan` timings on a home folder still show jank.
- The walk reads through task-15's `DirectoryLister` (list and the `.git` check); the test uses
  a blocking fake lister.
- `Editors`: `Exists` is `Future<bool>` and defaults to the `DirectoryLister`; the Program Files
  candidates were already listed through it (task-15). `test/browser_scan_test.dart` greps `lib/`
  for `*Sync(`.
