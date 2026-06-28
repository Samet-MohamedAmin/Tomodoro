namespace Tomodoro
{
    public class RecurringDialog : Adw.Window
    {
        private ContextConfig context;
        private Todo? original;
        private TodoSaveFunc on_save;
        private TodoDeleteFunc? on_delete;
        private string[] projects;
        private string[] main_projects;
        private bool main_project_locked = false;
        private bool show_locked_project_fields = false;
        private bool updating_text_case = false;
        private bool updating_schedule = false;

        private Gtk.Entry body;
        private Gtk.DropDown priority;
        private Gtk.DropDown main_project;
        private Gtk.Entry subproject;
        private Gtk.DropDown schedule;
        private Gtk.Widget weekly_row;
        private Gtk.Widget monthly_row;
        private Gtk.Box weekly_box;
        private Gtk.ToggleButton[] weekday_buttons = {};
        private Gtk.SpinButton monthly_day;
        private Gtk.SpinButton pm;
        private Gtk.Label error_label;

        public RecurringDialog (
            Gtk.Window parent,
            ContextConfig context,
            string[] projects,
            Todo? todo,
            owned TodoSaveFunc on_save,
            owned TodoDeleteFunc? on_delete = null,
            string default_project = "Inbox",
            string default_subproject = "Default",
            string default_priority = "C",
            bool lock_main_project = false,
            bool show_locked_project_fields = false
        ) {
            Object (
                transient_for: parent,
                modal: true,
                title: todo == null || on_delete == null ? "New Recurring" : "Edit Recurring",
                default_width: 460,
                default_height: 420
            );

            this.context = context;
            this.original = todo;
            this.on_save = (owned) on_save;
            this.on_delete = (owned) on_delete;
            this.projects = projects;
            this.main_project_locked = lock_main_project;
            this.show_locked_project_fields = show_locked_project_fields;
            this.main_projects = main_project_roots (projects, context.default_project, default_project);

            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            root.margin_top = 16;
            root.margin_bottom = 16;
            root.margin_start = 16;
            root.margin_end = 16;
            this.content = root;

            this.body = new Gtk.Entry ();
            this.body.placeholder_text = "Template body";
            this.body.text = todo != null ? todo.body : "";
            this.body.changed.connect (() => uppercase_entry_first_letter (this.body));
            this.body.activate.connect (save_clicked);
            root.append (row ("Body", this.body));

            this.priority = new Gtk.DropDown.from_strings (PRIORITY_OPTIONS);
            this.priority.factory = priority_factory ();
            var current_priority = todo != null ? todo.priority : default_priority.strip ().up ();
            this.priority.selected = selected_index (PRIORITY_OPTIONS, is_priority (current_priority) ? current_priority : "C", 2);

            var current_project = todo != null ? todo.project : join_project (project_root (default_project), default_subproject);
            var current_main = project_root (current_project);
            this.main_project = new Gtk.DropDown.from_strings (this.main_projects);
            this.main_project.selected = selected_index (this.main_projects, current_main, 0);
            this.main_project.sensitive = !(this.main_project_locked && this.show_locked_project_fields);
            this.subproject = new Gtk.Entry ();
            this.subproject.placeholder_text = "Default";
            this.subproject.text = project_child (current_project) == "" ? "Default" : project_child (current_project);
            this.subproject.changed.connect (() => sanitize_structure_entry (this.subproject, PROJECT_PART_MAX_LENGTH));
            if (this.main_project_locked && this.show_locked_project_fields) {
                this.subproject.sensitive = false;
                this.subproject.tooltip_text = "Subproject cannot be changed from All Projects";
            }

            if (this.main_project_locked && !this.show_locked_project_fields) {
                var priority_project_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                priority_project_box.append (inline_field ("Priority", this.priority));
                priority_project_box.append (inline_field ("Subproject", this.subproject));
                root.append (priority_project_box);
            }
            else {
                root.append (row ("Priority", this.priority));
                var project_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                project_box.append (inline_field ("Main", this.main_project));
                project_box.append (inline_field ("Subproject", this.subproject));
                root.append (row ("Project", project_box));
            }

            string[] schedules = {"Daily", "Weekly", "Monthly"};
            this.schedule = new Gtk.DropDown.from_strings (schedules);
            this.schedule.selected = schedule_index (todo != null ? todo.recurrence : RECURRENCE_DAILY);
            this.schedule.notify["selected"].connect (sync_schedule_controls);
            root.append (row ("Repeats", this.schedule));

            this.weekly_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            for (var index = 0; index < RECURRENCE_WEEKDAY_LABELS.length; index++) {
                var button = new Gtk.ToggleButton.with_label (RECURRENCE_WEEKDAY_LABELS[index]);
                button.toggled.connect (weekly_day_toggled);
                this.weekday_buttons += button;
                this.weekly_box.append (button);
            }
            this.weekly_row = row ("Week days", this.weekly_box);
            root.append (this.weekly_row);

            this.monthly_day = new Gtk.SpinButton.with_range (1, 31, 1);
            this.monthly_day.value = todo != null && todo.recurrence_anchor_day >= 1
                ? todo.recurrence_anchor_day
                : today_local ().get_day_of_month ();
            this.monthly_row = row ("Month day", this.monthly_day);
            root.append (this.monthly_row);

            this.pm = new Gtk.SpinButton.with_range (1, 99, 1);
            this.pm.value = todo != null ? int.max (1, todo.pm) : 1;
            root.append (row ("Pomodoros left", this.pm));

            this.error_label = new Gtk.Label ("");
            this.error_label.xalign = 0;
            this.error_label.visible = false;
            this.error_label.add_css_class ("error");
            root.append (this.error_label);

            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            buttons.halign = Gtk.Align.END;
            if (todo != null && on_delete != null) {
                var delete_button = new Gtk.Button.with_label ("Delete");
                delete_button.add_css_class ("destructive-action");
                delete_button.clicked.connect (() => {
                    if (this.on_delete != null) {
                        this.on_delete ();
                    }
                    this.close ();
                });
                buttons.append (delete_button);
            }
            var cancel = new Gtk.Button.with_label ("Cancel");
            cancel.clicked.connect (() => this.close ());
            buttons.append (cancel);
            var save = new Gtk.Button.with_label ("Save");
            save.add_css_class ("suggested-action");
            save.clicked.connect (save_clicked);
            buttons.append (save);
            root.append (buttons);

            load_weekdays (todo);
            sync_schedule_controls ();
        }

        private void save_clicked ()
        {
            var body_text = normalize_body_text (this.body.text);
            if (!has_minimum_letters (body_text)) {
                show_error ("Template body needs at least three letters.");
                this.body.add_css_class ("error");
                return;
            }

            var main_project_text = selected_main_project ();
            var subproject_text = project_root (normalize_project (this.subproject.text, ""));
            if (!valid_project_part_text (main_project_text)) {
                show_error ("Project needs at least three letters.");
                return;
            }
            if (!valid_project_part_text (subproject_text)) {
                show_error ("Subproject needs at least three letters.");
                this.subproject.add_css_class ("error");
                return;
            }

            var item = new Todo ();
            item.id = this.original != null ? this.original.id : "";
            item.body = body_text;
            item.priority = selected_priority_value ();
            item.project = join_project (main_project_text, subproject_text);
            item.pm = int.max (1, this.pm.get_value_as_int ());
            item.completed = false;
            item.pm_done = 0;
            item.due = "";
            item.dependency_id = "";
            item.recurrence_parent_id = "";
            item.recurrence = selected_recurrence_value ();
            item.recurrence_anchor_day = item.recurrence == RECURRENCE_MONTHLY ? this.monthly_day.get_value_as_int () : 0;
            item.recurrence_weekdays = item.recurrence == RECURRENCE_WEEKLY ? selected_weekdays () : "";
            if (item.recurrence == RECURRENCE_WEEKLY && recurrence_weekday_count (item.recurrence_weekdays) >= 7) {
                item.recurrence = RECURRENCE_DAILY;
                item.recurrence_weekdays = "";
            }
            if (item.recurrence == RECURRENCE_WEEKLY && item.recurrence_weekdays == "") {
                show_error ("Select at least one weekday.");
                return;
            }
            item.recurrence_latest_due = this.original != null ? this.original.recurrence_latest_due : "";
            if (this.original != null) {
                foreach (var tag in this.original.get_extra_tags ()) {
                    item.add_extra_tag (tag);
                }
            }
            item.clear_calendar_uid ();
            item.clear_previous_pm ();

            var error = this.on_save (item, false);
            if (error != null) {
                show_error (error);
                return;
            }
            this.close ();
        }

        private string selected_main_project ()
        {
            if (this.main_project.selected < this.main_projects.length) {
                return this.main_projects[this.main_project.selected];
            }
            return project_root (this.context.default_project);
        }

        private string selected_priority_value ()
        {
            if (this.priority.selected < PRIORITY_OPTIONS.length) {
                return PRIORITY_OPTIONS[this.priority.selected];
            }
            return "C";
        }

        private string selected_recurrence_value ()
        {
            switch (this.schedule.selected)
            {
                case 1:
                    return RECURRENCE_WEEKLY;
                case 2:
                    return RECURRENCE_MONTHLY;
                default:
                    return RECURRENCE_DAILY;
            }
        }

        private uint schedule_index (string recurrence)
        {
            switch (recurrence_kind (recurrence))
            {
                case RECURRENCE_WEEKLY:
                    return 1;
                case RECURRENCE_MONTHLY:
                    return 2;
                default:
                    return 0;
            }
        }

        private void load_weekdays (Todo? todo)
        {
            var weekdays = todo != null && todo.recurrence_weekdays != ""
                ? todo.recurrence_weekdays
                : weekday_token_for_date (today_local ());
            for (var index = 0; index < this.weekday_buttons.length; index++) {
                this.weekday_buttons[index].active = recurrence_weekday_enabled (weekdays, index);
            }
        }

        private string selected_weekdays ()
        {
            string[] weekdays = {};
            for (var index = 0; index < this.weekday_buttons.length; index++) {
                if (this.weekday_buttons[index].active) {
                    weekdays += RECURRENCE_WEEKDAY_TOKENS[index];
                }
            }
            return string.joinv (",", weekdays);
        }

        private void weekly_day_toggled ()
        {
            if (this.updating_schedule || this.schedule.selected != 1) {
                return;
            }
            if (recurrence_weekday_count (selected_weekdays ()) >= 7) {
                this.updating_schedule = true;
                this.schedule.selected = 0;
                this.updating_schedule = false;
            }
            sync_schedule_controls ();
        }

        private void sync_schedule_controls ()
        {
            var recurrence = selected_recurrence_value ();
            this.weekly_row.visible = recurrence == RECURRENCE_WEEKLY;
            this.monthly_row.visible = recurrence == RECURRENCE_MONTHLY;
        }

        private int recurrence_weekday_count (string weekdays)
        {
            var clean = sanitize_recurrence_weekdays (weekdays);
            return clean == "" ? 0 : clean.split (",").length;
        }

        private void show_error (string message)
        {
            this.error_label.label = message;
            this.error_label.visible = true;
        }

        private Gtk.Widget row (string label, Gtk.Widget child)
        {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var title = new Gtk.Label (label);
            title.xalign = 0;
            title.add_css_class ("caption");
            box.append (title);
            box.append (child);
            return box;
        }

        private Gtk.Widget inline_field (string label, Gtk.Widget child)
        {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            box.hexpand = true;
            var title = new Gtk.Label (label);
            title.xalign = 0;
            title.add_css_class ("caption");
            box.append (title);
            box.append (child);
            return box;
        }

        private Gtk.ListItemFactory priority_factory ()
        {
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((_factory, item) => {
                var list_item = item as Gtk.ListItem;
                if (list_item == null) {
                    return;
                }
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                var dot = new Gtk.Label ("");
                var label = new Gtk.Label ("");
                label.xalign = 0;
                row.append (dot);
                row.append (label);
                list_item.child = row;
            });
            factory.bind.connect ((_factory, item) => {
                var list_item = item as Gtk.ListItem;
                if (list_item == null) {
                    return;
                }
                var string_object = list_item.item as Gtk.StringObject;
                var row = list_item.child as Gtk.Box;
                if (string_object == null || row == null) {
                    return;
                }

                var dot = row.get_first_child () as Gtk.Label;
                var label = dot != null ? dot.get_next_sibling () as Gtk.Label : null;
                if (dot == null || label == null) {
                    return;
                }

                var value = string_object.string;
                dot.set_markup ("<span foreground='%s' size='large'>●</span>".printf (priority_color (value)));
                label.label = value;
            });
            return factory;
        }

        private uint selected_index (string[] values, string selected, uint fallback)
        {
            for (uint index = 0; index < values.length; index++) {
                if (values[index] == selected) {
                    return index;
                }
            }
            return fallback;
        }

        private static string[] main_project_roots (string[] projects, string context_default, string dialog_default)
        {
            string[] roots = {};
            roots = append_unique (roots, project_root (context_default));
            roots = append_unique (roots, project_root (dialog_default));
            foreach (var project in projects) {
                roots = append_unique (roots, project_root (project));
            }
            if (roots.length == 0) {
                return new string[] {"Inbox"};
            }
            return roots;
        }

        private static string[] append_unique (string[] values, string value)
        {
            var clean = project_root (normalize_project (value, "Inbox"));
            string[] result = {};
            foreach (var item in values) {
                if (item == clean) {
                    return values;
                }
                result += item;
            }
            result += clean;
            return result;
        }

        private void uppercase_entry_first_letter (Gtk.Entry entry)
        {
            if (this.updating_text_case) {
                return;
            }
            var text = entry.text;
            var updated = uppercase_first_letter (text);
            if (text == updated) {
                return;
            }
            var position = entry.get_position ();
            this.updating_text_case = true;
            entry.text = updated;
            entry.set_position (int.min (position, updated.length));
            this.updating_text_case = false;
        }

        private void sanitize_structure_entry (Gtk.Entry entry, int max_length)
        {
            if (this.updating_text_case) {
                return;
            }
            var text = entry.text;
            var updated = sanitize_structure_name_input (text, max_length);
            if (text == updated) {
                return;
            }
            var position = entry.get_position ();
            this.updating_text_case = true;
            entry.text = updated;
            entry.set_position (int.min (position, updated.length));
            this.updating_text_case = false;
        }
    }
}
