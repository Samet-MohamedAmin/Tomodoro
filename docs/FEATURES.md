# Tomodoro Functionality Specification

This is the source of truth for recreating Tomodoro from scratch. It describes the Vala/GTK 4/libadwaita app migrated from the original Python project. Keep this file updated whenever a feature is added, changed, or removed.

## Scope

Tomodoro is a context-specific `todo.txt` app with two top-level views in an `Adw.ViewStack`, selected by a native `Adw.ViewSwitcher` in an `Adw.HeaderBar`:

- `timer`: run a Pomodoro against one selected active todo.
- `list`: search, group, edit, complete, duplicate, create, and delete todos.

The project uses the FocusTimer repository structure as a Vala/libadwaita base only. Active Tomodoro targets must compile only Tomodoro sources. Leftover FocusTimer files may exist as reference material but are not app behavior.

Non-goals: no stats tab or `Ctrl+3`, no FocusTimer product behavior, no FocusTimer plugin system, command automation, FocusTimer plugin D-Bus API, scheduler, or database model, and no separate project-management screen unless explicitly reintroduced.

Build identity:

- Display name: `Tomodoro`.
- App ID: `io.github.samet_mohamedamin.Tomodoro`.
- Current version: `0.1.33`.
- Homepage: `https://github.com/Samet-MohamedAmin/Tomodoro`.
- CSS resource: `/io/github/samet_mohamedamin/Tomodoro/style.css`.
- Tomato icon resource: `/io/github/samet_mohamedamin/Tomodoro/icons/tomato.svg`; use the compiled local SVG instead of emoji.
- The About dialog must show the current app version and current release notes. Every user-visible behavior change must bump the Meson/AppStream version and update About release notes in the same change.
- Public positioning: `Todo + Pomodoro = Tomodoro.` Describe the app as a todo.txt task list plus Pomodoro timer for planning tasks and tracking focused work still left. Avoid overstating future features; present the app as working now, actively maintained, and open to feature requests.

## Storage And State

Storage is plain files, never a database:

- App state: `app-state.json` under the app data root.
- Todo files: `<contexts-root>/<context-slug>/todo.txt`, where the default contexts root is `~/contexts`.
- Todo saves preserve a trailing newline after every serialized todo.

Default app data root, in order:

1. `TOMODORO_DATA_ROOT` when set and non-empty.
2. Compatibility `TODO_POMODORO_DATA_ROOT` when set and non-empty.
3. `${XDG_DATA_HOME}/tomodoro`, usually `~/.local/share/tomodoro` outside Flatpak or `~/.var/app/io.github.samet_mohamedamin.Tomodoro/data/tomodoro` inside Flatpak.
4. Test/development helpers may inject a temporary root; injected test roots keep contexts under `<data-root>/contexts` for isolation.

Default contexts root, in order:

1. `TOMODORO_CONTEXTS_ROOT` when set and non-empty.
2. Compatibility `TODO_POMODORO_CONTEXTS_ROOT` when set and non-empty.
3. `~/contexts`.

Flatpak note: the native no-extra-permission location for app data is the app sandbox data directory under `~/.var/app/io.github.samet_mohamedamin.Tomodoro/data`. Direct host-visible `~/contexts` requires the narrow `~/contexts:create` filesystem permission; it is still much narrower than full home access.

`app-state.json` stores:

```json
{
  "selected_context": "work",
  "selected_project": "",
  "selected_view": "todos",
  "selected_todo_id": "123e4567-e89b-12d3-a456-426614174000",
  "selected_order": "due",
  "last_todo_priority": "C",
  "last_todo_project": "Inbox",
  "last_todo_subproject": "Default",
  "last_todo_due": "",
  "default_context": "work",
  "window": {"width": 900, "height": 640},
  "pomodoro_display": "icons",
  "compact_timer_actions": true,
  "show_delete_button": true,
  "dependencies_enabled": true,
  "auto_depend_on_previous_todo": false,
  "project_dependency_graph": false,
  "calendar_events_enabled": true,
  "contexts": {
    "work": {
      "name": "Work",
      "icon": "briefcase-symbolic",
      "default_project": "Inbox",
      "project_icons": {"Inbox": "mail-inbox-symbolic"}
    }
  },
  "selected_pomodoro_profile": "classic",
  "pomodoro_profiles": {
    "classic": {
      "name": "Classic",
      "work_minutes": 25,
      "break_minutes": 5,
      "work_seconds": 1500,
      "break_seconds": 300,
      "long_break_seconds": 900
    }
  },
  "notifications": {
    "due_today": true,
    "due_tomorrow": true,
    "due_cutoff_hour": 18
  },
  "pomodoro_history": [
    {
      "completed_at": "2026-06-19T17:10:00",
      "context": "work",
      "project": "Inbox.Default",
      "profile": "classic"
    }
  ]
}
```

Defaults when state is missing/unreadable:

- Context `work`: name `Work`, icon `briefcase-symbolic`, default project `Inbox`, `Inbox` icon `mail-inbox-symbolic`.
- Selected project: empty string for `All`; stale/missing roots clear to `All`.
- Selected view: `todos` or `pomodoro`; invalid values fall back to `todos`. If restored `pomodoro` is unavailable because there is no active selected todo, fall back to `todos`.
- Selected todo ID: hidden ID of the last selected timer todo, or empty.
- Selected order: `due`, `priority`, `project`, or `recurring`; invalid values fall back to `due`. Legacy `dependency` state migrates to `project`.
- Last todo priority: default `C`; update after successful new/edit/duplicate save.
- Last todo project/subproject: default `Inbox`/`Default`; subproject memory is root-project scoped. New todo reuses the last subproject only when the new todo root matches `last_todo_project`; otherwise it uses `Default`.
- Last todo due date: default empty; successful new/edit/duplicate saves remember the entered due date, including empty. Invalid dates become empty. Past remembered dates are clamped to today's local date before reuse.
- Window: default 900 x 640, restored on launch and clamped to at least 360 x 360.
- Pomodoro display: `icons`.
- Compact timer actions: persisted, but only active in narrow timer layout.
- Todo dependencies: enabled by default. Auto-depend-on-previous and Project dependency graph are disabled by default and only have effect when dependencies are enabled.
- Calendar events: enabled by default.
- Notifications: due today on and due tomorrow on. A stored cutoff hour can remain for compatibility, but Settings does not expose it.
- History: empty.
- Built-in profiles are ensured on load: `classic` 25m/5m/15m, `deep-work` 50m/10m/30m, `short` 15m/3m/9m, `testing` 10s/5s/5s. Legacy `work_minutes`/`break_minutes` are preserved, but runtime uses seconds fields.

