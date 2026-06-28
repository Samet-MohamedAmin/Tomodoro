---
name: tomodoro-todos
description: Create, list, edit, complete, delete, and suggest Tomodoro todo.txt tasks from the active Tomodoro context/project state, including dependencies and safe file writes.
---

# Tomodoro Todos

Use this skill to manage Tomodoro todos without editing app source.

## Paths

- Repo: `/var/home/mohamedamin/Desktop/me/todo-pomodoro-vala-restored`
- State root: `${TOMODORO_DATA_ROOT:-/var/home/mohamedamin/.var/app/io.github.samet_mohamedamin.Tomodoro/data/tomodoro}`
- Contexts root: `${TOMODORO_CONTEXTS_ROOT:-/var/home/mohamedamin/contexts}`
- State file: `$STATE_ROOT/app-state.json`
- Todo file: `$CONTEXTS_ROOT/<context-slug>/todo.txt`
- Global skill copies: `/var/home/mohamedamin/.config/opencode/skills/tomodoro-todos/SKILL.md` and `/var/home/mohamedamin/.opencode/skills/tomodoro-todos/SKILL.md`

Legacy `TODO_POMODORO_DATA_ROOT` and `TODO_POMODORO_CONTEXTS_ROOT` matter only when explicitly set.

## Read Current State

Read app-state JSON before writing.

- Context: `.selected_context`, else `.default_context`, else first `.contexts` key, else `work`.
- Project root: `.selected_project`; empty means All, so default to context `.default_project` or `Inbox` unless the user specified a root.
- Subproject: use `.last_todo_subproject` only when the resolved root equals `.last_todo_project`; otherwise use `Default`.
- Priority: `.last_todo_priority` or `C`.
- Due: `.last_todo_due`; empty is valid. If it is before today, use today.
- Dependencies: `.dependencies_enabled`; auto default is `.auto_depend_on_previous_todo`; Project graph display is `.project_dependency_graph`.

Useful commands:

```sh
STATE_ROOT="${TOMODORO_DATA_ROOT:-/var/home/mohamedamin/.var/app/io.github.samet_mohamedamin.Tomodoro/data/tomodoro}"
CONTEXTS_ROOT="${TOMODORO_CONTEXTS_ROOT:-/var/home/mohamedamin/contexts}"
STATE_FILE="$STATE_ROOT/app-state.json"
jq -r '.selected_context // .default_context // "work"' "$STATE_FILE"
jq -r '.selected_project // ""' "$STATE_FILE"
jq -r '.last_todo_project // "Inbox", .last_todo_subproject // "Default", .last_todo_priority // "C", .last_todo_due // ""' "$STATE_FILE"
```

All Contexts is UI-only; writes always target one concrete context.

## Suggestions

- Contexts: `jq -r '.contexts | to_entries[] | "\(.key)\t\(.value.name)"' "$STATE_FILE"`.
- Roots for a context: combine `.contexts[$ctx].default_project`, `.contexts[$ctx].project_icons` keys, and `+Project` tokens in `$CONTEXTS_ROOT/$ctx/todo.txt`; use only the part before `.`.
- Subprojects for a root: read `+Root.Sub` tokens in that context file; include `Default`.
- Parent candidates: active todos in the same exact `Project.Subproject`, excluding the todo being edited. Search candidates by todo body or timer-style summary. Reject only candidates that create a circular dependency chain. When a parent is selected, child priority choices are limited to the parent priority and lower priorities; for example parent `C` allows `C`-`H`.

## Todo Format

One line per todo:

```txt
(C) Body text +Project.Subproject due:2026-07-01 pm:1 pm-done:0 id:<uuid> dep:<uuid>
```

- Priority `(A)`-`(H)`, default `C`.
- Body first letter uppercase, at least three letters.
- Project is `+Main.Subproject`; each segment has at least three letters.
- Due is optional `due:YYYY-MM-DD`.
- Do not create or edit a todo with a due date before today. Clamp stale defaults to today and ask before using a user-requested past date.
- `pm:0` means completed and serializes with leading `x`; `pm>0` means active.
- `pm-done:N` tracks completed pomodoros.
- `id:<uuid>` is required hidden metadata and must never be shown unless debugging.
- `dep:<todo-id>` is optional hidden dependency metadata.
- Recurring templates are separate template lines, not normal todos: `(C) Body +Project.Subproject pm:1 pm-done:0 id:<uuid> recur:daily`, `recur:weekly recur-days:mon,tue`, or `recur:monthly recur-day:21`. Templates have no due date, no dependency, no completed state, and `pm` must be at least `1`.
- Generated recurring instances are normal todos with `recur-parent:<template-id>` and a due date. Their body is the template body only; do not append the date to the body.
- Templates may store `recur-latest:YYYY-MM-DD` so deleted generated instances are not recreated.
- Preserve unknown `key:value` tags. Preserve `cal-uid:<uid>` for active dated todos. Remove it only when clearing due date, completing the todo, or deleting the todo; Tomodoro can also remove old matching events from the deterministic `tomodoro-<id>@io.github.samet_mohamedamin.Tomodoro` UID.

Summary: first phrase ending in `. ` including the period; otherwise the full body.
Calendar event title: `<Context>: <summary>`.
UI note: Tomodoro may display near due dates as `Today`, `Tomorrow`, `In 2 days`, or `In 3 days`, but todo files always store ISO `due:YYYY-MM-DD`.

