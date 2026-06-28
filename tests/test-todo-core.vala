using Tomodoro;

private void test_parse_and_serialize_todo_txt_fields ()
{
    var id = "123e4567-e89b-12d3-a456-426614174000";
    var dep_id = "223e4567-e89b-12d3-a456-426614174000";
    var todo = parse_todo ("(A) Finish app +todoapp.core due:2026-07-01 pm:3 pm-done:2 id:%s dep:%s recur:weekly custom:x".printf (id, dep_id));

    assert (todo != null);
    assert (todo.id == id);
    assert (todo.dependency_id == dep_id);
    assert (todo.recurrence == RECURRENCE_WEEKLY);
    assert (todo.priority == "A");
    assert (todo.body == "Finish app");
    assert (todo.project == "Todoapp.Core");
    assert (todo.due == "2026-07-01");
    assert (todo.pm == 3);
    assert (todo.pm_done == 2);
    assert (todo.to_line ().contains ("id:%s".printf (id)));
    assert (todo.to_line ().contains ("dep:%s".printf (dep_id)));
    assert (todo.to_line ().contains ("recur:weekly"));
    assert (todo.to_line ().contains ("custom:x"));
}

private void test_monthly_recurrence_clamps_to_valid_day ()
{
    assert (next_recurring_due ("2026-01-31", RECURRENCE_MONTHLY, 31) == "2026-02-28");
    assert (next_recurring_due ("2026-02-28", RECURRENCE_MONTHLY, 31) == "2026-03-31");
    assert (next_recurring_due ("2028-01-31", RECURRENCE_MONTHLY, 31) == "2028-02-29");
    assert (next_recurring_due ("2026-06-23", RECURRENCE_WEEKLY, 0) == "2026-06-30");
    assert (next_recurring_due ("2026-06-23", RECURRENCE_DAILY, 0) == "2026-06-24");
}

private void test_finish_pomodoro_updates_done_and_remaining ()
{
    var todo = new Todo ();
    todo.body = "Work";
    todo.pm = 1;
    todo.pm_done = 4;

    todo.finish_pomodoro ();
    assert (todo.pm == 0);
    assert (todo.pm_done == 5);
    assert (todo.completed);

    todo.finish_pomodoro ();
    assert (todo.pm == 0);
    assert (todo.pm_done == 6);
    assert (todo.completed);
}

private void test_zero_pomodoros_parse_as_completed ()
{
    var todo = parse_todo ("(C) Done by count +Inbox pm:0");

    assert (todo != null);
    assert (todo.pm == 0);
    assert (todo.completed);
    assert (todo.to_line ().has_prefix ("x "));
}

private void test_positive_pomodoros_parse_as_active ()
{
    var todo = parse_todo ("x (C) Still has work +Inbox pm:2");

    assert (todo != null);
    assert (todo.pm == 2);
    assert (!todo.completed);
    assert (!todo.to_line ().has_prefix ("x "));
}

private void test_positive_pomodoros_serialize_as_active ()
{
    var todo = new Todo ();
    todo.body = "Still active";
    todo.project = "Inbox";
    todo.pm = 2;
    todo.completed = true;

    assert (!todo.to_line ().has_prefix ("x "));
}

private void test_todo_body_summary_uses_first_phrase ()
{
    assert (TODO_SUMMARY_MAX_CHARS == "Give access to team platform dev dev.".length);
    assert (has_explicit_todo_summary ("Give access to team dev. in project sdf"));
    assert (todo_body_summary ("Give access to team dev. in project sdf") == "Give access to team dev.");
    assert (!has_explicit_todo_summary ("Give access to team dev"));
    assert (todo_body_summary ("Give access to team dev") == "Give access to team dev");
}

private void test_todo_display_summary_trims_at_word_boundary ()
{
    var todo = new Todo ();
    todo.body = "Give access to team platform dev dev. in project sdf asdsadsa";

    assert (todo_display_summary (todo, TODO_SUMMARY_MAX_CHARS) == "Give access to team platform dev dev.");
    assert (todo_display_summary (todo, 20) == "Give access to team");
}