Startup must not write app-state while constructing the window. Closing persists width, height, selected view, selected timer todo, and selected order in one app-state write.

## Todo Model

Todo file line format:

```txt
(A) Task body +Project.Subproject due:2026-07-01 pm:3 pm-done:2 id:123e4567-e89b-12d3-a456-426614174000 dep:223e4567-e89b-12d3-a456-426614174000 custom:x
```

Supported tokens:

- Leading `x`: parsed but final completion is derived from `pm`.
- Priority: leading `(A)` through `(H)`, default `C`.
- Body: all non-project, non-tag text.
- Project: last `+Project` or `+Project.Subproject` wins.
- Tags: `due:YYYY-MM-DD`, `pm:N`, `pm-done:N`, hidden `pm-prev:N`, hidden stable `id:<unique-id>`, optional hidden dependency `dep:<todo-id>`, recurring-template `recur:daily|weekly|monthly`, weekly template days `recur-days:mon,tue,...`, monthly anchor `recur-day:N`, generated-instance parent `recur-parent:<template-id>`, template latest generated date `recur-latest:YYYY-MM-DD`, and preserved unknown `key:value` tags with valid tag keys.

Parsing, sanitization, and serialization:

- Ignore empty lines and todos whose parsed body becomes empty.
- Invalid/negative `pm` and `pm-done` become `0`; invalid dates are removed.
- `pm:0` means completed even without leading `x`; `pm > 0` means active even with leading `x`.
- Unknown tags are removed from body and preserved on save.
- Body text compacts spaces and uppercases the first letter.
- Every saved todo has a non-empty hidden ID. Missing/invalid IDs are generated; duplicate IDs keep the first and regenerate later duplicates. IDs are never shown in the UI and are ignored for duplicate-content detection.
- Dependencies use hidden `dep:<todo-id>` metadata. Invalid dependency IDs, self-dependencies, dependencies pointing at no todo in the same saved file, and circular dependency chains are removed during sanitization.
- Recurrence uses template rows, not normal todo rows. A template has `recur:daily`, `recur:weekly`, or `recur:monthly`, no due date, no dependency, no completion state, and `pm` clamped to at least `1`. Weekly templates store selected days in `recur-days:`; if all seven days are selected the template becomes daily. Monthly templates store `recur-day:N`; months without `N` use the closest valid day.
- Invalid priorities fall back to `C`.
- Invalid project roots fall back to the context default project, then `Inbox`; invalid subprojects fall back to `Default`.
- Dirty loaded files are rewritten after sanitization.
- Serialization order: optional `x`, priority, body, `+Project`, optional due, `pm:N`, `pm-done:N`, `id:<unique-id>`, optional `dep:<todo-id>`, optional `recur-parent:<template-id>`, optional `recur:<mode>`, optional `recur-day:N`, optional `recur-days:...`, optional `recur-latest:YYYY-MM-DD`, preserved unknown tags. `pm-prev:N` is preserved only while needed and removed after the todo is reactivated.

Completion and summaries:

- Finishing one Pomodoro increments `pm-done` by 1 and decrements `pm` by 1 only when `pm > 0`.
- Completion is not an independent saved state; it is derived from remaining pomodoros.
- Row/list completion stores the current positive `pm` in hidden `pm-prev:N`, then sets `pm:0`. Marking active restores `pm-prev:N`, or `1` if absent.
- Todo summary is display-only: if body contains `. `, summary is the first phrase through the period; otherwise it is the full normalized body.
- Timer summary display is capped at 37 characters, matching the minimum window width. Reference max: `Give access to team platform dev dev.`
- When trimming todo text, trim at a word boundary when practical and do not append `...`.
- Recurring templates generate normal todo instances with `recur-parent:<template-id>`. Generated instances copy body, project, priority, and pomodoros from the template, store their own due date, and do not append the due date to the body. The template stores `recur-latest:` as the newest generated due date, so a generated instance that the user deletes is not recreated on the next load.
- Daily templates generate yesterday and today. A daily generated instance that is still active after 12:00 local time on the day after its due date is removed during sanitization. Weekly templates generate yesterday/today/tomorrow when those dates match selected weekdays. Monthly templates generate matching yesterday/today/tomorrow dates using the clamped month day.

## Projects And Contexts

Project normalization:

- Trim, remove leading `+`, lowercase, replace spaces with `-`, replace `/` with `.`, keep only letters/digits/`.`, `-`, `_`, collapse empty dot segments, allow only `Main` or `Main.Sub`, uppercase the first letter of each segment, truncate each segment at 32 characters, and use the provided fallback if empty.
- UI-created body, main project, and subproject values must contain at least three letters.
- Body and subproject entries auto-uppercase the first typed letter. Subproject entry also strips spaces, `+`, `.`, `/`, and other todo-structure-breaking characters while typing, keeps only letters/digits/`-`/`_`, and caps at 32 characters.
- `Main.Sub` displays as `Main / Sub`; main project is the part before the first dot; subproject is after it. Todos without explicit subproject use `Default` for timer focus.

Contexts:

