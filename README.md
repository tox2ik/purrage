# purrage

![purrage on a checkout with six untracked paths, the ignore pane open on .gitignore](https://files.catbox.moe/q51hjs.png)

`git status` as a list: track or ignore each file, then commit.

One list across the window, one commit line across the bottom. No diffs, no branches,
no remotes. A Flutter app for Windows.

## Learning

Two things this one taught me, and both of them are about noise.

A stale `.git` file left behind by a checkout that moved or was deleted is worse than
no `.git` at all: it lies about what the repository is, so the app has to recognise it
and say so instead of quietly showing an empty list.

The cache folders are the other half. `build/`, `.dart_tool/`, `out/` are not files
anyone means to see — they are the mess the tools leave behind while they work, and
putting them in `.gitignore` is the entire point of the app.

Cleaning out the messy `.git` files and ignoring all the cache folders makes me purr
like a kitten that has chased every dust bunny out from under the sofa and now sits in
the middle of a clean room.

## Running it

```sh
flutter pub get
flutter run -d windows
flutter test
```

The `Makefile` wraps the same thing for everyday use: `make run`, `make test`,
`make build`, `make analyze`.

Releases are cut by hand: dispatch the `release` workflow with a Ymd version
(`20261117`) and it tests, builds and publishes the Windows artifact.