private void test_structure_name_input_sanitization ()
{
    assert (sanitize_structure_name_input ("new project+bad name", PROJECT_PART_MAX_LENGTH) == "Newprojectbadname");
    assert (sanitize_structure_name_input ("1context_name", CONTEXT_NAME_MAX_LENGTH) == "1Context_name");
    assert (sanitize_structure_name_input ("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz", 8) == "Abcdefgh");
    assert (valid_context_name_text ("Work_1"));
    assert (!valid_context_name_text ("x1"));
}

private void test_completion_restore_previous_pomodoros ()
{
    var todo = new Todo ();
    todo.body = "Finish report";
    todo.project = "Work.Report";
    todo.pm = 3;

    todo.complete_with_zero_pm ();
    assert (todo.completed);
    assert (todo.pm == 0);
    assert (todo.to_line ().contains ("pm-prev:3"));

    var parsed = parse_todo (todo.to_line ());
    assert (parsed != null);
    assert (parsed.completed);
    assert (parsed.pm == 0);
    assert (parsed.previous_pm_or_default (1) == 3);

    parsed.restore_pm_after_completion ();
    assert (!parsed.completed);
    assert (parsed.pm == 3);
    assert (!parsed.to_line ().contains ("pm-prev:"));

    var legacy = parse_todo ("x (C) Legacy done +Inbox pm:0");
    assert (legacy != null);
    legacy.restore_pm_after_completion ();
    assert (!legacy.completed);
    assert (legacy.pm == 1);
}

private void test_calendar_uid_tag_is_hidden_metadata ()
{
    var todo = parse_todo ("(C) Sync calendar +Inbox due:2026-07-01 pm:1 cal-uid:tomodoro-123@io.github.samet_mohamedamin.Tomodoro");
    assert (todo != null);
    assert (todo.calendar_uid () == "tomodoro-123@io.github.samet_mohamedamin.Tomodoro");
    assert (todo.to_line ().contains ("cal-uid:tomodoro-123@io.github.samet_mohamedamin.Tomodoro"));

    todo.clear_calendar_uid ();
    assert (todo.calendar_uid () == "");
    assert (!todo.to_line ().contains ("cal-uid:"));
}

private void test_completed_due_todo_removes_calendar_uid_on_save ()
{
    var previous = parse_todo ("(C) Sync calendar +Inbox due:2026-07-01 pm:1 id:123e4567-e89b-12d3-a456-426614174000 cal-uid:tomodoro-123@io.github.samet_mohamedamin.Tomodoro");
    var current = parse_todo ("x (C) Sync calendar +Inbox due:2026-07-01 pm:0 id:123e4567-e89b-12d3-a456-426614174000");
    assert (previous != null);
    assert (current != null);

    var removed = CalendarSync.prepare_for_save ({previous}, {current});

    assert (removed.length == 1);
    assert (removed[0].calendar_uid () == "tomodoro-123@io.github.samet_mohamedamin.Tomodoro");
    assert (current.calendar_uid () == "");
}

private void test_removed_due_todo_uses_deterministic_calendar_uid ()
{
    var previous = parse_todo ("(C) Delete calendar event +Inbox due:2026-07-01 pm:1 id:123e4567-e89b-12d3-a456-426614174000");
    assert (previous != null);

    var removed = CalendarSync.prepare_for_save ({previous}, {});

    assert (removed.length == 1);
    assert (removed[0].calendar_uid () == "tomodoro-123e4567-e89b-12d3-a456-426614174000@io.github.samet_mohamedamin.Tomodoro");
}

private void test_cleared_due_todo_uses_deterministic_calendar_uid ()
{
    var previous = parse_todo ("(C) Clear due event +Inbox due:2026-07-01 pm:1 id:123e4567-e89b-12d3-a456-426614174000");
    var current = parse_todo ("(C) Clear due event +Inbox pm:1 id:123e4567-e89b-12d3-a456-426614174000");
    assert (previous != null);
    assert (current != null);

    var removed = CalendarSync.prepare_for_save ({previous}, {current});

    assert (removed.length == 1);
    assert (removed[0].calendar_uid () == "tomodoro-123e4567-e89b-12d3-a456-426614174000@io.github.samet_mohamedamin.Tomodoro");
    assert (current.calendar_uid () == "");
}