- Each context has slug, display name, icon, default project, project icon map, and its own `todo.txt`.
- The selected context controls editing; switching context reloads that file.
- Contexts are created from the app menu inline `+New` entry. Input keeps only letters/digits/`_`/`-`, removes spaces/`+`/`.`/`/` and other todo-structure-breaking characters, uppercases only the first letter, caps at 32 chars, and requires at least three letters.
- Pressing Enter in the context `+New` entry creates only valid, non-duplicate contexts. Duplicate context names, ignoring case, mark the entry with native error styling and Enter does not create one.
- Slugs are generated from names and made unique with `-2`, `-3`, etc.
- The selected context is a primary-colored selector button at the top, excluded from expanded alternatives. Selecting keeps the menu open and smoothly collapses the alternatives so the new selection is removed next expansion.
- Delete buttons are hidden by default, revealed by right-click with animation, and must not reserve trailing blank space. Deleting is disabled when only one context exists.
- Deleting a context removes `contexts/<slug>`, removes its history entries, and falls back selection/default to the first remaining context when needed.
- Context list expand/collapse uses slide-down animation. Opening the main menu resets expansion.

All Contexts mode:

- Loads all contexts, includes context name in row subtitle, caches reads by context and file mtime, and avoids unnecessary timer-choice refresh work.
- Disables timer use, project creation/deletion, and New/Duplicate todo operations.
- Allows editing, completing/reactivating, and deleting existing todos/templates. Saves write back only to the row's owning context file, then reload the overview.
- Attempts to create, duplicate, or run timers show the timed native context warning and redirect timer view attempts back to list.
- Empty state is informational and not clickable.
- Clicking an active row switches to that row's context, makes it current, selects the todo for the timer, opens timer view, and starts the timer unless the todo has an unfinished dependency, in which case the dependency dialog is shown first.

Projects:

- Root project filtering lives in the main menu under a context-style selector. The selector shows selected project or `All` as the primary-colored top button, excluding that item from alternatives.
- Selecting a project persists to app-state, keeps the menu open, smoothly collapses alternatives, and removes the new selection on next expansion.
- Selecting `All`, switching context, choosing `All Contexts`, deleting the selected project, or loading a stale missing root clears the selected project.
- Selecting a project with no active todos makes the timer unavailable and switches to list if timer was open.
- Project selector is disabled in `All Contexts`; only one of project/context alternatives may be expanded at once.
- Known roots come from context default, project icon metadata, and todo projects. Project roots remain selectable as long as they exist, even when every todo under that root is completed. Completed todo visibility is controlled only by the list's show-completed toggle, not by project selector availability.
- Project selector includes an inline `+New` entry and right-click-revealed delete buttons. Pressing Enter creates only valid, non-duplicate roots and does not switch the selected project filter to the new root. Project creation mirrors context sanitization and duplicate-name validation, comparing normalized roots ignoring case.
- Project deletion is disabled in `All Contexts` and when the selected context has only one root. Empty projects delete without confirmation; projects with todos ask first. Deleting root `Main` removes todos/projects/history for `Main` and `Main.*`, removes matching project icon entries, resets selected project/focus/timer todo, and if the context default root was deleted, the default becomes the first remaining existing root. `Inbox` is only the initial root created with a new context; it has no special protection and deletion must not synthesize `Default` or recreate `Inbox`.

Project save rules:

- Main project todos constrain child todos on every save.
- A child cannot outrank its main project todo; higher child priority is lowered to main priority.
- If a main project todo has a due date, child todos with no due date or a later due date inherit it.
- Main project todo `pm` and `pm-done` become the sum of all child todos under that root.

## List View

Controls and responsive layout:

- Toolbar has a search entry, icon-only order/group menu (`Due`, `Priority`, `Project`, `Recurring`), a dedicated completed-todos toggle outside Recurring order, a separate nested/instances toggle where applicable, a New Recurring plus button in Recurring order, and optional delete-mode toggle.
- The completed-todos toggle only controls completed todo visibility and is hidden in Recurring order. The nested/instances toggle appears separately in dependency-graph modes to show/hide nested child rows and in Recurring order to show/hide generated next instances.
- Wide layout: search expands to fill available horizontal space without a fixed minimum width and shares a row with order menu, nested/instances toggle when visible, completed toggle when visible, recurring plus button, and delete-mode toggle.
- Narrow layout below 620 px: search is full-width on first row; order menu, nested/instances toggle when visible, completed toggle when visible, and recurring plus button stay left on the second row; the delete-mode toggle stays on the right after the spacer.
- The selected order mode is saved/restored, shown in toolbar as icon only, and choices show icon plus label in this order: Due, Priority, Project, Recurring. Priority order uses a sort-style icon, not an importance/warning icon.

Filtering, grouping, and ordering:

- Completed todos are hidden unless show-completed is enabled.
- Selected project filter limits rows to that root.
- Search supports one-letter priority `A`-`H`, general body/project/priority/relative-due text, project-normalized text, `+project` prefix, and under a selected root `+sub text`.
- Pressing Enter in search selects the single active filtered todo when exactly one active match remains.
- Priority grouping uses expander titles `A`-`H`; due grouping uses relative groups (`today`, `tomorrow`, `yesterday`, `N days overdue`, `N days`, `N weeks`, `N months`, `no due`) computed from calendar-day differences, not Unix-second differences. Project grouping uses root names when Projects is `All`; when one root is selected, Project grouping uses subproject names inside that root and todo rows omit the subproject subtitle. Recurring grouping shows recurring templates only as root rows grouped by `Daily`, `Weekly`, and `Monthly`; generated instances appear as indented child rows only when the Recurring toolbar toggle is active, with the occurrence date as the row title instead of repeating the template body or showing a duplicate date subtitle. Dependency graph mode keeps normal row styling and adds only indentation, not arrows or extra row borders/cards. Active and completed graph rows do not nest across each other; when a parent is completed and a child is active, the child renders as a root row and omits the completed parent subtitle.
- When dependency-graph nested rows are hidden, only root rows render and each root with hidden descendants shows a small child-count note such as `3 children`. The separate nested/instances toggle also hides/shows generated child instances in Recurring order.
- Group/section expander titles use normal row title weight and show GNOME-palette priority/due dots, except Recurring sections do not show priority color dots.
- Priority order sorts by priority rank, then due date, then dependency chain, then creation/file order. Due order keeps sections in due-date order and sorts rows inside each section by priority rank, then dependency chain, then creation/file order. Project order keeps sections in root-project/subproject order and sorts rows inside each section by priority rank, then dependency chain, then creation/file order. Recurring order keeps recurrence sections in daily, weekly, monthly order and sorts templates by schedule, priority, then creation/file order; generated child instances sort by due date. Dependency graph keeps the same section grouping and row actions, but renders parents before children inside each section. When dependency graph is enabled and Projects is `All`, Project order groups by main project root, not `Main / Sub`, and orders root sections by their highest active priority before falling back to name. Timer candidate order is priority rank, due date, then dependency chain, then creation/file order. Recurring templates are not timer candidates; generated recurring instances are normal timer candidates.
- Section folding is remembered in-memory across normal list refreshes, including new/edit/delete/complete saves and show-completed/delete-mode toggles. Folding memory is cleared and sections open again when context, selected project, or order mode changes.
- When show-completed is enabled, completed todos remain in their section but appear after active todos.