## Normalization

- Project/context text: trim, remove leading `+`, keep only letters/digits/`-`/`_`; project normalization may also accept `/` as subproject separator and `.` internally.
- Do not write spaces, `+`, `/`, or extra `.` inside project/context segments.
- Uppercase only the first letter. Cap each segment at 32 chars.
- Require at least three letters for body, context names, project root, and subproject.
- Reject duplicate context/project names ignoring case.

## Create

1. Resolve context, root, subproject, priority, due, and pomodoros.
2. If dependencies are enabled and auto-depend is enabled, set `dep:` to the most recent active parent candidate in the same exact subproject unless the user chose another parent or none.
3. Validate dependency rules before writing: if child B depends on parent A, B cannot be higher priority than A (`A` is rank 0, so `rank(B) >= rank(A)`), and B due must be on or after A due when A has a due date. If the chosen parent conflicts with the requested child priority/due, clamp the child priority to the parent priority or lower, keep the result valid, and mention the constraint; never write invalid dependency metadata. Never create circular chains.
4. Generate `id:<uuid>`.
5. Append one normalized line and keep final newline.
6. Update `app-state.json`: `last_todo_priority`, `last_todo_project`, `last_todo_subproject`, and `last_todo_due`.

## Create Recurring Template

1. Resolve context, root, subproject, priority, pomodoros, and schedule.
2. Use `recur:daily`, `recur:weekly recur-days:<tokens>`, or `recur:monthly recur-day:<1-31>`.
3. Weekly tokens are `mon,tue,wed,thu,fri,sat,sun`. If all seven days are selected, write `recur:daily` instead. Weekly needs at least one day. UI labels use plural day names for one or two selected days, for example `Tuesdays`.
4. Do not write `due:`, `dep:`, leading `x`, or `pm:0` on a template. Generate `id:<uuid>` and use `pm>=1`.
5. The app owns `recur-latest:`; preserve it when editing an existing template and omit it when creating/duplicating a template unless specifically maintaining existing state.

## Edit

- Match by hidden `id:` when possible; otherwise require a single clear match.
- Do not change root project after creation. Normal todos keep subproject fixed after creation; recurring templates may change subproject while preserving the root project.
- Do not change `dep:` after creation; existing dependencies are read-only in edit.
- Preserve `id`, `pm-done`, `pm-prev`, `cal-uid`, and unknown tags.
- Do not add or edit recurrence fields on normal todos. Edit recurring templates with the recurring-template rules. For generated recurring instances (`recur-parent:<id>`), only priority, `pm`, completion, and `pm-prev` should change; preserve body, project, due, and parent ID.
- Recompute completion from `pm`.
- Dependency may be selected only during creation. Editing preserves the existing `dep:` value.
- Dependency metadata must satisfy the same priority, due-date, and circular-chain validation as Create. If the requested priority/due value conflicts with the selected parent, keep the value inside the constraint instead of writing invalid metadata.
- Editing a parent todo must not silently break active children. If a parent priority/due edit would make children higher priority than the parent or earlier/undated against a dated parent, warn that saving will overwrite children and cascade the parent priority/due constraints through affected children on save.
- Reject duplicate visible content ignoring hidden id.
- Update last priority/project/subproject/due after successful save.

## Duplicate

- Treat duplicate as Create with a prefilled template, not Edit. Do not keep the source `id`. Allow subproject changes, allow root-project changes when the UI/project context is `All`, and allow choosing `dep:` during creation.

## Complete Or Reactivate

- Complete: if `pm>0`, add/update `pm-prev:<old pm>`, set `pm:0`, and prefix `x`.
- Reactivate: if `pm:0`, restore `pm-prev` or `1`, remove `pm-prev`, remove leading `x`.
- Finish one pomodoro: increment `pm-done`, decrement `pm` when positive, and complete at `pm:0`.
- Recurring template completion does not exist. Generated recurring instances complete like normal todos with `pm:0`; completed or deleted generated instances remove that occurrence from calendar projection. Daily generated instances missed past 12:00 local time on the day after their due date may be cleaned up by the app.

## Dependencies

An active todo with `dep:<id>` is blocked until its unfinished parent chain is completed. Agents should not silently start blocked work; suggest working on the highest unfinished parent first or remove `dep:` only when the user asks. Completed parents do not block. Invalid, self, missing, or circular dependencies should be removed during cleanup. When a parent is completed, the app prefers the next unblocked direct child todo.

Todo ordering tie-breaks use dependency chain first, then creation/file order. Do not sort equal-priority/equal-due todos alphabetically. When `.project_dependency_graph` is true, the app displays normal rows with indentation for parent/child hierarchy and no arrow glyphs. The Recurring order view lists recurring templates grouped by daily/weekly/monthly and can show generated active instances as indented children.

## Delete

Delete by `id:` when possible. If deleting a dependency target, remove stale `dep:` tags from remaining todos. Delete only on explicit user request.

## Safe Writes

Before writing, create `todo.txt.bak.YYYYMMDD-HHMMSS` next to the file. Write a temp file in the same directory, then rename over `todo.txt`. Never rewrite unrelated contexts, never drop unknown tags, and preserve a trailing newline.
