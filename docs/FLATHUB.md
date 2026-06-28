# Flathub Preparation

Tomodoro's Flathub app ID is `io.github.samet_mohamedamin.Tomodoro`.

Use these checks before opening a Flathub submission PR:

```sh
meson compile -C build-todo
meson test -C build-todo --print-errorlogs
appstreamcli validate --no-net --explain build-todo/data/io.github.samet_mohamedamin.Tomodoro.metainfo.xml
```

Install and smoke-test the local Flatpak:

```sh
scripts/todo-pomodoro-flatpak-install
timeout 5s flatpak run io.github.samet_mohamedamin.Tomodoro
```

The repository-root manifest `io.github.samet_mohamedamin.Tomodoro.json` is the Flathub source manifest. It is pinned to the current release tag. When releasing a new version, update the AppStream release entry, bump the Meson version, update the manifest tag, and push the matching Git tag before submitting the Flathub PR.

Flathub PR checklist:

- Use `io.github.samet_mohamedamin.Tomodoro.json` as the manifest name.
- Ensure the AppStream ID, desktop file, icon name, and manifest app ID all match `io.github.samet_mohamedamin.Tomodoro`.
- Keep `data/io.github.samet_mohamedamin.Tomodoro.metainfo.xml.in` valid and include screenshots, content rating, developer metadata, release notes, and homepage/bugtracker/source URLs.
- Keep screenshots at stable URLs under `images/`.
- Document any broad permission request; current permissions are limited to Wayland/fallback X11, notifications, StatusNotifier, EDS calendar services, and `~/contexts:create`.