Rows:

- Title is todo body, capped to two lines with ellipsized overflow; stored body is not truncated.
- Subtitle contains `Main / Sub` and relative due label. Child rows inside dependency/recurring nesting omit project/subproject because their top parent carries that context. In `All Contexts`, subtitle also includes context name. Due grouping omits per-row due labels. Recurring template subtitles contain `Main / Sub` and the schedule label: `Daily`; one/two weekly days as plural full names such as `Mondays and Tuesdays`; three or more weekly days as `Every Mon, Tue, Wed`; and monthly day as `21st`. On narrow windows, when ordering by priority and Projects is `All`, due label moves to a second subtitle line.
- Completed rows are dimmed and show no pomodoro count/zero marker.
- Active rows use pointer cursor and are activatable; completed rows are not activatable.
- Activating an active row selects it for timer and opens timer view, except All Contexts behavior switches context and starts timer as specified above.
- Priority letters are visible in rows except Priority order, where the section title already provides the priority. Project and Recurring grouping color row priority letters with the GNOME priority palette; all other order modes keep priority letters uncolored. Dependency graph rows use the same coloring rule as their current order mode.
- Row suffix shows pomodoros left using settings: repeated local tomato SVG icons or compact number plus tomato. Repeated icons group by fours from the right edge; incomplete groups sit left of complete groups. Narrow rows below 620 px show icons up to 8 total and wrap at 4 per line; 620-999 px show up to 15 and wrap at 8; 1000 px+ show up to 15 and wrap at 12. Counts above the active limit fall back to number-plus-tomato.

Inline row actions and delete mode:

- In selected-context mode, right-click reveals animated square icon buttons for edit, duplicate, and completion toggle. Recurring template rows omit the completion toggle. Opening one row hides other inline actions.
- Completion toggle appears on active and completed rows, uses neutral styling, and applies `pm:0`/`pm-prev:N` semantics.
- In `All Contexts`, right-click reveals row actions too, but Duplicate is omitted. Edit, completion toggle, and delete-mode deletion write to the row's owning context.
- On narrow windows, revealed actions appear below the pomodoro display; on wide windows, inline after it.
- Delete mode is controlled by Settings `Show delete button`. If hidden, the toolbar toggle is hidden and active delete mode is disabled.
- Delete mode is available in selected-context and All Contexts modes. When enabled, toolbar toggle uses destructive styling, every row shows a small square destructive delete button, row right-click actions are disabled, and no edit/duplicate/complete actions appear.
- Toggling delete mode off hides row delete buttons and restores normal right-click actions. Clicking a normal row delete button deletes immediately without confirmation. Deleting a recurring template shows a native destructive confirmation first, because the template and its generated child instances stop appearing. Deleting the final todo returns to the normal selected-context empty state.

Empty states:

- Selected-context empty state: title `No Todos`, description `Click here to create a todo.`, clickable with pointer cursor, opens New Todo.
- All Contexts empty state is informational and not clickable.
- Recurring empty state: title `No Recurring Todos`, description `Click here to create a recurring template.`, clickable in selected-context mode, opens New Recurring.

## Todo Editor Dialog

The same dialog creates, edits, and duplicates todos.

Fields/layout:

- Fields: Body, Priority, Project, Subproject, optional Depends on, Due date, calendar picker, Pomodoros left spin control, Completed checkbox. Normal New/Edit Todo has no recurrence controls.
- Body is first and stays single-line. Priority appears after Body; Project appears after Priority.
- New todo shows the main project dropdown only when project filter is `All`; when a specific project filter is active, hide the main project dropdown and use that root.
- Edit todo cannot change root project or subproject after creation. When one root project is selected, the editor hides the main project dropdown and shows disabled Subproject. When Projects is `All`, it shows both Main and Subproject fields disabled.
- Delete button is shown only when editing an existing todo, at the bottom.

Priority/project entry behavior:

- Priority dropdown offers `A`-`H`, shows GNOME-palette colored dots, defaults to last successful dialog priority or `C`, and accepts `A`-`H` key presses while focused.
- Main project choices come from known roots plus context/default roots.
- Subproject defaults to the last successful dialog subproject only when the new todo root project matches the remembered root project; otherwise it defaults to `Default`.
- Existing subprojects for selected main project are suggested with inline autocomplete only, including `Default`. Autocomplete applies only while typing forward at the end of the field and must not reinsert deleted suffix text during Backspace, Delete, or selected-suffix edits.
- Body/subproject auto-uppercase first typed letter. Subproject typing enforces the same structure-name rules as project/context creation: no spaces, no `+`, no `.`, no `/`, only letters/digits/`-`/`_`, max 32 characters, at least three letters at save. Pressing Enter in Body saves through the same validation path as Save.
- While Body is focused, show a summary hint only when body exceeds the timer summary limit and either lacks a short explicit first phrase ending in `. ` or has one still too long. Hide the hint when Body loses focus or the body/summary fits.

Dependencies:

