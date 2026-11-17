---
id: task-13
title: Name the repository, and polish the commit bar
status: To Do
assignee: []
created_date: '2026-11-17'
labels:
  - ui
  - usability
dependencies: []
priority: low
---

## Description

After a switch in Browse, nothing in the Changes mode says which repository it shows. The window
title is always "Purrage", and the only path on screen is in the Browse list. With several
checkouts of the same project, that is how a commit lands in the wrong one.

- The window title becomes `<repo folder> - Purrage`, and the Changes header shows the path, plus
  the current branch, read-only (`git branch --show-current`, read with status). The plan rules
  out branch *operations*, not naming the branch.
- Commit bar:
  - `Ctrl+Enter` in the message commits. Enter already does (`onSubmitted`); keep both.
  - A summary over 72 characters gets a quiet counter.
  - After a commit, the keyboard goes back to the list.
  - The button reads `Commit 0` when nothing is staged. Make it `Commit`, with a tooltip that says
    why it is disabled.
  - The field is read-only when nothing is staged, but typing still looks possible. Show the
    reason as the hint.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 window title and header name the repository, and update on a Browse switch
- [ ] #2 commit bar behaviour covered by widget tests (seeded FakeRepo)
<!-- AC:END -->