private void test_due_update_keeps_calendar_uid_for_upsert ()
{
    var previous = parse_todo ("(C) Move due event +Inbox due:2026-07-01 pm:1 id:123e4567-e89b-12d3-a456-426614174000");
    var current = parse_todo ("(C) Move due event +Inbox due:2026-07-02 pm:1 id:123e4567-e89b-12d3-a456-426614174000");
    assert (previous != null);
    assert (current != null);

    var removed = CalendarSync.prepare_for_save ({previous}, {current});

    assert (removed.length == 0);
    assert (current.calendar_uid () == "tomodoro-123e4567-e89b-12d3-a456-426614174000@io.github.samet_mohamedamin.Tomodoro");
}

private void test_recurring_calendar_projects_next_40_days ()
{
    var id = "123e4567-e89b-12d3-a456-426614174000";
    var today = today_local ();
    var todo = parse_todo ("(C) Daily review +Inbox due:%s pm:1 id:%s recur:daily".printf (today.format ("%F"), id));
    assert (todo != null);

    var dates = CalendarSync.recurring_event_dates (todo);

    assert (dates.length == 40);
    assert (dates[0] == today.format ("%F"));
    assert (dates[39] == today.add_days (39).format ("%F"));
}

private void test_recurring_disable_removes_projected_events ()
{
    var id = "123e4567-e89b-12d3-a456-426614174000";
    var today = today_local ().format ("%F");
    var previous = parse_todo ("(C) Daily review +Inbox due:%s pm:1 id:%s recur:daily".printf (today, id));
    var current = parse_todo ("(C) Daily review +Inbox due:%s pm:1 id:%s".printf (today, id));
    assert (previous != null);
    assert (current != null);

    var removed = CalendarSync.prepare_for_save ({previous}, {current});

    assert (removed.length == 40);
    assert (removed[0].calendar_uid ().contains ("tomodoro-%s-".printf (id)));
    assert (current.calendar_uid () == "tomodoro-%s@io.github.samet_mohamedamin.Tomodoro".printf (id));
}

private void test_due_todo_event_summary_uses_context_prefix ()
{
    var todo = parse_todo ("(C) Give access to team dev. in project sdf +Inbox due:2026-07-01 pm:1 id:123e4567-e89b-12d3-a456-426614174000");
    assert (todo != null);

    assert (CalendarSync.event_summary ("Work", todo) == "Work: Give access to team dev.");
}

private bool removed_contains_calendar_uid (Todo[] removed, string uid)
{
    foreach (var todo in removed) {
        if (todo.calendar_uid () == uid) {
            return true;
        }
    }
    return false;
}

private void test_calendar_remove_all_collects_known_uids ()
{
    var today = today_local ();
    var stored_id = "123e4567-e89b-12d3-a456-426614174000";
    var due_id = "223e4567-e89b-12d3-a456-426614174000";
    var recurring_id = "323e4567-e89b-12d3-a456-426614174000";
    var stored = parse_todo ("(C) Stored sync +Inbox due:%s pm:1 id:%s cal-uid:tomodoro-custom@io.github.samet_mohamedamin.Tomodoro".printf (today.format ("%F"), stored_id));
    var due = parse_todo ("(C) Deterministic sync +Inbox due:%s pm:1 id:%s".printf (today.format ("%F"), due_id));
    var recurring = parse_todo ("(C) Daily review +Inbox pm:1 id:%s recur:daily".printf (recurring_id));
    assert (stored != null);
    assert (due != null);
    assert (recurring != null);

    var removed = CalendarSync.prepare_remove_all ({stored, due, recurring});

    assert (stored.calendar_uid () == "");
    assert (removed.length == 42);
    assert (removed_contains_calendar_uid (removed, "tomodoro-custom@io.github.samet_mohamedamin.Tomodoro"));
    assert (removed_contains_calendar_uid (removed, "tomodoro-%s@io.github.samet_mohamedamin.Tomodoro".printf (due_id)));
    assert (removed_contains_calendar_uid (removed, "tomodoro-%s-%s@io.github.samet_mohamedamin.Tomodoro".printf (recurring_id, today.format ("%Y%m%d"))));
}