- Dependency UI appears only when Settings `Todo dependencies` is enabled.
- Depends on uses a selector popover with search and list in one view. It lists active parent candidates in the same exact project/subproject as the todo being created or edited, excludes the todo itself and circular dependency choices, can be searched by todo body or timer-style display summary text, and stores selection as hidden `dep:<todo-id>`. Parent candidates remain selectable unless they would create a circular chain.
- `None` means no dependency and serializes no `dep:` field.
- If Settings `Depend on previous todo` is enabled, a new todo automatically selects the most recently added active todo in the same subproject as its dependency. The user can change it to another listed todo or `None` before saving.
- Changing the subproject while creating a todo refreshes the dependency list to that subproject. Editing cannot change subproject or dependency after creation; the dependency is shown read-only.
- Saving with a dependency validates the chain before writing. The selected parent must not create a circular chain. If child B depends on parent A, then B cannot be higher priority than A. If A has a due date, B must also have a due date on or after A's due date; B may be undated only when A is undated. Selecting a parent filters the Priority dropdown to the parent priority and lower priorities only; for example parent `C` allows `C`-`H`. Changing the selected parent in New or Duplicate immediately rebuilds the Priority dropdown. If the current priority is outside the selected parent constraint, the editor moves it back to the parent priority and shows an inline notice. If the due date is empty or before the parent due date, the Due date field gets native error styling, shows a field error, and Save is blocked. Circular dependency errors stay on the Depends on field.
- Editing a parent todo validates its active children before saving. If the current Priority would make one or more children higher priority, show an orange warning under Priority saying `1 child has priority higher than this todo. Save will overwrite children.` or `%d children have priority higher than this todo. Save will overwrite children.` If the current Due date would make one or more children earlier/undated against a dated parent, show the equivalent warning under Due date. Save does not open a second dialog in this case; it saves the parent and cascades priority/due constraints through children.

Pomodoros, due date, validation, and duplicate:

- Pomodoros left uses native numeric spin control, clamped 0-99. `0` means completed.
- Setting value to `0` checks Completed; any positive value clears it. Checking Completed remembers current positive count, sets `0`, and saves `pm-prev:N`. Clearing while `0` restores previous positive count or `1`. Completed is mirrored from pomodoros, not independently saved.
- Due entry accepts `YYYY-MM-DD`; invalid dates add error styling and show `Invalid date`. New/Edit does not allow choosing or saving dates before today; past dates show due-date error styling and `Due date cannot be before today.` Editing an existing overdue todo preserves the old visible due value but blocks saving until it is corrected. Prefilled, pasted, or calendar-written duplicated date text such as `2026-06-232026-06-23` is normalized back to one valid date before validation.
- New todo defaults due date from the last successful dialog due date. Empty due dates are remembered as empty. Past remembered dates are clamped to today before display.
- Calendar-selected dates display as `Today`, `Tomorrow`, `In 2 days`, or `In 3 days` when the selected date is that close; choosing a past calendar day snaps back to today. When the Due date entry receives focus for editing, any relative display label converts back to numeric `YYYY-MM-DD` and selects the text.
- Generated recurring instances open in the normal Todo editor but are locked down: Body, project/subproject, dependency, and Due date are shown but disabled; a read-only `Recurring task template` field replaces Depends on and names the source template/schedule; only Priority, Pomodoros left, and Completed can be changed.
- Calendar selection stores an ISO `YYYY-MM-DD` due date internally, hides the calendar, and selecting the already-highlighted current date in a new todo still selects today. The visible entry may show the relative labels above until focused for editing. Calendar reveal slides down and dialog height animates smoothly, returning to compact height when collapsed.
- Body, main project, and subproject must each contain at least three letters; shorter values show inline errors.
- Exact duplicate todos are rejected by compact lowercase body, priority, due, project, remaining pomodoros, and derived completion. Hidden ID is ignored.
- Editing preserves `pm-done`, hidden ID, project/subproject, and unknown tags. Creating uses contextual defaults from selected project/focus/context default.
- Successful new/edit/duplicate saves update last priority, root-scoped subproject, and due-date defaults.

Duplicate flow:

- Duplicate opens the dialog as a new todo template, suffixes body with ` (2)`, immediately focuses Body and places the cursor at the end. It is not edit mode: subproject can change, main project can change when the current project filter is `All`, and Depends on is selectable.
- Priority, due, project, `pm`, `pm-done`, unknown tags, and derived completion are copied. Hidden ID is not copied; a new ID is assigned on save.

## Recurring Template Dialog

Recurring templates are created from the Recurring order view empty state or New Recurring toolbar button, and edited by activating/editing a recurring template row.

- Fields: Body, Priority, Project/Subproject, Repeats, optional Week days, optional Month day, and Pomodoros left. Priority uses the same colored-letter/dropdown presentation as normal todo editing.
- Templates do not have Depends on, Due date, Completed, or a completion action. Pomodoros left is clamped to `1`-`99`.
- Daily templates show no extra schedule controls or unused schedule labels.
- Weekly templates show seven toggle buttons and the Week days label only while Weekly is selected. At least one weekday is required. Selecting all seven weekdays converts the template to Daily.
- Monthly templates show a day-of-month spinner and Month day label only while Monthly is selected; generated instances in shorter months use the closest valid day.
- Template rows show schedule text next to project/subproject: `Daily`; plural full day names for one or two selected weekdays; `Every Mon, Tue, Wed` style text for three or more weekdays; and ordinal day text such as `21st` for monthly.
- Editing a template keeps the main project fixed. When one root project is selected, Subproject can change. When Projects is `All`, both Main and Subproject are shown disabled.
- Saving a template preserves its hidden ID and `recur-latest:` value on edit. Duplicating a template clears ID and `recur-latest:` so the duplicate starts its own generated series.
- Deleting a template requires a destructive confirmation and causes generated child instances for that template to stop appearing.

## Timer View

Controls/layout:

