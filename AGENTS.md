# Agent Instructions

This repository is the restored Vala Tomodoro app. Treat it as the active app unless the user explicitly says otherwise.

## Project Boundaries

- Do not edit `/var/home/mohamedamin/Desktop/me/todo` unless the user explicitly asks; that directory is the original Python app and legacy data source.
- Keep persistent work in this repository, not in `/tmp`.
- Before broad recovery, replay, or refactor work, create a backup archive outside the repo or under the old app's `backups/` directory and report its path.
- Leftover FocusTimer files may exist as reference material. Active Tomodoro build targets must use the `io.github.samet_mohamedamin.Tomodoro` Vala sources and must not reintroduce FocusTimer product behavior.

## Feature Source Of Truth

- `docs/FEATURES.md` is mandatory source-of-truth documentation.
- Any feature add, update, delete, or behavior change must update `docs/FEATURES.md` in the same change.
- The spec must be detailed enough to recreate the app from scratch, including storage, todo parsing, UI behavior, edge cases, settings, keyboard shortcuts, and rebuild checklist.
- The app intentionally has no stats tab.

## Git Discipline

- Commit every completed change requested by the user.
- Do not leave a successful fix only in the working tree.
- Keep commits focused and include the relevant spec update with the implementation change.
- For every user-visible app change, bump the Meson/AppStream version and update the About dialog release notes in the same commit.
- Do not revert user changes or unrelated dirty work unless the user explicitly asks.
- `main` is the GitHub-facing branch and tracks `origin/main`.
- Until the user says the public commit is completed, GitHub `main` must stay as one commit. Publish updates by amending `main` and pushing with `--force-with-lease`, not by adding a second public commit.
- Keep ongoing local work and detailed history on local-only branches. `local-full-history` preserves the pre-public development history and must not be pushed unless the user explicitly asks.

## Verification

Use these commands from this repository root:

```sh
meson setup build-todo
meson compile -C build-todo
meson test -C build-todo --print-errorlogs
```

For an isolated smoke launch that does not touch real user data:

```sh
mkdir -p /tmp/todo-pomodoro-smoke-home /tmp/todo-pomodoro-smoke-data
GSETTINGS_SCHEMA_DIR="$PWD/build-todo/data" timeout 5s env HOME=/tmp/todo-pomodoro-smoke-home XDG_DATA_HOME=/tmp/todo-pomodoro-smoke-data ./build-todo/src/tomodoro
```

Exit code `124` from the smoke command means the timeout stopped a running app; that is acceptable. A segmentation fault or immediate runtime warning about missing compiled resources is not acceptable.

## Runtime Data

- The app should use `~/Desktop/me/todo/data` by default when that legacy app data directory exists.
- If the legacy data directory is absent, the app falls back to XDG data storage.
- Tests and smoke runs should use injected temporary data roots.

## Local GNOME / Flatpak Install

- The preferred GNOME installation is now the user Flatpak `io.github.samet_mohamedamin.Tomodoro`.
- The Flatpak installer is `scripts/todo-pomodoro-flatpak-install`.
- The installer builds `build-flatpak/`, exports a local repository and bundle, installs with `flatpak install --user`, grants `~/contexts`, removes the old `io.github.mohamedamin.TodoPomodoro` install if present, and rewrites the user-local desktop entry to run `flatpak run io.github.samet_mohamedamin.Tomodoro`.
- The launcher is `~/.local/bin/todo-pomodoro`, symlinked to `scripts/todo-pomodoro-flatpak-launch`.
- The updater is `~/.local/bin/todo-pomodoro-update`, symlinked to `scripts/todo-pomodoro-flatpak-install`.
- After code changes that should be usable from GNOME, run:

```sh
~/.local/bin/todo-pomodoro-update
```

- The older toolbox scripts `scripts/todo-pomodoro-launch` and `scripts/todo-pomodoro-update` are retained for fallback local builds, but do not use them as the default install path unless the user explicitly asks to stop using Flatpak.
- To run the installed app from a terminal:

```sh
flatpak run io.github.samet_mohamedamin.Tomodoro
```