private void test_due_color_ranges_are_distinct ()
{
    var today = today_local ();
    assert (parse_int_safe ("08", -1) == 8);
    assert (parse_int_safe ("09", -1) == 9);
    assert (parse_date ("2026-07-08") != null);
    assert (due_color (today.add_days (1).format ("%F")) == "#e66100");

    string[] colors = {
        due_color (today.add_days (-1).format ("%F")),
        due_color (today.format ("%F")),
        due_color (today.add_days (1).format ("%F")),
        due_color (today.add_days (2).format ("%F")),
        due_color (today.add_days (3).format ("%F")),
        due_color (today.add_days (4).format ("%F")),
        due_color (today.add_days (5).format ("%F")),
        due_color (today.add_days (6).format ("%F")),
        due_color (today.add_days (8).format ("%F")),
        due_color (today.add_days (15).format ("%F")),
        due_color (today.add_days (32).format ("%F")),
        due_color (today.add_days (120).format ("%F")),
    };

    for (int left = 0; left < colors.length; left++) {
        for (int right = left + 1; right < colors.length; right++) {
            assert (colors[left] != colors[right]);
        }
    }
}

private void test_due_input_relative_labels_and_past_detection ()
{
    var today = today_local ();

    assert (due_input_to_iso ("today") == today.format ("%F"));
    assert (due_input_to_iso ("Tomorrow") == today.add_days (1).format ("%F"));
    assert (due_input_to_iso ("in 2 days") == today.add_days (2).format ("%F"));
    assert (due_input_to_iso ("In 3 days") == today.add_days (3).format ("%F"));
    assert (due_input_display_text (today.format ("%F")) == "Today");
    assert (due_input_display_text (today.add_days (1).format ("%F")) == "Tomorrow");
    assert (due_input_display_text (today.add_days (2).format ("%F")) == "In 2 days");
    assert (due_input_display_text (today.add_days (3).format ("%F")) == "In 3 days");
    assert (date_is_before_today (today.add_days (-1).format ("%F")));
    assert (!date_is_before_today (today.format ("%F")));
    assert (!due_input_is_valid ("later"));
}

private void test_priority_colors_follow_gnome_palette_order ()
{
    assert (priority_color ("A") == "#a51d2d");
    assert (priority_color ("B") == "#c01c28");
    assert (priority_color ("C") == "#ff7800");
    assert (priority_color ("D") == "#f6d32d");
    assert (priority_color ("E") == "#33d17a");
    assert (priority_color ("F") == "#3584e4");
    assert (priority_color ("G") == "#9141ac");
    assert (priority_color ("H") == "#9a9996");
}

private void test_store_records_pomodoro_history ()
{
    var tmp = GLib.DirUtils.make_tmp ("todo-pomodoro-test-XXXXXX");
    var store = new Store (tmp);
    store.record_pomodoro ("work", "Inbox", "classic");

    var history = store.pomodoro_history ();
    assert (history.length == 1);
    assert (history[0].context == "work");
    assert (history[0].project == "Inbox");
    assert (history[0].profile == "classic");
}

private void test_store_persists_compact_timer_actions ()
{
    var tmp = GLib.DirUtils.make_tmp ("todo-pomodoro-test-XXXXXX");
    var store = new Store (tmp);

    assert (store.compact_timer_actions);
    store.compact_timer_actions = false;
    store.save ();

    var reloaded = new Store (tmp);
    assert (!reloaded.compact_timer_actions);
}