- Controls: focus/subproject menu, todo selector menu, edit selected todo button, session indicator, countdown label, Start/Pause, `+`, Done, and metadata line.
- Wide layout: focus menu, todo selector, and edit share one row. Narrow below 620 px: focus moves to its own row; todo selector/edit stay on next row. Narrow timer spacing matches list rhythm.
- Session indicator, countdown, and timer buttons are in an invisible group centered horizontally/vertically against the timer window area; a bottom spacer compensates for selector/metadata rows. Session indicator sits above countdown.
- Session indicator is text (`Pomodoro`, `Short Break`, or `Long Break`) shown above the countdown and keeps tooltip text with the session name for accessibility.
- Countdown is large, tabular, `MM:SS` or `H:MM:SS`.
- Timer controls are ordered Start/Pause, `+`, Done. Start/Pause and `+` have matching stable dimensions, are larger than compact inline actions but narrower/shorter than older timer controls, and do not use primary/suggested accent styling. Start/Pause is icon-only and toggles play/pause icons. `+` is a native symbolic add icon that adds one minute to the current session without changing mode.
- Done uses a symbolic GTK icon plus label, neutral inverse styling based on the theme, finishes the current session, and glows slowly when the session has naturally reached `00:00`.

Compact timer actions:

- Wide windows always show focus/project selector and edit button.
- In narrow layout only, right-clicking selected todo body toggles stored `compact_timer_actions`. Compact mode hides focus selector/edit with animations, leaves no empty row/gap, and does not change todo labels/search/filtering.
- Narrow selected-todo tooltip is multiline and explains right-click. In compact mode, left-click switches to list, animates scrolling to that todo, and highlights the row with a primary/accent border until the next left click, right-click, or key press. Right-clicking the highlighted row clears the highlight and still reveals row actions.
- Outside narrow compact mode, including small non-compact and all wide layouts, left-click opens the timer todo selector.

State and availability:

- Session modes: `Pomodoro`, `Short Break`, `Long Break`. Pomodoro uses profile `work_seconds`; Short Break uses `break_seconds`; Long Break uses `long_break_seconds` after every fourth completed Pomodoro.
- Timer cannot run without a selected active todo or in All Contexts. No default todo/timer fallback exists.
- Unavailable timer disables controls, visibly dims the timer label, keeps timer page visible in the switcher, shows metadata explaining whether a specific context or active todo is needed, and redirects keyboard/action timer view attempts back to list with a timed banner.
- If the active timer selection/filter becomes unavailable, stop the timer and switch to list. A selected project with no active todos must not fall back to another project.
- Timer/list navigation uses text-only `Adw.ViewSwitcher` page labels `Timer` and `List`, no page icons. Pages must explicitly keep empty `icon_name` values, and Tomodoro must hide any internal switcher `Gtk.Image` children that libadwaita creates for those pages.
- Last selected view, active timer todo ID, window size, and order mode restore on restart when valid.

Todo selection and focus filtering:

- Timer selector lists active todos from the current subproject/focus, excludes the current selected todo, and every button must select the exact todo it displays independent of refreshes or loop ordering.
- Selecting a todo immediately makes it current and updates the focus/project selector. Edit is disabled without a valid active todo.
- If dependency support is enabled and the selected todo has a `dep:<todo-id>` chain pointing to an active unfinished parent, selection shows a native alert instead of starting work. The alert explains the parent dependency, says to work on the highest dependency first, and offers `Work on Highest Dependency`, `Remove Dependency and Start`, and `Cancel`.
- `Work on Highest Dependency` selects the highest unfinished parent in the chain. `Remove Dependency and Start` clears the selected todo's `dep:` metadata, saves, and selects that todo. Completed dependencies do not block selection.
- Automatic best-todo selection skips todos with unfinished dependencies; users can still select them manually to see the dependency alert.
- When a todo is completed and dependency support is enabled, the timer prefers the next active todo that directly depended on the completed todo, if it is now unblocked and matches the active timer filter.
- Selected todo label displays timer summary only, omits priority, stays one line, keeps a small minimum width, and must not prevent window shrinking. Wide windows allocate more label width.
- Timer focus/project and todo selector labels use ellipsizing single-line labels with tiny width requests so long project names and All-project labels never prevent shrinking the timer window.
- Focus choices are based on active todos. `Main.Sub` focus is `Main.Sub`; project `Main` has focus `Main.Default`.
- When project filter is `All`, focus labels use `Main / Sub`; when a root is selected, labels show only subproject under that root; when no root filter is active, focus choices group under root headings.
- Focus search matches raw project, normalized project, `Main / Sub`, `Main.Sub`, and `Main/Sub`. Selecting focus clears search, closes popover, and picks the best matching timer todo.
- Timer todo search matches body plus `Main / Sub`, `Main.Sub`, and `Main/Sub`. If typed text has no matches, show a primary `Create` option; click or Enter opens New Todo with uppercase-normalized body from search text and project/subproject from current timer focus.

Session completion and history:

- Start begins a one-second tick; Pause stops tick without resetting remaining seconds.
- Natural zero leaves timer at `00:00`, stops ticking, sends timer notification, and waits for Done. Clicking glowing Done advances to the next session and auto-starts it when a valid active todo exists.
- Done during Pomodoro records one finished pomodoro for the selected todo, saves todos, records history with local timestamp/context/project/profile, and advances to Short Break or every fourth Pomodoro to Long Break when break duration is positive; if break duration is zero, it resets directly to next Pomodoro.
- Done during Short Break or Long Break advances to the next Pomodoro.
- If the selected todo reaches `pm == 0`, move to the next best todo: same focus first, same root second, then any active todo. If no next todo exists, stop timer availability and switch to list.
- When Done would reduce a todo to zero, show a native alert before saving final state. Message is todo body; actions are `Add pomodoros` and `Mark Complete`, with `Mark Complete` to the right of `Add pomodoros` in wide layout. Narrow stacked layouts show `Add pomodoros` above `Mark Complete`. Extra child is only a native numeric spin button defaulting to `1`, with no row container or visible input label.
- `Mark Complete` records the finished Pomodoro, sets completion through `pm:0`, and moves to next best todo. `Add pomodoros` adds selected remaining pomodoros before recording the finished Pomodoro, keeping the todo active and advancing to the proper break when enabled.

Metadata:

- Metadata line shows plain priority letter, due label, and pomodoros left, or inactive-state text.
- Pomodoro-left display uses the same `pomodoro_display_widget` as list rows, including repeated-vs-number setting, colorful tomato icon, grouping, responsive wrapping, and count fallback.

## Settings, Profiles, Notifications, And Integrations

Profiles:

