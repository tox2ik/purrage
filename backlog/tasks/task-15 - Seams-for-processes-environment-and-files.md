---
id: task-15
title: Seams for processes, environment and files
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - tests
  - refactor
dependencies: []
priority: high
---

## Description

Several branches can only run on a machine in a particular state, so no test reaches them:

- `Repo.status` calls `Process.run('git', …)` directly, and its non-zero exit branch needs a
  broken repository.
- `Repo.writeTextFile` / `clearHiddenAndSystem` / `_attributes` call `attrib`. Their failure
  branches ("still Hidden after attrib -H -S", "could not set H again") need a file that
  refuses.
- `Editors` calls `where`, `git var GIT_EDITOR`, reads `Platform.environment`
  (`VISUAL`, `EDITOR`, `ProgramFiles`) and lists `Program Files`.
- `Prefs.defaultDirectory` and `Repo.globalIgnorePath` read `APPDATA`, `USERPROFILE`, `HOME` and
  `XDG_CONFIG_HOME`.
- `RepoBrowser.drives` probes `A:`…`Z:`.

Introduce three small seams, each with a real default and a fake for tests:

- `ProcessRunner` (`run(exe, args, {cwd, stdin})` → exit code, stdout, stderr), used by `Repo`
  for status and stdin calls, by `Editors` and by the attrib helpers. `GitDir.runCommand` stays
  the door for the rest of git.
- `Env` (a `Map<String, String>` view plus `isWindows`), passed where `Platform.*` is read.
- A `DirectoryLister` for the browse walk and the nvim-qt probe.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 no `Process.run`/`Process.start` outside the runner; no `Platform.environment` outside `Env`
- [ ] #2 the attrib failure branches, `where` ordering (.exe, then .cmd/.bat), the env fallbacks and the drive probe have unit tests with fakes
- [ ] #3 the real implementations are still exercised by the repo tests and integration tests
<!-- AC:END -->