private void test_store_persists_show_delete_button ()
{
    var tmp = GLib.DirUtils.make_tmp ("todo-pomodoro-test-XXXXXX");
    var store = new Store (tmp);

    assert (store.show_delete_button);
    store.show_delete_button = false;
    store.save ();

    var reloaded = new Store (tmp);
    assert (!reloaded.show_delete_button);
}

private void test_store_uses_separate_contexts_root ()
{
    var state_root = GLib.DirUtils.make_tmp ("todo-pomodoro-test-XXXXXX");
    var contexts_root = GLib.DirUtils.make_tmp ("todo-pomodoro-test-XXXXXX");
    var store = new Store (state_root, contexts_root);
    var context = store.selected_context ();

    store.save_todos ({parse_todo ("(C) Check storage +Inbox pm:1")}, context);

    assert (GLib.FileUtils.test (GLib.Path.build_filename (state_root, "app-state.json"), GLib.FileTest.EXISTS));
    assert (GLib.FileUtils.test (GLib.Path.build_filename (contexts_root, context.slug, "todo.txt"), GLib.FileTest.EXISTS));
    assert (!GLib.FileUtils.test (GLib.Path.build_filename (state_root, "contexts", context.slug, "todo.txt"), GLib.FileTest.EXISTS));
}

private void test_store_persists_selected_project ()
{
    var tmp = GLib.DirUtils.make_tmp ("todo-pomodoro-test-XXXXXX");
    var store = new Store (tmp);

    assert (store.selected_project_root == "");
    store.set_selected_project ("alpha.build");
    assert (store.selected_project_root == "Alpha");

    var reloaded = new Store (tmp);
    assert (reloaded.selected_project_root == "Alpha");

    reloaded.set_selected_project (null);
    var cleared = new Store (tmp);
    assert (cleared.selected_project_root == "");
}

private void test_store_persists_window_view_and_todo_selection ()
{
    var tmp = GLib.DirUtils.make_tmp ("todo-pomodoro-test-XXXXXX");
    var store = new Store (tmp);
    var todo_id = "123e4567-e89b-12d3-a456-426614174000";

    store.set_window_size (1040, 720);
    store.update_selected_view ("pomodoro");
    store.update_selected_todo_id (todo_id);
    store.update_selected_order_mode (2);

    var reloaded = new Store (tmp);
    assert (reloaded.window_width == 1040);
    assert (reloaded.window_height == 720);
    assert (reloaded.selected_view == "pomodoro");
    assert (reloaded.selected_todo_id == todo_id);
    assert (reloaded.selected_order_mode == "project");
    assert (reloaded.selected_order_index () == 2);
    reloaded.update_selected_order_mode (3);
    var recurring_order = new Store (tmp);
    assert (recurring_order.selected_order_mode == "recurring");
    assert (recurring_order.selected_order_index () == 3);
    recurring_order.update_selected_order_mode (9);
    var invalid_order = new Store (tmp);
    assert (invalid_order.selected_order_mode == "due");
    assert (invalid_order.selected_order_index () == 1);
    reloaded.update_last_todo_defaults ("a", "Alpha", "platform-dev", "");

    var defaults = new Store (tmp);
    assert (defaults.last_todo_priority == "A");
    assert (defaults.last_todo_project_root == "Alpha");
    assert (defaults.last_todo_subproject == "Platform-dev");
    assert (defaults.last_todo_subproject_for_project ("Alpha") == "Platform-dev");
    assert (defaults.last_todo_subproject_for_project ("Beta") == "Default");

    reloaded.update_ui_state (100, 120, "bad-view", "bad id!", 9);
    reloaded.update_last_todo_defaults ("z", "+", "+", "bad-date");

    var sanitized = new Store (tmp);
    assert (sanitized.selected_view == "todos");
    assert (sanitized.selected_todo_id == "");
    assert (sanitized.selected_order_mode == "due");
    assert (sanitized.selected_order_index () == 1);
    assert (sanitized.last_todo_priority == "C");
    assert (sanitized.last_todo_project_root == "Inbox");
    assert (sanitized.last_todo_subproject == "Default");
    assert (sanitized.last_todo_due == "");
    assert (sanitized.window_width == 360);
    assert (sanitized.window_height == 360);
}