- Built-ins: `classic` 25/5/15 min, `deep-work` 50/10/30 min, `short` 15/3/9 min, `testing` 10s/5s/5s.
- Profile summaries show Pomodoro, Short Break, and Long Break durations using seconds for sub-minute testing values and minutes otherwise.
- Settings profile dropdown persists `selected_pomodoro_profile`; changes affect future timer resets only.

Settings:

- `Pomodoro display` is a two-option `Adw.ToggleGroup` with taller icon-only buttons: four repeated tomatoes, or number plus tomato. No separate preview is shown.
- Display `icons` renders one tomato per remaining pomodoro; display `count` renders number plus tomato. Todo editor always uses numeric spin control.
- `Compact timer actions` switch appears only when Settings is opened from a narrow main window; hint is multiline and explains small-window right-click compact mode.
- `Show delete button` controls the list delete-mode toolbar toggle.
- Dependency controls are under a `Dependencies` heading.
- `Todo dependencies` controls whether New/Edit shows Depends on and whether timer selection enforces unfinished dependencies.
- `Depend on previous todo` is enabled only when dependencies are enabled. When active, New Todo auto-selects the most recently added active todo in the same exact subproject as the dependency candidate.
- `Project dependency graph` is enabled only when dependencies are enabled. When active, Due, Priority, and Project order modes render top-down parent/child graph rows inside their current sections instead of a flat list. Recurring keeps its template/instance child view.
- `Calendar events` controls GNOME Calendar integration. Turning it off persists `calendar_events_enabled: false`, removes Tomodoro-created events from the calendar, clears hidden `cal-uid` tags from saved todo lines, and prevents future calendar upserts while off. Turning it back on saves the setting and refreshes calendar events from the current todos.
- Settings does not expose due notification switches or the due cutoff hour.

Notifications:

- Startup due scan is deferred so the main window opens first, then loads all contexts, ignores completed todos, and sends one notification per context for due-today and/or due-tomorrow counts. Body: `<Context Name>: <N> todo(s) due today` or `due tomorrow`. IDs may use message text. Cutoff hour is stored for policy compatibility; current migrated behavior does not enforce cutoff timing.
- Timer start/pause updates MPRIS media-control state but does not send regular desktop notifications. Natural session end sends a session-finished notification; manual Done before zero does not.
- Session-finished notification title is current session name; body is the same selected todo summary/body shown in timer window. Notifications use `GApplication.send_notification`, high priority, category `timer`, app actions, and one stable replacement ID so they do not stack.
- Session-finished notification `Start/Pause` presents the app and invokes the same toggle as the in-app button. Notification `Done` presents the app and uses the same finish path, including the last-pomodoro dialog over the timer window.
- GNOME Shell always lets users dismiss regular notifications and may hide action buttons until expanded even when action support is reported. Regular notifications cannot remove the close button or force inline buttons.

Media controls and indicators:

- Tomodoro does not expose MPRIS and must not show as a music/media player in GNOME Shell.
- Keep regular notifications for due counts and session-finished alerts; do not use regular notifications for always-visible controls.
- Tomodoro exports a StatusNotifier/AppIndicator item with a monochrome symbolic app icon, tooltip, click-to-present behavior, and a DBusMenu menu.
- Indicator menu entries: `Open`, `New`, separator, `Pause/Start`, `Done`, separator, and `Quit`. Menu entries do not use icons.
- Indicator `New` presents the app window before opening the New Todo dialog.
- This is app-side support only: stock GNOME Shell does not show app indicators without an extension such as AppIndicator/KStatusNotifier.
- Flatpak grants narrow session-bus talk access to `org.kde.StatusNotifierWatcher` for indicator registration. Do not add broad session-bus access.

GNOME Calendar integration:

- Implemented through Evolution Data Server calendar APIs, not by writing GNOME Calendar files directly.
- GNOME Shell's `org.gnome.Shell.CalendarServer` is a shell display/read-side service; Tomodoro must not treat it as an event creation API.
- Correct path is Evolution Data Server APIs (`libecal-2.0`, `libedataserver-1.2`) because GNOME Calendar and top-panel date menu read EDS calendars.
- Tomodoro creates or updates one all-day `VEVENT` in the writable default EDS calendar for every active non-recurring todo with a due date. Generated recurring instances do not create separate non-recurring calendar UIDs; their calendar identity comes from the template occurrence UID.
- For recurring templates, Tomodoro projects one all-day `VEVENT` per active occurrence in the next 40 local calendar days. Daily projects every day, weekly projects selected weekdays, and monthly projects the selected/clamped month day.
- The event summary is `<Context>: <todo summary>`. The event description includes context, project, priority, pomodoros left, hidden todo ID, and full body.
- The event is transparent/free time and categorized as `Tomodoro`.
- Each dated non-recurring todo stores a hidden `cal-uid:<uid>` tag. This UID is deterministic from the todo ID so edits update the same event instead of creating duplicates. Recurring occurrence UIDs are deterministic as `tomodoro-<todo-id>-<YYYYMMDD>@io.github.samet_mohamedamin.Tomodoro` and are not stored on the todo line.
- Settings `Calendar events` defaults to on. When switched off, Tomodoro removes known calendar events by stored `cal-uid` and deterministic Tomodoro UIDs derived from todo IDs and recurring occurrence dates. It does not need a separate event database.
- Changing a due date updates the same non-recurring calendar event. Clearing a due date, completing a dated non-recurring todo, deleting a todo, or deleting a project removes the matching calendar event. Removal uses the stored hidden UID when present, or the deterministic UID derived from the todo ID for older dated todos that do not yet have `cal-uid`.
- Changing or deleting recurring templates removes projected events for the previous recurrence in the next 40 days and creates the new projected events when applicable. Completing or deleting a generated recurring instance removes that occurrence event. Future template occurrences after `recur-latest:` remain projected; generated dates at or before `recur-latest:` are projected only while the generated instance row still exists and is active.
- Calendar sync is best-effort and runs after todo files are saved. Failures warn but must not block or corrupt todo storage.
- Tests set `TOMODORO_DISABLE_CALENDAR_SYNC=1` to avoid touching the live user calendar.
- Flatpak support bundles `libical` and Evolution Data Server client libraries, and grants narrow session-bus talk access to `org.gnome.evolution.dataserver.Sources5` and `org.gnome.evolution.dataserver.Calendar8`. Do not request broad session-bus access.

