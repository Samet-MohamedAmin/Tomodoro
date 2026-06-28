namespace Tomodoro
{
    private const int DEFAULT_LONG_BREAK_MULTIPLIER = 3;

    private class TodoFileCache : GLib.Object
    {
        public Todo[] todos = {};
        public int64 modified_at = 0;
    }

    public class Store : GLib.Object
    {
        public string data_dir { get; private set; }
        public string contexts_root { get; private set; }
        public string config_path { get; private set; }
        public string selected_context_slug { get; private set; default = "work"; }
        public string default_context_slug { get; private set; default = "work"; }
        public string selected_project_root { get; private set; default = ""; }
        public string selected_view { get; private set; default = "todos"; }
        public string selected_todo_id { get; private set; default = ""; }
        public string selected_order_mode { get; private set; default = "due"; }
        public string last_todo_priority { get; private set; default = "C"; }
        public string last_todo_project_root { get; private set; default = "Inbox"; }
        public string last_todo_subproject { get; private set; default = "Default"; }
        public string last_todo_due { get; private set; default = ""; }
        public string selected_profile_slug { get; private set; default = "classic"; }
        public int window_width { get; private set; default = 900; }
        public int window_height { get; private set; default = 640; }
        public bool notify_due_today { get; set; default = true; }
        public bool notify_due_tomorrow { get; set; default = true; }
        public int due_cutoff_hour { get; set; default = 18; }
        public bool repeat_pomodoro_icons { get; set; default = true; }
        public bool compact_timer_actions { get; set; default = true; }
        public bool show_delete_button { get; set; default = true; }
        public bool dependencies_enabled { get; set; default = true; }
        public bool auto_depend_on_previous_todo { get; set; default = false; }
        public bool project_dependency_graph { get; set; default = false; }
        public bool calendar_events_enabled { get; private set; default = true; }

        private ContextConfig[] context_items = {};
        private PomodoroProfile[] profile_items = {};
        private PomodoroHistoryEntry[] history_items = {};
        private GLib.HashTable<string, TodoFileCache> todo_cache = new GLib.HashTable<string, TodoFileCache> (GLib.str_hash, GLib.str_equal);

        public Store (string? data_root = null, string? contexts_root = null)
        {
            this.data_dir = data_root ?? default_data_dir ();
            this.contexts_root = contexts_root ?? (data_root == null ? default_contexts_root () : GLib.Path.build_filename (this.data_dir, "contexts"));
            this.config_path = GLib.Path.build_filename (this.data_dir, "app-state.json");
            this.load ();
        }

        public ContextConfig[] contexts ()
        {
            return this.context_items;
        }

        public PomodoroProfile[] pomodoro_profiles ()
        {
            return this.profile_items;
        }

        public PomodoroHistoryEntry[] pomodoro_history ()
        {
            return this.history_items;
        }

        public ContextConfig selected_context ()
        {
            foreach (var context in this.context_items) {
                if (context.slug == this.selected_context_slug) {
                    return context;
                }
            }

            if (this.context_items.length == 0) {
                return this.add_context ("Work", "briefcase-symbolic");
            }

            return this.context_items[0];
        }

        public ContextConfig context_by_slug (string slug) throws GLib.Error
        {
            foreach (var context in this.context_items) {
                if (context.slug == slug) {
                    return context;
                }
            }
            throw new StoreError.NOT_FOUND ("Unknown context: %s", slug);
        }

        public void set_selected_context (string slug)
        {
            this.selected_context_slug = slug;
            this.save ();
        }

        public void set_selected_project (string? project)
        {
            var next = normalize_selected_project_root (project);
            if (this.selected_project_root == next) {
                return;
            }

            this.selected_project_root = next;
            this.save ();
        }

        public void update_selected_view (string? view)
        {
            var next = normalize_selected_view (view);
            if (this.selected_view == next) {
                return;
            }

            this.selected_view = next;
            this.save ();
        }

        public void update_selected_todo_id (string? id)
        {
            var next = id == null || !is_valid_todo_id (id) ? "" : id.down ();
            if (this.selected_todo_id == next) {
                return;
            }

            this.selected_todo_id = next;
            this.save ();
        }

        public uint selected_order_index ()
        {
            return order_mode_index (this.selected_order_mode);
        }

        public void update_selected_order_mode (uint mode)
        {
            var next = order_mode_slug (mode);
            if (this.selected_order_mode == next) {
                return;
            }

            this.selected_order_mode = next;
            this.save ();
        }

        public string last_todo_subproject_for_project (string project)
        {
            var root = project_root (normalize_project (project, "Inbox"));
            if (root != "" && root == this.last_todo_project_root && this.last_todo_subproject != "") {
                return this.last_todo_subproject;
            }
            return "Default";
        }

        public string last_todo_due_for_default ()
        {
            if (!is_valid_date (this.last_todo_due)) {
                return "";
            }
            return date_delta_days (this.last_todo_due) < 0 ? today_local ().format ("%F") : this.last_todo_due;
        }

        public void update_last_todo_defaults (string priority, string project, string subproject, string due)
        {
            var next_priority = normalize_priority_value (priority);
            var next_project = project_root (normalize_project (project, "Inbox"));
            var next_subproject = normalize_last_todo_subproject (subproject);
            var next_due = normalize_last_todo_due (due);
            if (this.last_todo_priority == next_priority
                && this.last_todo_project_root == next_project
                && this.last_todo_subproject == next_subproject
                && this.last_todo_due == next_due) {
                return;
            }

            this.last_todo_priority = next_priority;
            this.last_todo_project_root = next_project;
            this.last_todo_subproject = next_subproject;
            this.last_todo_due = next_due;
            this.save ();
        }

        public void set_window_size (int width, int height)
        {
            var next_width = int.max (360, width);
            var next_height = int.max (360, height);
            if (this.window_width == next_width && this.window_height == next_height) {
                return;
            }

            this.window_width = next_width;
            this.window_height = next_height;
            this.save ();
        }

        public void update_ui_state (int width, int height, string? view, string? todo_id, uint order_mode)
        {
            var changed = false;
            var next_width = int.max (360, width);
            var next_height = int.max (360, height);
            var next_view = normalize_selected_view (view);
            var next_todo_id = normalize_selected_todo_id (todo_id);
            var next_order_mode = order_mode_slug (order_mode);

            if (this.window_width != next_width) {
                this.window_width = next_width;
                changed = true;
            }
            if (this.window_height != next_height) {
                this.window_height = next_height;
                changed = true;
            }
            if (this.selected_view != next_view) {
                this.selected_view = next_view;
                changed = true;
            }
            if (this.selected_todo_id != next_todo_id) {
                this.selected_todo_id = next_todo_id;
                changed = true;
            }
            if (this.selected_order_mode != next_order_mode) {
                this.selected_order_mode = next_order_mode;
                changed = true;
            }

            if (changed) {
                this.save ();
            }
        }

        public ContextConfig add_context (string name, string icon = "folder-symbolic")
        {
            var slug = unique_context_slug (slugify (name), this.context_items);
            var context = new ContextConfig ();
            context.slug = slug;
            context.name = name.strip () == "" ? slug : uppercase_first_letter (name.strip ());
            context.icon = icon.strip () == "" ? "folder-symbolic" : icon.strip ();
            context.default_project = "Inbox";
            context.set_project_icon ("Inbox", "mail-inbox-symbolic");
            this.context_items += context;

            ensure_dir (context_dir (context));
            this.save ();
            return context;
        }

        public void delete_context (string slug)
        {
            if (this.context_items.length <= 1) {
                return;
            }

            ContextConfig[] next = {};
            foreach (var context in this.context_items) {
                if (context.slug != slug) {
                    next += context;
                }
            }
            this.context_items = next;

            PomodoroHistoryEntry[] history = {};
            foreach (var item in this.history_items) {
                if (item.context != slug) {
                    history += item;
                }
            }
            this.history_items = history;

            if (this.selected_context_slug == slug || this.default_context_slug == slug) {
                this.selected_context_slug = this.context_items[0].slug;
                this.default_context_slug = this.context_items[0].slug;
            }

            delete_dir_recursive (GLib.Path.build_filename (this.contexts_root, slug));
            this.save ();
        }

        public void update_context (ContextConfig context, string name, string icon, string default_project)
        {
            context.name = name.strip () == "" ? context.slug : name.strip ();
            context.icon = icon.strip () == "" ? "folder-symbolic" : icon.strip ();
            context.default_project = normalize_project (default_project, "Inbox");
            this.save ();
        }

        public PomodoroProfile selected_profile ()
        {
            foreach (var profile in this.profile_items) {
                if (profile.slug == this.selected_profile_slug) {
                    return profile;
                }
            }

            return this.profile_items.length > 0 ? this.profile_items[0] : default_profile ("classic", "Classic", 25, 5);
        }

        public void set_selected_profile (string slug)
        {
            this.selected_profile_slug = slug;
            this.save ();
        }

        public void set_pomodoro_profile (string slug, string name, int work_minutes, int break_minutes)
        {
            var clean_slug = slugify (slug);
            foreach (var profile in this.profile_items) {
                if (profile.slug == clean_slug) {
                    profile.name = name.strip () == "" ? clean_slug : name.strip ();
                    profile.work_minutes = int.max (1, work_minutes);
                    profile.break_minutes = int.max (0, break_minutes);
                    profile.work_seconds = profile.work_minutes * 60;
                    profile.break_seconds = profile.break_minutes * 60;
                    profile.long_break_seconds = profile.break_seconds * DEFAULT_LONG_BREAK_MULTIPLIER;
                    this.save ();
                    return;
                }
            }

            var profile = default_profile (clean_slug, name.strip () == "" ? clean_slug : name.strip (), work_minutes, break_minutes);
            this.profile_items += profile;
            this.save ();
        }

        public void update_calendar_events_enabled (bool enabled)
        {
            if (this.calendar_events_enabled == enabled) {
                return;
            }

            this.calendar_events_enabled = enabled;
            this.save ();
            refresh_calendar_events ();
        }

        public Todo[] load_todos (ContextConfig? context = null)
        {
            var target = context ?? this.selected_context ();
            ensure_dir (context_dir (target));
            var path = todo_path (target);
            if (!GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) {
                try {
                    GLib.FileUtils.set_contents (path, "");
                }
                catch (GLib.Error error) {
                    warning ("Could not create todo file: %s", error.message);
                }
            }

            string contents = "";
            var modified_at = file_modified_at (path);
            var cached = this.todo_cache.lookup (target.slug);
            if (cached != null && cached.modified_at == modified_at && !cached_todos_need_time_sanitize (cached.todos)) {
                return cached.todos;
            }

            try {
                GLib.FileUtils.get_contents (path, out contents);
            }
            catch (GLib.Error error) {
                warning ("Could not read todo file: %s", error.message);
            }

            Todo[] todos = {};
            var normalized = new GLib.StringBuilder ();
            var should_rewrite = false;
            foreach (var line in contents.split ("\n")) {
                var todo = parse_todo (line, target.default_project);
                if (todo != null) {
                    todos += todo;
                }
                else if (line.strip () != "") {
                    should_rewrite = true;
                }
            }
            var previous_calendar_todos = copy_todos (todos);
            var sanitized = sanitize_todo_list (ref todos, target.default_project);
            Todo[] removed_calendar_todos = {};
            if (sanitized) {
                should_rewrite = true;
                removed_calendar_todos = this.calendar_events_enabled
                    ? CalendarSync.prepare_for_save (previous_calendar_todos, todos)
                    : CalendarSync.prepare_remove_all (todos);
            }
            foreach (var todo in todos) {
                normalized.append (todo.to_line ());
                normalized.append_c ('\n');
            }
            if (contents.strip () != normalized.str.strip ()) {
                should_rewrite = true;
            }
            if (should_rewrite) {
                try {
                    GLib.FileUtils.set_contents (path, normalized.str);
                    modified_at = file_modified_at (path);
                }
                catch (GLib.Error error) {
                    warning ("Could not normalize todo file: %s", error.message);
                }
            }
            if (sanitized) {
                CalendarSync.schedule_context_sync (
                    target.name,
                    this.calendar_events_enabled ? todos : new Todo[0],
                    removed_calendar_todos
                );
            }
            var cache = new TodoFileCache ();
            cache.todos = todos;
            cache.modified_at = modified_at;
            this.todo_cache.insert (target.slug, cache);
            return todos;
        }

        public void save_todos (Todo[] todos, ContextConfig? context = null)
        {
            var target = context ?? this.selected_context ();
            ensure_dir (context_dir (target));
            var previous = cached_todo_snapshot (target.slug);
            var clean_todos = todos;
            sanitize_todo_list (ref clean_todos, target.default_project);
            var removed_calendar_todos = this.calendar_events_enabled
                ? CalendarSync.prepare_for_save (previous, clean_todos)
                : CalendarSync.prepare_remove_all (clean_todos);
            var builder = new GLib.StringBuilder ();
            foreach (var todo in clean_todos) {
                builder.append (todo.to_line ());
                builder.append_c ('\n');
            }

            try {
                GLib.FileUtils.set_contents (todo_path (target), builder.str);
                var cache = new TodoFileCache ();
                cache.todos = clean_todos;
                cache.modified_at = file_modified_at (todo_path (target));
                this.todo_cache.insert (target.slug, cache);
                CalendarSync.schedule_context_sync (
                    target.name,
                    this.calendar_events_enabled ? clean_todos : new Todo[0],
                    removed_calendar_todos
                );
            }
            catch (GLib.Error error) {
                warning ("Could not save todo file: %s", error.message);
            }
        }

        private Todo[] cached_todo_snapshot (string context_slug)
        {
            Todo[] snapshot = {};
            var cached = this.todo_cache.lookup (context_slug);
            if (cached == null) {
                return snapshot;
            }

            foreach (var todo in cached.todos) {
                snapshot += todo.copy ();
            }
            return snapshot;
        }

        private Todo[] copy_todos (Todo[] todos)
        {
            Todo[] result = {};
            foreach (var todo in todos) {
                result += todo.copy ();
            }
            return result;
        }

        private bool cached_todos_need_time_sanitize (Todo[] todos)
        {
            foreach (var todo in todos) {
                if (todo.recurring) {
                    return true;
                }
                if (todo.recurring_instance && !todo.completed && daily_recurrence_missed_after_grace (todo.due)) {
                    return true;
                }
            }
            return false;
        }

        private bool sanitize_todo_list (ref Todo[] todos, string default_project)
        {
            var changed = false;
            var ids = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
            foreach (var todo in todos) {
                var before = todo.to_line ();
                var clean_priority = todo.priority.strip ().up ();
                todo.priority = is_priority (clean_priority) ? clean_priority : "C";
                todo.body = normalize_body_text (todo.body);
                todo.due = is_valid_date (todo.due) ? todo.due : "";
                todo.project = sanitize_todo_project (todo.project, default_project);
                todo.pm = int.max (0, todo.pm);
                todo.pm_done = int.max (0, todo.pm_done);
                todo.completed = todo.pm == 0;
                sanitize_recurrence (todo);

                todo.id = is_valid_todo_id (todo.id) ? todo.id.down () : "";
                while (todo.id == "" || ids.lookup (todo.id) != null) {
                    todo.id = new_todo_id ();
                }
                ids.insert (todo.id, todo.id);

                if (todo.to_line () != before) {
                    changed = true;
                }
            }
            if (remove_invalid_recurring_instances (ref todos, ids)) {
                changed = true;
            }
            foreach (var todo in todos) {
                var before = todo.to_line ();
                if (todo.dependency_id != "") {
                    if (!is_valid_todo_id (todo.dependency_id)
                        || todo.dependency_id == todo.id
                        || ids.lookup (todo.dependency_id) == null) {
                        todo.dependency_id = "";
                    }
                    else {
                        todo.dependency_id = todo.dependency_id.down ();
                    }
                }
                if (todo.dependency_id != "" && dependency_chain_is_circular (todo, todos)) {
                    todo.dependency_id = "";
                }
                if (todo.to_line () != before) {
                    changed = true;
                }
            }
            if (ensure_recurring_instances (ref todos)) {
                changed = true;
            }
            return changed;
        }

        private void sanitize_recurrence (Todo todo)
        {
            todo.recurrence = recurrence_kind (todo.recurrence);
            todo.recurrence_weekdays = sanitize_recurrence_weekdays (todo.recurrence_weekdays);
            todo.recurrence_parent_id = is_valid_todo_id (todo.recurrence_parent_id) ? todo.recurrence_parent_id.down () : "";
            todo.recurrence_latest_due = is_valid_date (todo.recurrence_latest_due) ? todo.recurrence_latest_due : "";

            if (todo.recurring_instance) {
                todo.recurrence = RECURRENCE_NONE;
                todo.recurrence_anchor_day = 0;
                todo.recurrence_weekdays = "";
                todo.recurrence_latest_due = "";
                todo.dependency_id = "";
                return;
            }

            if (todo.recurrence == RECURRENCE_NONE) {
                todo.recurrence_anchor_day = 0;
                todo.recurrence_weekdays = "";
                todo.recurrence_latest_due = "";
                return;
            }

            todo.due = "";
            todo.dependency_id = "";
            todo.pm = int.max (1, todo.pm);
            todo.pm_done = 0;
            todo.completed = false;
            todo.clear_previous_pm ();

            if (todo.recurrence == RECURRENCE_MONTHLY) {
                if (todo.recurrence_anchor_day < 1 || todo.recurrence_anchor_day > 31) {
                    todo.recurrence_anchor_day = today_local ().get_day_of_month ();
                }
                todo.recurrence_weekdays = "";
            }
            else if (todo.recurrence == RECURRENCE_WEEKLY) {
                todo.recurrence_anchor_day = 0;
                if (todo.recurrence_weekdays == "") {
                    todo.recurrence_weekdays = weekday_token_for_date (today_local ());
                }
                if (recurrence_weekday_count (todo.recurrence_weekdays) >= 7) {
                    todo.recurrence = RECURRENCE_DAILY;
                    todo.recurrence_weekdays = "";
                }
            }
            else {
                todo.recurrence_anchor_day = 0;
                todo.recurrence_weekdays = "";
            }
        }

        private bool remove_invalid_recurring_instances (ref Todo[] todos, GLib.HashTable<string, string> ids)
        {
            var changed = false;
            Todo[] next = {};
            foreach (var todo in todos) {
                if (!todo.recurring_instance) {
                    next += todo;
                    continue;
                }

                var parent = ids.lookup (todo.recurrence_parent_id) == null
                    ? null
                    : todo_for_id (todos, todo.recurrence_parent_id);
                if (parent == null || !parent.recurring || !is_valid_date (todo.due) || recurring_instance_expired (todo, parent)) {
                    changed = true;
                    continue;
                }
                next += todo;
            }

            if (changed) {
                todos = next;
            }
            return changed;
        }

        private bool recurring_instance_expired (Todo todo, Todo parent)
        {
            if (todo.completed) {
                return false;
            }
            if (parent.recurrence == RECURRENCE_DAILY) {
                return daily_recurrence_missed_after_grace (todo.due);
            }
            return date_delta_days (todo.due) < -1;
        }

        private bool ensure_recurring_instances (ref Todo[] todos)
        {
            var changed = false;
            var next = todos;
            foreach (var template in todos) {
                if (!template.recurring || template.id == "") {
                    continue;
                }
                foreach (var due in recurring_visible_instance_dates (template)) {
                    if (template.recurrence_latest_due != "" && GLib.strcmp (due, template.recurrence_latest_due) <= 0) {
                        continue;
                    }
                    if (recurring_instance_exists (todos, template.id, due)) {
                        template.recurrence_latest_due = latest_date (template.recurrence_latest_due, due);
                        continue;
                    }
                    next += generated_recurring_instance (template, due);
                    template.recurrence_latest_due = latest_date (template.recurrence_latest_due, due);
                    changed = true;
                }
            }
            if (changed) {
                todos = next;
            }
            return changed;
        }

        private bool recurring_instance_exists (Todo[] todos, string template_id, string due)
        {
            foreach (var todo in todos) {
                if (todo.recurring_instance && todo.recurrence_parent_id == template_id && todo.due == due) {
                    return true;
                }
            }
            return false;
        }

        private Todo generated_recurring_instance (Todo template, string due)
        {
            var instance = new Todo ();
            instance.id = new_todo_id ();
            instance.body = recurring_instance_body (template, due);
            instance.priority = template.priority;
            instance.due = due;
            instance.project = template.project;
            instance.pm = int.max (1, template.pm);
            instance.pm_done = 0;
            instance.completed = false;
            instance.recurrence_parent_id = template.id;
            return instance;
        }

        private string latest_date (string current, string candidate)
        {
            if (!is_valid_date (candidate)) {
                return current;
            }
            if (!is_valid_date (current) || GLib.strcmp (candidate, current) > 0) {
                return candidate;
            }
            return current;
        }

        private string[] recurring_visible_instance_dates (Todo template)
        {
            string[] dates = {};
            var today = today_local ();
            switch (template.recurrence)
            {
                case RECURRENCE_DAILY:
                    dates += today.add_days (-1).format ("%F");
                    dates += today.format ("%F");
                    break;

                case RECURRENCE_WEEKLY:
                    for (var offset = -1; offset <= 1; offset++) {
                        var date = today.add_days (offset);
                        if (recurrence_weekday_enabled (template.recurrence_weekdays, date.get_day_of_week () - 1)) {
                            dates += date.format ("%F");
                        }
                    }
                    break;

                case RECURRENCE_MONTHLY:
                    for (var offset = -1; offset <= 1; offset++) {
                        var date = today.add_days (offset);
                        var anchor = int.max (1, int.min (31, template.recurrence_anchor_day));
                        var clamped = int.min (anchor, days_in_month (date.get_year (), date.get_month ()));
                        if (date.get_day_of_month () == clamped) {
                            dates += date.format ("%F");
                        }
                    }
                    break;
            }
            return dates;
        }

        private int recurrence_weekday_count (string weekdays)
        {
            var clean = sanitize_recurrence_weekdays (weekdays);
            if (clean == "") {
                return 0;
            }
            return clean.split (",").length;
        }

        private bool dependency_chain_is_circular (Todo todo, Todo[] todos)
        {
            var current_id = todo.dependency_id;
            var seen = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);

            while (current_id != "") {
                if (current_id == todo.id || seen.lookup (current_id) != null) {
                    return true;
                }
                seen.insert (current_id, current_id);

                var current = todo_for_id (todos, current_id);
                if (current == null) {
                    return false;
                }
                current_id = current.dependency_id;
            }
            return false;
        }

        private Todo? todo_for_id (Todo[] todos, string id)
        {
            foreach (var todo in todos) {
                if (todo.id == id) {
                    return todo;
                }
            }
            return null;
        }

        public void record_pomodoro (string context_slug, string project, string profile_slug)
        {
            var entry = new PomodoroHistoryEntry ();
            entry.completed_at = new GLib.DateTime.now_local ().format ("%Y-%m-%dT%H:%M:%S");
            entry.context = context_slug;
            entry.project = project;
            entry.profile = profile_slug;
            this.history_items += entry;
            this.save ();
        }

        public void delete_project_icons (ContextConfig context, string project)
        {
            var clean_project = normalize_project (project, "Inbox");
            string[] keys = {};
            foreach (var key in context.project_icons.get_keys ()) {
                if (key == clean_project || key.has_prefix ("%s.".printf (clean_project))) {
                    keys += key;
                }
            }

            foreach (var key in keys) {
                context.project_icons.remove (key);
            }
            this.save ();
        }

        public void delete_project_history (string context_slug, string project)
        {
            var clean_project = normalize_project (project, "Inbox");
            PomodoroHistoryEntry[] history = {};
            foreach (var item in this.history_items) {
                var item_project = normalize_project (item.project, item.project);
                if (item.context != context_slug
                    || (item_project != clean_project && !item_project.has_prefix ("%s.".printf (clean_project)))) {
                    history += item;
                }
            }
            this.history_items = history;
            this.save ();
        }

        public string[] due_notifications ()
        {
            string[] messages = {};
            var today = today_local ();
            var tomorrow = today.add_days (1);
            var today_text = today.format ("%F");
            var tomorrow_text = tomorrow.format ("%F");

            foreach (var context in this.context_items) {
                var due_today = 0;
                var due_tomorrow = 0;
                foreach (var todo in this.load_todos (context)) {
                    if (todo.completed) {
                        continue;
                    }
                    if (this.notify_due_today && todo.due == today_text) {
                        due_today++;
                    }
                    if (this.notify_due_tomorrow && todo.due == tomorrow_text) {
                        due_tomorrow++;
                    }
                }
                if (due_today > 0) {
                    messages += "%s: %d todo(s) due today".printf (context.name, due_today);
                }
                if (due_tomorrow > 0) {
                    messages += "%s: %d todo(s) due tomorrow".printf (context.name, due_tomorrow);
                }
            }
            return messages;
        }

        public void refresh_calendar_events ()
        {
            foreach (var context in this.context_items) {
                save_todos (load_todos (context), context);
            }
        }

        public void save ()
        {
            ensure_dir (this.data_dir);
            var builder = new Json.Builder ();
            builder.begin_object ();

            builder.set_member_name ("selected_context");
            builder.add_string_value (this.selected_context_slug);
            builder.set_member_name ("selected_project");
            builder.add_string_value (this.selected_project_root);
            builder.set_member_name ("selected_view");
            builder.add_string_value (this.selected_view);
            builder.set_member_name ("selected_todo_id");
            builder.add_string_value (this.selected_todo_id);
            builder.set_member_name ("selected_order");
            builder.add_string_value (this.selected_order_mode);
            builder.set_member_name ("last_todo_priority");
            builder.add_string_value (this.last_todo_priority);
            builder.set_member_name ("last_todo_project");
            builder.add_string_value (this.last_todo_project_root);
            builder.set_member_name ("last_todo_subproject");
            builder.add_string_value (this.last_todo_subproject);
            builder.set_member_name ("last_todo_due");
            builder.add_string_value (this.last_todo_due);
            builder.set_member_name ("default_context");
            builder.add_string_value (this.default_context_slug);

            builder.set_member_name ("window");
            builder.begin_object ();
            builder.set_member_name ("width");
            builder.add_int_value (this.window_width);
            builder.set_member_name ("height");
            builder.add_int_value (this.window_height);
            builder.end_object ();

            builder.set_member_name ("contexts");
            builder.begin_object ();
            foreach (var context in this.context_items) {
                builder.set_member_name (context.slug);
                builder.begin_object ();
                builder.set_member_name ("name");
                builder.add_string_value (context.name);
                builder.set_member_name ("icon");
                builder.add_string_value (context.icon);
                builder.set_member_name ("default_project");
                builder.add_string_value (context.default_project);
                builder.set_member_name ("project_icons");
                builder.begin_object ();
                foreach (var key in context.project_icons.get_keys ()) {
                    builder.set_member_name (key);
                    builder.add_string_value (context.project_icons.lookup (key));
                }
                builder.end_object ();
                builder.end_object ();
            }
            builder.end_object ();

            builder.set_member_name ("selected_pomodoro_profile");
            builder.add_string_value (this.selected_profile_slug);
            builder.set_member_name ("pomodoro_display");
            builder.add_string_value (this.repeat_pomodoro_icons ? "icons" : "count");
            builder.set_member_name ("compact_timer_actions");
            builder.add_boolean_value (this.compact_timer_actions);
            builder.set_member_name ("show_delete_button");
            builder.add_boolean_value (this.show_delete_button);
            builder.set_member_name ("dependencies_enabled");
            builder.add_boolean_value (this.dependencies_enabled);
            builder.set_member_name ("auto_depend_on_previous_todo");
            builder.add_boolean_value (this.auto_depend_on_previous_todo);
            builder.set_member_name ("project_dependency_graph");
            builder.add_boolean_value (this.project_dependency_graph);
            builder.set_member_name ("calendar_events_enabled");
            builder.add_boolean_value (this.calendar_events_enabled);
            builder.set_member_name ("pomodoro_profiles");
            builder.begin_object ();
            foreach (var profile in this.profile_items) {
                builder.set_member_name (profile.slug);
                builder.begin_object ();
                builder.set_member_name ("name");
                builder.add_string_value (profile.name);
                builder.set_member_name ("work_minutes");
                builder.add_int_value (profile.work_minutes);
                builder.set_member_name ("break_minutes");
                builder.add_int_value (profile.break_minutes);
                builder.set_member_name ("work_seconds");
                builder.add_int_value (profile.work_duration_seconds ());
                builder.set_member_name ("break_seconds");
                builder.add_int_value (profile.short_break_duration_seconds ());
                builder.set_member_name ("long_break_seconds");
                builder.add_int_value (profile.long_break_duration_seconds ());
                builder.end_object ();
            }
            builder.end_object ();

            builder.set_member_name ("notifications");
            builder.begin_object ();
            builder.set_member_name ("due_today");
            builder.add_boolean_value (this.notify_due_today);
            builder.set_member_name ("due_tomorrow");
            builder.add_boolean_value (this.notify_due_tomorrow);
            builder.set_member_name ("due_cutoff_hour");
            builder.add_int_value (this.due_cutoff_hour);
            builder.end_object ();

            builder.set_member_name ("pomodoro_history");
            builder.begin_array ();
            foreach (var item in this.history_items) {
                builder.begin_object ();
                builder.set_member_name ("completed_at");
                builder.add_string_value (item.completed_at);
                builder.set_member_name ("context");
                builder.add_string_value (item.context);
                builder.set_member_name ("project");
                builder.add_string_value (item.project);
                builder.set_member_name ("profile");
                builder.add_string_value (item.profile);
                builder.end_object ();
            }
            builder.end_array ();

            builder.end_object ();

            var generator = new Json.Generator ();
            generator.set_pretty (true);
            generator.set_root (builder.get_root ());
            try {
                generator.to_file (this.config_path);
            }
            catch (GLib.Error error) {
                warning ("Could not save app-state.json: %s", error.message);
            }
        }

        private void load ()
        {
            ensure_dir (this.data_dir);
            if (!GLib.FileUtils.test (this.config_path, GLib.FileTest.EXISTS)) {
                this.load_defaults ();
                this.save ();
                return;
            }

            try {
                var parser = new Json.Parser ();
                parser.load_from_file (this.config_path);
                var root = parser.get_root ().get_object ();
                this.read_config (root);
            }
            catch (GLib.Error error) {
                warning ("Could not load app-state.json, using defaults: %s", error.message);
                this.load_defaults ();
                this.save ();
            }
        }

        private void read_config (Json.Object root)
        {
            this.selected_context_slug = string_member (root, "selected_context", "work");
            this.selected_project_root = normalize_selected_project_root (string_member (root, "selected_project", ""));
            this.selected_view = normalize_selected_view (string_member (root, "selected_view", "todos"));
            this.selected_todo_id = normalize_selected_todo_id (string_member (root, "selected_todo_id", ""));
            this.selected_order_mode = normalize_order_mode (string_member (root, "selected_order", "due"));
            this.last_todo_priority = normalize_priority_value (string_member (root, "last_todo_priority", "C"));
            this.last_todo_project_root = project_root (normalize_project (string_member (root, "last_todo_project", "Inbox"), "Inbox"));
            this.last_todo_subproject = normalize_last_todo_subproject (string_member (root, "last_todo_subproject", "Default"));
            this.last_todo_due = normalize_last_todo_due (string_member (root, "last_todo_due", ""));
            this.default_context_slug = string_member (root, "default_context", "work");
            this.selected_profile_slug = string_member (root, "selected_pomodoro_profile", "classic");
            this.repeat_pomodoro_icons = string_member (root, "pomodoro_display", "icons") != "count";
            this.compact_timer_actions = bool_member (root, "compact_timer_actions", true);
            this.show_delete_button = bool_member (root, "show_delete_button", true);
            this.dependencies_enabled = bool_member (root, "dependencies_enabled", true);
            this.auto_depend_on_previous_todo = bool_member (root, "auto_depend_on_previous_todo", false);
            this.project_dependency_graph = bool_member (root, "project_dependency_graph", false);
            this.calendar_events_enabled = bool_member (root, "calendar_events_enabled", true);
            this.window_width = 900;
            this.window_height = 640;
            if (root.has_member ("window")) {
                var window = root.get_object_member ("window");
                this.window_width = int.max (360, int_member (window, "width", 900));
                this.window_height = int.max (360, int_member (window, "height", 640));
            }
            this.context_items = {};
            this.profile_items = {};
            this.history_items = {};

            if (root.has_member ("contexts")) {
                var contexts = root.get_object_member ("contexts");
                foreach (var slug in contexts.get_members ()) {
                    var item = contexts.get_object_member (slug);
                    var context = new ContextConfig ();
                    context.slug = slug;
                    context.name = string_member (item, "name", slug);
                    context.icon = string_member (item, "icon", "folder-symbolic");
                    context.default_project = normalize_project (string_member (item, "default_project", "Inbox"), "Inbox");
                    if (item.has_member ("project_icons")) {
                        var icons = item.get_object_member ("project_icons");
                        foreach (var project in icons.get_members ()) {
                            context.set_project_icon (project, icons.get_string_member (project));
                        }
                    }
                    this.context_items += context;
                    ensure_dir (context_dir (context));
                }
            }

            if (root.has_member ("pomodoro_profiles")) {
                var profiles = root.get_object_member ("pomodoro_profiles");
                foreach (var slug in profiles.get_members ()) {
                    var item = profiles.get_object_member (slug);
                    var work_minutes = int_member (item, "work_minutes", 25);
                    var break_minutes = int_member (item, "break_minutes", 5);
                    this.profile_items += default_profile_seconds (
                        slug,
                        string_member (item, "name", slug),
                        int_member (item, "work_seconds", int.max (1, work_minutes) * 60),
                        int_member (item, "break_seconds", int.max (0, break_minutes) * 60),
                        int_member (
                            item,
                            "long_break_seconds",
                            int.max (0, break_minutes * DEFAULT_LONG_BREAK_MULTIPLIER) * 60
                        )
                    );
                }
            }

            if (root.has_member ("notifications")) {
                var notifications = root.get_object_member ("notifications");
                this.notify_due_today = bool_member (notifications, "due_today", true);
                this.notify_due_tomorrow = bool_member (notifications, "due_tomorrow", true);
                this.due_cutoff_hour = int_member (notifications, "due_cutoff_hour", 18);
            }

            if (root.has_member ("pomodoro_history")) {
                var history = root.get_array_member ("pomodoro_history");
                for (uint index = 0; index < history.get_length (); index++) {
                    var item = history.get_object_element (index);
                    var entry = new PomodoroHistoryEntry ();
                    entry.completed_at = string_member (item, "completed_at", "");
                    entry.context = string_member (item, "context", "");
                    entry.project = string_member (item, "project", "");
                    entry.profile = string_member (item, "profile", "");
                    this.history_items += entry;
                }
            }

            if (this.context_items.length == 0 || this.profile_items.length == 0) {
                this.load_defaults ();
            }

            ensure_builtin_profiles ();
        }

        private void load_defaults ()
        {
            this.selected_context_slug = "work";
            this.default_context_slug = "work";
            this.selected_project_root = "";
            this.selected_view = "todos";
            this.selected_todo_id = "";
            this.selected_order_mode = "due";
            this.last_todo_priority = "C";
            this.last_todo_project_root = "Inbox";
            this.last_todo_subproject = "Default";
            this.last_todo_due = "";
            this.selected_profile_slug = "classic";
            this.window_width = 900;
            this.window_height = 640;
            this.notify_due_today = true;
            this.notify_due_tomorrow = true;
            this.due_cutoff_hour = 18;
            this.repeat_pomodoro_icons = true;
            this.compact_timer_actions = true;
            this.show_delete_button = true;
            this.dependencies_enabled = true;
            this.auto_depend_on_previous_todo = false;
            this.project_dependency_graph = false;
            this.calendar_events_enabled = true;
            this.history_items = {};

            var work = new ContextConfig ();
            work.slug = "work";
            work.name = "Work";
            work.icon = "briefcase-symbolic";
            work.default_project = "Inbox";
            work.set_project_icon ("Inbox", "mail-inbox-symbolic");
            this.context_items = {work};

            this.profile_items = {
                default_profile ("classic", "Classic", 25, 5),
                default_profile ("deep-work", "Deep Work", 50, 10),
                default_profile ("short", "Short", 15, 3),
                default_profile_seconds ("testing", "Testing", 10, 5, 5),
            };
        }

        private void ensure_builtin_profiles ()
        {
            ensure_builtin_profile (default_profile ("classic", "Classic", 25, 5));
            ensure_builtin_profile (default_profile ("deep-work", "Deep Work", 50, 10));
            ensure_builtin_profile (default_profile ("short", "Short", 15, 3));
            ensure_builtin_profile (default_profile_seconds ("testing", "Testing", 10, 5, 5));
        }

        private void ensure_builtin_profile (PomodoroProfile builtin)
        {
            foreach (var profile in this.profile_items) {
                if (profile.slug == builtin.slug) {
                    return;
                }
            }

            this.profile_items += builtin;
        }

        private string context_dir (ContextConfig context)
        {
            return GLib.Path.build_filename (this.contexts_root, context.slug);
        }

        private string todo_path (ContextConfig context)
        {
            return GLib.Path.build_filename (context_dir (context), "todo.txt");
        }

        private int64 file_modified_at (string path)
        {
            try {
                var file = GLib.File.new_for_path (path);
                var info = file.query_info ("time::modified", GLib.FileQueryInfoFlags.NONE);
                var modified = info.get_modification_date_time ();
                return modified == null ? 0 : modified.to_unix ();
            }
            catch (GLib.Error error) {
                return 0;
            }
        }
    }

    public errordomain StoreError
    {
        NOT_FOUND
    }

    private PomodoroProfile default_profile (string slug, string name, int work_minutes, int break_minutes)
    {
        return default_profile_seconds (
            slug,
            name,
            int.max (1, work_minutes) * 60,
            int.max (0, break_minutes) * 60,
            int.max (0, break_minutes * DEFAULT_LONG_BREAK_MULTIPLIER) * 60
        );
    }

    private PomodoroProfile default_profile_seconds (
        string slug,
        string name,
        int work_seconds,
        int break_seconds,
        int long_break_seconds
    )
    {
        var profile = new PomodoroProfile ();
        profile.slug = slug;
        profile.name = name;
        profile.work_seconds = int.max (1, work_seconds);
        profile.break_seconds = int.max (0, break_seconds);
        profile.long_break_seconds = int.max (0, long_break_seconds);
        profile.work_minutes = int.max (1, (profile.work_seconds + 59) / 60);
        profile.break_minutes = int.max (0, profile.break_seconds / 60);
        return profile;
    }

    private string normalize_selected_project_root (string? project)
    {
        if (project == null || project.strip () == "") {
            return "";
        }

        return project_root (normalize_project (project, ""));
    }

    private string normalize_selected_view (string? view)
    {
        var clean = view == null ? "" : view.strip ();
        if (clean == "pomodoro" || clean == "todos") {
            return clean;
        }
        return "todos";
    }

    private string normalize_selected_todo_id (string? id)
    {
        if (id == null || !is_valid_todo_id (id)) {
            return "";
        }
        return id.down ();
    }

    private string normalize_order_mode (string? mode)
    {
        var clean = mode == null ? "" : mode.strip ().down ();
        if (clean == "priority" || clean == "due" || clean == "project" || clean == "recurring") {
            return clean;
        }
        if (clean == "dependency") {
            return "project";
        }
        return "due";
    }

    private string order_mode_slug (uint mode)
    {
        switch (mode)
        {
            case 0:
                return "priority";
            case 1:
                return "due";
            case 2:
                return "project";
            case 3:
                return "recurring";
            default:
                return "due";
        }
    }

    private uint order_mode_index (string? mode)
    {
        switch (normalize_order_mode (mode))
        {
            case "due":
                return 1;
            case "project":
                return 2;
            case "recurring":
                return 3;
            default:
                return 0;
        }
    }

    private string normalize_priority_value (string? priority)
    {
        var clean = priority == null ? "" : priority.strip ().up ();
        return is_priority (clean) ? clean : "C";
    }

    private string normalize_last_todo_subproject (string? subproject)
    {
        var clean = subproject == null ? "" : project_root (normalize_project (subproject, "Default"));
        return valid_project_part_text (clean) ? clean : "Default";
    }

    private string normalize_last_todo_due (string? due)
    {
        if (due == null || due.strip () == "") {
            return "";
        }
        var clean = due.strip ();
        if (!is_valid_date (clean)) {
            return "";
        }
        return date_delta_days (clean) < 0 ? today_local ().format ("%F") : clean;
    }

    private string default_data_dir ()
    {
        var tomodoro_data_root = GLib.Environment.get_variable ("TOMODORO_DATA_ROOT");
        if (tomodoro_data_root != null && tomodoro_data_root.strip () != "") {
            return tomodoro_data_root.strip ();
        }

        var env_data_root = GLib.Environment.get_variable ("TODO_POMODORO_DATA_ROOT");
        if (env_data_root != null && env_data_root.strip () != "") {
            return env_data_root.strip ();
        }

        return GLib.Path.build_filename (GLib.Environment.get_user_data_dir (), "tomodoro");
    }

    private string default_contexts_root ()
    {
        var tomodoro_contexts_root = GLib.Environment.get_variable ("TOMODORO_CONTEXTS_ROOT");
        if (tomodoro_contexts_root != null && tomodoro_contexts_root.strip () != "") {
            return tomodoro_contexts_root.strip ();
        }

        var old_contexts_root = GLib.Environment.get_variable ("TODO_POMODORO_CONTEXTS_ROOT");
        if (old_contexts_root != null && old_contexts_root.strip () != "") {
            return old_contexts_root.strip ();
        }

        return GLib.Path.build_filename (GLib.Environment.get_home_dir (), "contexts");
    }

    private string unique_context_slug (string base_slug, ContextConfig[] contexts)
    {
        var candidate = base_slug;
        var counter = 2;
        while (context_slug_exists (candidate, contexts)) {
            candidate = "%s-%d".printf (base_slug, counter);
            counter++;
        }
        return candidate;
    }

    private bool context_slug_exists (string slug, ContextConfig[] contexts)
    {
        foreach (var context in contexts) {
            if (context.slug == slug) {
                return true;
            }
        }
        return false;
    }

    private void ensure_dir (string path)
    {
        if (GLib.DirUtils.create_with_parents (path, 0755) != 0) {
            warning ("Could not create directory %s", path);
        }
    }

    private void delete_dir_recursive (string path)
    {
        var directory = GLib.File.new_for_path (path);
        try {
            if (!directory.query_exists ()) {
                return;
            }
            var enumerator = directory.enumerate_children (
                "standard::name,standard::type",
                GLib.FileQueryInfoFlags.NONE
            );
            GLib.FileInfo? info;
            while ((info = enumerator.next_file ()) != null) {
                var child = directory.get_child (info.get_name ());
                if (info.get_file_type () == GLib.FileType.DIRECTORY) {
                    delete_dir_recursive (child.get_path ());
                }
                else {
                    child.delete ();
                }
            }
            directory.delete ();
        }
        catch (GLib.Error error) {
            warning ("Could not delete %s: %s", path, error.message);
        }
    }

    private string string_member (Json.Object object, string name, string fallback)
    {
        if (!object.has_member (name) || object.get_member (name).get_value_type () != typeof (string)) {
            return fallback;
        }
        return object.get_string_member (name);
    }

    private int int_member (Json.Object object, string name, int fallback)
    {
        if (!object.has_member (name)) {
            return fallback;
        }
        return (int) object.get_int_member (name);
    }

    private bool bool_member (Json.Object object, string name, bool fallback)
    {
        if (!object.has_member (name)) {
            return fallback;
        }
        return object.get_boolean_member (name);
    }
}