private void test_store_persists_due_default_and_dependency_preferences ()
{
    var tmp = GLib.DirUtils.make_tmp ("todo-pomodoro-test-XXXXXX");
    var store = new Store (tmp);

    store.update_last_todo_defaults ("B", "Work", "Plan", today_local ().add_days (-2).format ("%F"));
    store.dependencies_enabled = false;
    store.auto_depend_on_previous_todo = true;
    store.project_dependency_graph = true;
    store.update_calendar_events_enabled (false);
    store.save ();

    var reloaded = new Store (tmp);
    assert (reloaded.last_todo_due == today_local ().format ("%F"));
    assert (reloaded.last_todo_due_for_default () == today_local ().format ("%F"));
    assert (!reloaded.dependencies_enabled);
    assert (reloaded.auto_depend_on_previous_todo);
    assert (reloaded.project_dependency_graph);
    assert (!reloaded.calendar_events_enabled);

    reloaded.update_last_todo_defaults ("B", "Work", "Plan", "");
    var empty_due = new Store (tmp);
    assert (empty_due.last_todo_due == "");
    assert (empty_due.last_todo_due_for_default () == "");
}

private void test_store_includes_testing_profile ()
{
    var tmp = GLib.DirUtils.make_tmp ("todo-pomodoro-test-XXXXXX");
    var store = new Store (tmp);

    var found = false;
    foreach (var profile in store.pomodoro_profiles ()) {
        if (profile.slug != "testing") {
            continue;
        }

        found = true;
        assert (profile.name == "Testing");
        assert (profile.work_duration_seconds () == 10);
        assert (profile.short_break_duration_seconds () == 5);
        assert (profile.long_break_duration_seconds () == 5);
        assert (profile.summary () == "Testing · 10 sec / 5 sec / 5 sec");
    }

    assert (found);
}

private void test_store_sanitizes_loaded_todos ()
{
    var tmp = GLib.DirUtils.make_tmp ("todo-pomodoro-test-XXXXXX");
    var store = new Store (tmp);
    var context = store.selected_context ();
    var context_dir = GLib.Path.build_filename (tmp, "contexts", context.slug);
    GLib.DirUtils.create_with_parents (context_dir, 0755);
    var path = GLib.Path.build_filename (context_dir, "todo.txt");
    var duplicate_id = "123e4567-e89b-12d3-a456-426614174000";
    var missing_dependency_id = "999e4567-e89b-12d3-a456-426614174000";
    var circular_a_id = "223e4567-e89b-12d3-a456-426614174000";
    var circular_b_id = "323e4567-e89b-12d3-a456-426614174000";
    GLib.FileUtils.set_contents (
        path,
        "(c) legacy body +ab.x due:not-a-date pm:-5\n" +
        "(C) First real +Project.tool pm:2 id:%s\n".printf (duplicate_id) +
        "(C) Second real +Project.tool pm:3 id:%s dep:%s\n".printf (duplicate_id, missing_dependency_id) +
        "(C) Circular A +Project.tool pm:1 id:%s dep:%s\n".printf (circular_a_id, circular_b_id) +
        "(C) Circular B +Project.tool pm:1 id:%s dep:%s\n".printf (circular_b_id, circular_a_id)
    );

    var todos = store.load_todos (context);

    assert (todos.length == 5);
    assert (todos[0].id != "");
    assert (todos[0].project == "Inbox.Default");
    assert (todos[0].due == "");
    assert (todos[0].pm == 0);
    assert (todos[0].completed);
    assert (todos[1].id == duplicate_id);
    assert (todos[2].id != duplicate_id);
    assert (todos[0].id != todos[1].id);
    assert (todos[0].id != todos[2].id);
    assert (todos[1].id != todos[2].id);
    assert (todos[2].dependency_id == "");
    assert (!todo_has_dependency (todos[3]) || !todo_depends_on_test (todos[3], todos[3].id, todos));
    assert (!todo_has_dependency (todos[4]) || !todo_depends_on_test (todos[4], todos[4].id, todos));

    string rewritten;
    GLib.FileUtils.get_contents (path, out rewritten);
    assert (rewritten.contains ("+Inbox.Default"));
    assert (rewritten.contains ("id:"));
    assert (!rewritten.contains ("due:not-a-date"));
    assert (!rewritten.contains ("dep:%s".printf (missing_dependency_id)));
}