## Packaging And Shortcuts

Flatpak:

- Local manifest: `build-aux/flatpak/io.github.samet_mohamedamin.Tomodoro.local.json`.
- Flathub source manifest: `io.github.samet_mohamedamin.Tomodoro.json`.
- Flathub preparation checklist: `docs/FLATHUB.md`.
- Runtime/SDK: `org.gnome.Platform//50`, `org.gnome.Sdk//50`; command `tomodoro`; app ID `io.github.samet_mohamedamin.Tomodoro`.
- AppStream summary: `Plan todo.txt tasks and work through them with Pomodoro sessions`.
- AppStream description must mention todo.txt tasks, Pomodoro sessions, remaining pomodoros, contexts/projects/priorities/due dates/dependencies/recurring schedules, desktop notifications, app indicator, and optional GNOME Calendar events.
- AppStream screenshot URLs point at stable repository images: `images/screenshot-list.png`, `images/screenshot-timer.png`, and `images/screenshot-editor.png`.
- Permissions are intentionally narrow: Wayland, fallback X11, IPC sharing, session-bus talk access to `org.freedesktop.Notifications`, `org.kde.StatusNotifierWatcher`, and the required EDS source/calendar services, plus filesystem access only to `~/contexts:create`.
- `scripts/todo-pomodoro-flatpak-install` builds with Flatpak commands, not `flatpak-builder`. It downloads and SHA-256 verifies the pinned `libical` and Evolution Data Server source archives, builds those client libraries into `/app`, then builds Tomodoro, exports a local repo and `build-flatpak/io.github.samet_mohamedamin.Tomodoro.flatpak`, installs with `flatpak install --user`, applies `TOMODORO_CONTEXTS_ROOT=~/contexts`, grants that directory only, removes previous local IDs `io.github.mohamedamin.Tomodoro` and `io.github.mohamedamin.TodoPomodoro` when present, and rewrites GNOME/user-local launchers to `flatpak run io.github.samet_mohamedamin.Tomodoro`.
- `scripts/todo-pomodoro-flatpak-launch` delegates to `flatpak run io.github.samet_mohamedamin.Tomodoro`.
- Meson installs app icon as `io.github.samet_mohamedamin.Tomodoro.svg` in the hicolor app icon theme so Flatpak exports a valid desktop icon.

Keyboard shortcuts:

- Settings includes `Keyboard Shortcuts`, opening native `Adw.ShortcutsDialog`. The main menu contains Settings and About, not a separate shortcuts item.
- `Ctrl+N`: new todo.
- `Ctrl+F`: focus list search.
- `Ctrl+1`: timer view.
- `Ctrl+2`: list view.
- `Ctrl+?`: keyboard shortcuts dialog.
- No `Ctrl+3` because there is no stats tab.

Agent skill:

- Opencode todo-management skill lives at `opencode/skills/tomodoro-todos/SKILL.md`.
- For global opencode use, install the same skill at `/var/home/mohamedamin/.config/opencode/skills/tomodoro-todos/SKILL.md` and `/var/home/mohamedamin/.opencode/skills/tomodoro-todos/SKILL.md`.
- The skill points agents at the active app repo, Flatpak app-state path, `/var/home/mohamedamin/contexts`, concrete context todo files, current context/project/subproject/due defaults, context/project suggestion rules, todo syntax, dependency behavior, summary behavior, normalization, and safe-write rules.

## Visual And Error Requirements

GTK/libadwaita components:

- Use GTK 4 and libadwaita: `Adw.ApplicationWindow`, `Adw.HeaderBar`, `Adw.ViewStack`, `Adw.ViewSwitcher`, `Adw.Banner`, `Adw.ExpanderRow`, `Adw.ActionRow`, `Adw.StatusPage`, `Adw.ShortcutsDialog`, `Gtk.Popover`, `Gtk.MenuButton`, `Gtk.DropDown`, `Gtk.Revealer`.
- Use icon buttons for edit, duplicate, complete, delete, show-completed, and menu actions where icons exist. Main menu todo creation command is labeled `New`.
- Main window must be resizable and maximizable.
- App-level warnings, including `All Contexts is an overview...` and unavailable-timer messages, use revealed `Adw.Banner`, auto-hide after about five seconds, and reset timeout when a new warning appears.

Interaction and layout:

- Main menu context/project popover is compact, about 165 px wide.
- Selected context/project is primary-colored, at the top, and excluded from alternatives. Only one alternatives list can expand at a time. Context/project expansion and collapse animate; selecting keeps menu open and smoothly collapses the selected list.
- Project selector is disabled in All Contexts.
- Hidden right-click reveal actions must animate and must not reserve blank layout space.
- Due calendar reveal and dialog height changes must animate and return to compact height.
- Empty-state creation and activatable todo rows use pointer cursors.

Colors:

- Priority palette follows GNOME colors: A `#a51d2d`, B `#c01c28`, C `#ff7800`, D `#f6d32d`, E `#33d17a`, F `#3584e4`, G `#9141ac`, H/default `#9a9996`.
- Due colors range in GNOME style from red for overdue/today through a strong orange-red for tomorrow, then orange/yellow/green/blue/purple/gray for farther dates.

Errors and edge cases:

- If app-state cannot be read, fall back to defaults and save a new app-state.
- If a context todo file does not exist, create it. If todo read/write fails, warn but do not crash.
- Todo reads are cached by context and file modification time, especially for All Contexts.
- Empty or duplicate context/project creation entries show native error styling and do not create duplicates.
- Todo save validates body/project/subproject length, due date, and duplicate content with inline errors.
- Trying to create, duplicate, or run timers in All Contexts shows the context hint. Editing, completing, and deleting existing rows are allowed and save back to the row's owning context.
- Deleting the last remaining context is ignored. Deleting empty contexts/projects needs no confirmation; deleting ones with todos asks.