private void test_store_generates_recurring_template_instance ()
{
    var tmp = GLib.DirUtils.make_tmp ("todo-pomodoro-test-XXXXXX");
    var store = new Store (tmp);
    var context = store.selected_context ();
    var id = "123e4567-e89b-12d3-a456-426614174000";
    var today = today_local ().format ("%F");
    var today_day = today_local ().get_day_of_month ();
    var todo = parse_todo ("(C) Pay invoice +Inbox.Default pm:2 id:%s recur:monthly recur-day:%d".printf (id, today_day));
    assert (todo != null);

    store.save_todos ({todo}, context);
    var todos = store.load_todos (context);

    assert (todos.length == 2);
    assert (todos[0].id == id);
    assert (todos[0].recurrence == RECURRENCE_MONTHLY);
    assert (todos[0].recurrence_anchor_day == today_day);
    assert (todos[0].due == "");
    assert (todos[0].pm == 2);
    assert (!todos[0].completed);
    assert (todos[0].recurrence_latest_due == today);

    assert (todos[1].recurrence_parent_id == id);
    assert (todos[1].due == today);
    assert (todos[1].body == "Pay invoice");
    assert (todos[1].pm == 2);
    assert (!todos[1].completed);
}

private bool todo_depends_on_test (Todo todo, string target_id, Todo[] todos)
{
    var current_id = todo.dependency_id;
    var seen = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
    while (current_id != "") {
        if (current_id == target_id || seen.lookup (current_id) != null) {
            return true;
        }
        seen.insert (current_id, current_id);

        Todo? current = null;
        foreach (var candidate in todos) {
            if (candidate.id == current_id) {
                current = candidate;
                break;
            }
        }
        if (current == null) {
            return false;
        }
        current_id = current.dependency_id;
    }
    return false;
}

private void test_project_delete_cleans_metadata ()
{
    var tmp = GLib.DirUtils.make_tmp ("todo-pomodoro-test-XXXXXX");
    var store = new Store (tmp);
    var context = store.selected_context ();
    context.set_project_icon ("Alpha", "folder-symbolic");
    context.set_project_icon ("Alpha.Build", "folder-symbolic");
    context.set_project_icon ("Beta", "folder-symbolic");
    store.record_pomodoro ("work", "Alpha", "classic");
    store.record_pomodoro ("work", "Alpha.Build", "classic");
    store.record_pomodoro ("work", "Beta", "classic");

    store.delete_project_icons (context, "Alpha");
    store.delete_project_history ("work", "Alpha");

    assert (context.project_icons.lookup ("Alpha") == null);
    assert (context.project_icons.lookup ("Alpha.Build") == null);
    assert (context.project_icons.lookup ("Beta") != null);

    var history = store.pomodoro_history ();
    assert (history.length == 1);
    assert (history[0].project == "Beta");
}

private void test_project_roots_after_delete_use_existing_roots ()
{
    string[] projects = {"Inbox", "Inbox.Default", "Beta", "Gamma.Plan"};
    var roots = project_roots_from_projects (projects);

    assert (roots.length == 3);
    assert (roots[0] == "Inbox");
    assert (roots[1] == "Beta");
    assert (roots[2] == "Gamma");

    var remaining = remaining_project_roots_after_delete (projects, "Inbox");
    assert (remaining.length == 2);
    assert (remaining[0] == "Beta");
    assert (remaining[1] == "Gamma");
}

public int main (string[] args)
{
    GLib.Test.init (ref args);
    GLib.Test.add_func ("/todo/parse-and-serialize", test_parse_and_serialize_todo_txt_fields);
    GLib.Test.add_func ("/todo/monthly-recurrence-clamps", test_monthly_recurrence_clamps_to_valid_day);
    GLib.Test.add_func ("/todo/finish-pomodoro", test_finish_pomodoro_updates_done_and_remaining);
    GLib.Test.add_func ("/todo/zero-pomodoros-completed", test_zero_pomodoros_parse_as_completed);
    GLib.Test.add_func ("/todo/positive-pomodoros-active", test_positive_pomodoros_parse_as_active);
    GLib.Test.add_func ("/todo/positive-pomodoros-serialize-active", test_positive_pomodoros_serialize_as_active);
    GLib.Test.add_func ("/todo/body-summary", test_todo_body_summary_uses_first_phrase);
    GLib.Test.add_func ("/todo/display-summary-word-boundary", test_todo_display_summary_trims_at_word_boundary);
    GLib.Test.add_func ("/todo/structure-name-input-sanitization", test_structure_name_input_sanitization);
    GLib.Test.add_func ("/todo/completion-restore-previous-pomodoros", test_completion_restore_previous_pomodoros);
    GLib.Test.add_func ("/todo/calendar-uid-tag", test_calendar_uid_tag_is_hidden_metadata);
    GLib.Test.add_func ("/todo/completed-due-removes-calendar-uid", test_completed_due_todo_removes_calendar_uid_on_save);
    GLib.Test.add_func ("/todo/removed-due-calendar-uid", test_removed_due_todo_uses_deterministic_calendar_uid);
    GLib.Test.add_func ("/todo/cleared-due-calendar-uid", test_cleared_due_todo_uses_deterministic_calendar_uid);
    GLib.Test.add_func ("/todo/due-update-calendar-upsert", test_due_update_keeps_calendar_uid_for_upsert);
    GLib.Test.add_func ("/todo/recurring-calendar-next-40-days", test_recurring_calendar_projects_next_40_days);
    GLib.Test.add_func ("/todo/recurring-disable-calendar-remove", test_recurring_disable_removes_projected_events);
    GLib.Test.add_func ("/todo/calendar-event-summary-context", test_due_todo_event_summary_uses_context_prefix);
    GLib.Test.add_func ("/todo/calendar-remove-all-uids", test_calendar_remove_all_collects_known_uids);
    GLib.Test.add_func ("/todo/due-colors", test_due_color_ranges_are_distinct);
    GLib.Test.add_func ("/todo/due-input-relative-labels", test_due_input_relative_labels_and_past_detection);
    GLib.Test.add_func ("/todo/priority-colors", test_priority_colors_follow_gnome_palette_order);
    GLib.Test.add_func ("/store/record-pomodoro", test_store_records_pomodoro_history);
    GLib.Test.add_func ("/store/compact-timer-actions", test_store_persists_compact_timer_actions);
    GLib.Test.add_func ("/store/show-delete-button", test_store_persists_show_delete_button);
    GLib.Test.add_func ("/store/separate-contexts-root", test_store_uses_separate_contexts_root);
    GLib.Test.add_func ("/store/selected-project", test_store_persists_selected_project);
    GLib.Test.add_func ("/store/window-view-todo-selection", test_store_persists_window_view_and_todo_selection);
    GLib.Test.add_func ("/store/due-default-and-dependency-preferences", test_store_persists_due_default_and_dependency_preferences);
    GLib.Test.add_func ("/store/testing-profile", test_store_includes_testing_profile);
    GLib.Test.add_func ("/store/sanitizes-loaded-todos", test_store_sanitizes_loaded_todos);
    GLib.Test.add_func ("/store/generates-recurring-template-instance", test_store_generates_recurring_template_instance);
    GLib.Test.add_func ("/store/project-delete-cleans-metadata", test_project_delete_cleans_metadata);
    GLib.Test.add_func ("/project/roots-after-delete", test_project_roots_after_delete_use_existing_roots);
    return GLib.Test.run ();
}
