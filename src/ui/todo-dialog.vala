namespace Tomodoro
{
    public delegate string? TodoSaveFunc (Todo todo, bool cascade_children);
    public delegate void TodoDeleteFunc ();

    public class TodoDialog : Adw.Window
    {
        private ContextConfig context;
        private Todo? original;
        private Todo? template_todo;
        private TodoSaveFunc on_save;
        private TodoDeleteFunc? on_delete;
        private string[] projects;
        private string[] main_projects;
        private Todo[] dependency_candidates;
        private string selected_dependency_id_value = "";
        private string[] active_priority_options = {};
        private bool main_project_locked = false;
        private bool dependencies_enabled = false;
        private bool auto_dependency_enabled = false;
        private bool recurring_instance_mode = false;
        private bool show_locked_project_fields = false;
        private string default_dependency_id = "";

        private Gtk.DropDown priority;
        private Gtk.Label priority_child_warning;
        private Gtk.Entry body;
        private Gtk.Label body_summary_hint;
        private Gtk.DropDown main_project;
        private Gtk.Entry subproject;
        private Gtk.SearchEntry dependency_search;
        private Gtk.MenuButton depends_on;
        private Gtk.Label dependency_button_label;
        private Gtk.Popover dependency_popover;
        private Gtk.Box dependency_choices;
        private Gtk.Label dependency_hint;
        private Gtk.Label dependency_notice;
        private Gtk.Entry due;
        private Gtk.Label due_child_warning;
        private Gtk.Calendar calendar;
        private Gtk.Revealer calendar_revealer;
        private Gtk.SpinButton pm;
        private Gtk.CheckButton completed;
        private Gtk.Label due_error_label;
        private Gtk.Label error_label;
        private bool updating_subproject = false;
        private bool updating_text_case = false;
        private bool body_has_focus = false;
        private bool suppress_subproject_autocomplete = false;
        private bool updating_dependency_choices = false;
        private bool updating_dependency_constraints = false;
        private bool updating_due_from_calendar = false;
        private bool updating_due_text = false;
        private bool updating_priority_selection = false;
        private bool manual_dependency_choice = false;
        private string dependency_adjustment_message = "";
        private uint calendar_window_animation = 0;
        private int calendar_animation_step = 0;
        private int calendar_animation_start_height = 420;
        private int calendar_animation_target_height = 420;
        private int previous_subproject_length = 0;
        private int previous_pm_before_completion = 1;

        public TodoDialog (
            Gtk.Window parent,
            ContextConfig context,
            string[] projects,
            Todo? todo,
            owned TodoSaveFunc on_save,
            owned TodoDeleteFunc? on_delete = null,
            string default_body = "",
            string default_project = "Inbox",
            string default_subproject = "Default",
            string default_priority = "C",
            string default_due = "",
            Todo[] dependency_candidates,
            bool dependencies_enabled,
            bool auto_dependency_enabled,
            string default_dependency_id,
            bool lock_main_project = false,
            bool focus_body_at_end = false,
            bool template_mode = false,
            bool show_locked_project_fields = false
        ) {
            Object (
                transient_for: parent,
                modal: true,
                title: todo == null || template_mode ? "New Todo" : "Edit Todo",
                default_width: 460,
                default_height: 420
            );

            this.context = context;
            this.original = template_mode ? null : todo;
            this.template_todo = template_mode ? todo : null;
            this.on_save = (owned) on_save;
            this.on_delete = (owned) on_delete;
            this.projects = projects;
            this.dependency_candidates = dependency_candidates;
            this.main_project_locked = lock_main_project;
            this.dependencies_enabled = dependencies_enabled;
            this.auto_dependency_enabled = auto_dependency_enabled;
            this.recurring_instance_mode = todo != null && todo.recurring_instance;
            this.show_locked_project_fields = show_locked_project_fields;
            this.default_dependency_id = is_valid_todo_id (default_dependency_id) ? default_dependency_id.down () : "";
            this.selected_dependency_id_value = this.default_dependency_id;
            this.main_projects = main_project_roots (projects, context.default_project, default_project);

            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            root.margin_top = 16;
            root.margin_bottom = 16;
            root.margin_start = 16;
            root.margin_end = 16;
            this.content = root;

            this.body = new Gtk.Entry ();
            this.body.placeholder_text = "Todo body";
            this.body.text = todo != null ? todo.body : normalize_body_text (default_body);
            this.body.sensitive = !this.recurring_instance_mode;
            this.body.changed.connect (() => uppercase_entry_first_letter (this.body));
            this.body.changed.connect (sync_body_summary_hint);
            this.body.activate.connect (save_clicked);
            var body_focus = new Gtk.EventControllerFocus ();
            body_focus.enter.connect (() => {
                this.body_has_focus = true;
                sync_body_summary_hint ();
            });
            body_focus.leave.connect (() => {
                this.body_has_focus = false;
                sync_body_summary_hint ();
            });
            this.body.add_controller (body_focus);
            this.body_summary_hint = new Gtk.Label ("");
            this.body_summary_hint.xalign = 0;
            this.body_summary_hint.wrap = true;
            this.body_summary_hint.visible = false;
            this.body_summary_hint.add_css_class ("caption");
            this.body_summary_hint.add_css_class ("dim-label");
            var body_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            body_box.append (this.body);
            body_box.append (this.body_summary_hint);
            root.append (row ("Body", body_box));

            this.active_priority_options = PRIORITY_OPTIONS;
            this.priority = new Gtk.DropDown.from_strings (this.active_priority_options);
            this.priority.factory = priority_factory ();
            var current_priority = todo != null ? todo.priority : default_priority.strip ().up ();
            if (!is_priority (current_priority)) {
                current_priority = "C";
            }
            this.priority.selected = selected_index (this.active_priority_options, current_priority, 2);
            add_priority_key_controller ();
            this.priority.notify["selected"].connect (priority_selection_changed);
            this.priority_child_warning = warning_label ();
            var priority_content = field_with_notice (this.priority, this.priority_child_warning);

            var current_project = todo != null ? todo.project : join_project (project_root (default_project), default_subproject);
            var current_main = todo != null
                ? project_root (current_project)
                : (this.main_project_locked ? project_root (default_project) : project_root (current_project));
            this.main_project = new Gtk.DropDown.from_strings (this.main_projects);
            this.main_project.selected = selected_index (this.main_projects, current_main, 0);
            this.main_project.sensitive = !this.recurring_instance_mode && !(this.main_project_locked && this.show_locked_project_fields);
            this.subproject = new Gtk.Entry ();
            this.subproject.placeholder_text = "Default";
            this.subproject.text = project_child (current_project) == "" ? "Default" : project_child (current_project);
            this.previous_subproject_length = this.subproject.text.length;
            this.subproject.changed.connect (() => sanitize_structure_entry (this.subproject, PROJECT_PART_MAX_LENGTH));
            this.subproject.changed.connect (autocomplete_subproject);
            this.subproject.changed.connect (refresh_dependency_choices);
            if (this.original != null) {
                this.subproject.sensitive = false;
                this.subproject.tooltip_text = "Subproject cannot be changed after creation";
            }
            var subproject_keys = new Gtk.EventControllerKey ();
            subproject_keys.key_pressed.connect ((keyval, keycode, state) => {
                if (keyval == Gdk.Key.BackSpace || keyval == Gdk.Key.Delete || keyval == Gdk.Key.Left || keyval == Gdk.Key.Right) {
                    this.suppress_subproject_autocomplete = true;
                }
                return false;
            });
            this.subproject.add_controller (subproject_keys);
            this.main_project.notify["selected"].connect (() => {
                this.previous_subproject_length = 0;
                autocomplete_subproject ();
                refresh_dependency_choices ();
            });
            autocomplete_subproject ();

            if (this.main_project_locked && !this.show_locked_project_fields) {
                var priority_project_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                priority_project_box.append (inline_field ("Priority", priority_content));
                priority_project_box.append (inline_field ("Subproject", this.subproject));
                root.append (priority_project_box);
            }
            else {
                root.append (row ("Priority", priority_content));
                var project_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                project_box.append (inline_field ("Main", this.main_project));
                project_box.append (inline_field ("Subproject", this.subproject));
                root.append (row ("Project", project_box));
            }

            if (this.recurring_instance_mode) {
                var template_label = new Gtk.Label (recurring_template_label ());
                template_label.xalign = 0;
                template_label.wrap = true;
                template_label.sensitive = false;
                var hint = new Gtk.Label ("Generated recurring todo. Only priority, pomodoros left, and completion can be changed.");
                hint.xalign = 0;
                hint.wrap = true;
                hint.add_css_class ("caption");
                hint.add_css_class ("dim-label");
                var template_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
                template_box.append (template_label);
                template_box.append (hint);
                root.append (row ("Recurring task template", template_box));
            }
            else if (this.dependencies_enabled) {
                this.depends_on = new Gtk.MenuButton ();
                this.depends_on.hexpand = true;
                this.dependency_button_label = new Gtk.Label ("None");
                this.dependency_button_label.xalign = 0;
                this.dependency_button_label.ellipsize = Pango.EllipsizeMode.END;
                this.depends_on.child = this.dependency_button_label;
                this.dependency_popover = new Gtk.Popover ();
                this.dependency_search = new Gtk.SearchEntry ();
                this.dependency_search.placeholder_text = "Search parents";
                this.dependency_search.search_changed.connect (refresh_dependency_choices);
                this.dependency_choices = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
                var dependency_scroller = new Gtk.ScrolledWindow ();
                dependency_scroller.child = this.dependency_choices;
                dependency_scroller.min_content_height = 190;
                dependency_scroller.max_content_height = 340;
                var dependency_popover_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
                dependency_popover_content.margin_top = 10;
                dependency_popover_content.margin_bottom = 10;
                dependency_popover_content.margin_start = 10;
                dependency_popover_content.margin_end = 10;
                dependency_popover_content.width_request = 320;
                dependency_popover_content.append (this.dependency_search);
                dependency_popover_content.append (dependency_scroller);
                this.dependency_popover.child = dependency_popover_content;
                this.dependency_popover.notify["visible"].connect (() => {
                    if (this.dependency_popover.visible) {
                        this.dependency_search.text = "";
                        refresh_dependency_choices ();
                        this.dependency_search.grab_focus ();
                    }
                });
                this.depends_on.popover = this.dependency_popover;
                this.dependency_hint = new Gtk.Label ("");
                this.dependency_hint.xalign = 0;
                this.dependency_hint.wrap = true;
                this.dependency_hint.visible = false;
                this.dependency_hint.add_css_class ("caption");
                this.dependency_hint.add_css_class ("error");
                this.dependency_notice = new Gtk.Label ("");
                this.dependency_notice.xalign = 0;
                this.dependency_notice.wrap = true;
                this.dependency_notice.visible = false;
                this.dependency_notice.add_css_class ("caption");
                this.dependency_notice.add_css_class ("dim-label");
                refresh_dependency_choices ();
                if (this.original != null) {
                    this.depends_on.sensitive = false;
                    this.depends_on.tooltip_text = "Dependency cannot be changed after creation";
                }
                var dependency_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
                dependency_box.append (this.depends_on);
                dependency_box.append (this.dependency_hint);
                dependency_box.append (this.dependency_notice);
                root.append (row ("Depends on", dependency_box));
            }

            this.due = new Gtk.Entry ();
            this.due.placeholder_text = "YYYY-MM-DD";
            this.due.hexpand = true;
            this.due.sensitive = !this.recurring_instance_mode;
            var initial_due = normalize_due_entry_text (todo != null ? todo.due : default_due);
            var initial_due_iso = due_input_to_iso (initial_due);
            if (initial_due_iso != "") {
                if (todo == null && date_is_before_today (initial_due_iso)) {
                    initial_due_iso = today_local ().format ("%F");
                }
                this.due.text = due_input_display_text (initial_due_iso);
            } else {
                this.due.text = "";
            }
            this.due.changed.connect (() => {
                if (this.updating_due_text) {
                    return;
                }
                this.dependency_adjustment_message = "";
                if (sanitize_due_entry ()) {
                    return;
                }
                validate_due ();
                sync_dependency_constraints_and_validation ();
            });

            this.due_error_label = new Gtk.Label ("Invalid date");
            this.due_error_label.xalign = 0;
            this.due_error_label.visible = false;
            this.due_error_label.add_css_class ("error");
            this.due_child_warning = warning_label ();

            var due_line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            due_line.append (this.due);
            due_line.append (this.due_error_label);

            this.calendar = new Gtk.Calendar ();
            var parsed_due = parse_date (current_due_date ());
            if (parsed_due != null) {
                this.calendar.set_date (parsed_due);
            }
            var calendar_click = new Gtk.GestureClick ();
            calendar_click.button = 1;
            calendar_click.released.connect (() => apply_calendar_selection ());
            this.calendar.add_controller (calendar_click);
            this.calendar_revealer = new Gtk.Revealer ();
            this.calendar_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
            this.calendar_revealer.transition_duration = 260;
            this.calendar_revealer.child = this.calendar;

            var due_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            due_box.append (due_line);
            due_box.append (this.due_child_warning);
            due_box.append (this.calendar_revealer);
            var due_focus = new Gtk.EventControllerFocus ();
            due_focus.enter.connect (() => {
                show_numeric_due_text_for_editing ();
                set_calendar_visible (true);
            });
            due_focus.leave.connect (() => set_calendar_visible (false));
            due_box.add_controller (due_focus);
            var due_entry_focus = new Gtk.EventControllerFocus ();
            due_entry_focus.enter.connect (() => show_numeric_due_text_for_editing ());
            due_entry_focus.leave.connect (() => validate_due ());
            this.due.add_controller (due_entry_focus);
            root.append (row ("Due date", due_box));

            sync_dependency_constraints_and_validation ();

            this.pm = new Gtk.SpinButton.with_range (0, 99, 1);
            this.pm.value = todo != null ? todo.pm : 1;
            this.previous_pm_before_completion = todo != null
                ? (todo.pm > 0 ? todo.pm : todo.previous_pm_or_default (1))
                : 1;
            this.pm.value_changed.connect (sync_completed_from_pm);
            root.append (row ("Pomodoros left", this.pm));

            this.completed = new Gtk.CheckButton.with_label ("Completed");
            this.completed.active = this.pm.get_value_as_int () == 0;
            this.completed.toggled.connect (completed_toggled);
            root.append (this.completed);
            sync_completed_from_pm ();

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

            if (focus_body_at_end) {
                this.map.connect (() => {
                    this.body.grab_focus ();
                    this.body.set_position (this.body.text.length);
                });
            }
        }

        private void save_clicked ()
        {
            var due_date = current_due_date ();
            if (this.due.text.strip () != "" && !due_input_is_valid (this.due.text.strip ())) {
                show_due_error ();
                return;
            }
            if (!this.recurring_instance_mode && due_date != "" && date_is_before_today (due_date)) {
                show_due_error ("Due date cannot be before today.");
                return;
            }

            var body_text = normalize_body_text (this.body.text);
            if (!has_minimum_letters (body_text)) {
                show_error ("Todo body needs at least three letters.");
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

            if (show_dependency_validation_errors ()) {
                return;
            }

            var metadata_source = this.original != null ? this.original : this.template_todo;
            var item = new Todo ();
            item.id = this.original != null ? this.original.id : "";
            item.body = this.recurring_instance_mode && this.original != null ? this.original.body : body_text;
            item.priority = selected_priority_value ();
            item.due = this.recurring_instance_mode && this.original != null ? this.original.due : due_date;
            item.project = this.original != null ? this.original.project : join_project (main_project_text, subproject_text);
            item.pm = this.pm.get_value_as_int ();
            item.pm_done = metadata_source != null ? metadata_source.pm_done : 0;
            item.completed = item.pm == 0;
            item.dependency_id = this.recurring_instance_mode
                ? ""
                : (this.dependencies_enabled
                ? selected_dependency_id ()
                : (this.original != null ? this.original.dependency_id : ""));
            item.recurrence = RECURRENCE_NONE;
            item.recurrence_anchor_day = 0;
            item.recurrence_weekdays = "";
            item.recurrence_parent_id = this.recurring_instance_mode && this.original != null ? this.original.recurrence_parent_id : "";
            if (metadata_source != null) {
                foreach (var tag in metadata_source.get_extra_tags ()) {
                    item.add_extra_tag (tag);
                }
            }
            if (item.completed) {
                item.remember_pm_before_completion (item.pm > 0 ? item.pm : this.previous_pm_before_completion);
                item.pm = 0;
            }
            else {
                item.clear_previous_pm ();
            }

            var cascade_children = has_child_constraint_warning (item);
            var error = this.on_save (item, cascade_children);
            if (error != null) {
                show_error (error);
                return;
            }

            this.close ();
        }

        private void validate_due ()
        {
            if (this.updating_due_from_calendar) {
                return;
            }

            var text = this.due.text.strip ();
            var due_date = current_due_date ();
            if (text == "" || due_date != "") {
                if (due_date != "" && date_is_before_today (due_date)) {
                    show_due_error ("Due date cannot be before today.");
                    sync_dependency_constraints_and_validation ();
                    return;
                }
                clear_due_error ();
                var parsed = parse_date (due_date);
                if (parsed != null) {
                    this.calendar.set_date (parsed);
                }
                sync_dependency_constraints_and_validation ();
                return;
            }

            show_due_error ();
        }

        private bool sanitize_due_entry ()
        {
            var clean = normalize_due_entry_text (this.due.text);
            if (clean == this.due.text) {
                return false;
            }

            replace_due_text (clean);
            return true;
        }

        private string normalize_due_entry_text (string value)
        {
            var text = value.strip ();
            if (text == "") {
                return "";
            }
            var due_date = due_input_to_iso (text);
            if (due_date != "") {
                return due_date;
            }
            if (text.length >= 20) {
                var first = text.substring (0, 10);
                var last = text.substring (text.length - 10, 10);
                if (is_valid_date (first) && is_valid_date (last)) {
                    return last;
                }
            }
            return text;
        }

        private void replace_due_text (string value)
        {
            if (this.due == null) {
                return;
            }

            var clean = normalize_due_entry_text (value);
            this.updating_due_text = true;
            this.due.set_text (clean);
            this.due.set_position (clean.length);
            this.updating_due_text = false;
            validate_due ();
            sync_dependency_constraints_and_validation ();
        }

        private void replace_due_text_for_display (string value)
        {
            if (this.due == null) {
                return;
            }

            var clean = normalize_due_entry_text (value);
            var display = due_input_display_text (clean);
            this.updating_due_text = true;
            this.due.set_text (display);
            this.due.set_position (display.length);
            this.updating_due_text = false;
            validate_due ();
            sync_dependency_constraints_and_validation ();
        }

        private void show_numeric_due_text_for_editing ()
        {
            if (this.due == null || this.updating_due_text) {
                return;
            }

            var due_date = current_due_date ();
            if (due_date == "" || this.due.text == due_date) {
                return;
            }

            this.updating_due_text = true;
            this.due.set_text (due_date);
            this.due.select_region (0, due_date.length);
            this.updating_due_text = false;
        }

        private void apply_calendar_selection ()
        {
            if (this.calendar == null || this.due == null || this.updating_due_from_calendar) {
                return;
            }

            this.updating_due_from_calendar = true;
            var selected = this.calendar.get_date ();
            this.updating_due_from_calendar = false;
            if (selected.to_unix () < today_local ().to_unix ()) {
                selected = today_local ();
                this.calendar.set_date (selected);
            }
            replace_due_text_for_display (selected.format ("%F"));
            set_calendar_visible (false);
        }

        private void show_due_error (string message = "Invalid date")
        {
            this.due.add_css_class ("error");
            this.due_error_label.label = message;
            this.due_error_label.visible = true;
        }

        private void clear_due_error ()
        {
            this.due.remove_css_class ("error");
            this.due_error_label.label = "Invalid date";
            this.due_error_label.visible = false;
        }

        private void show_error (string message)
        {
            this.error_label.label = message;
            this.error_label.visible = true;
        }

        private void sync_body_summary_hint ()
        {
            if (this.body_summary_hint == null) {
                return;
            }

            var body_text = compact_text (this.body.text);
            var summary = todo_body_summary (body_text);
            if (!this.body_has_focus || body_text == "") {
                this.body_summary_hint.visible = false;
                return;
            }

            if (body_text.length <= TODO_SUMMARY_MAX_CHARS) {
                this.body_summary_hint.visible = false;
                return;
            }

            if (!has_explicit_todo_summary (body_text)) {
                this.body_summary_hint.label = "Add a short first sentence ending with `. ` to set the timer summary.";
                this.body_summary_hint.visible = true;
                return;
            }

            if (summary.length > TODO_SUMMARY_MAX_CHARS) {
                this.body_summary_hint.label = "Keep the first sentence shorter; it is used as the timer summary.";
                this.body_summary_hint.visible = true;
                return;
            }

            this.body_summary_hint.visible = false;
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

        private void set_calendar_visible (bool visible)
        {
            animate_window_height (visible ? 650 : 420);
            this.calendar_revealer.reveal_child = visible;
        }

        private void animate_window_height (int target_height)
        {
            if (this.calendar_window_animation != 0) {
                GLib.Source.remove (this.calendar_window_animation);
                this.calendar_window_animation = 0;
            }

            var current_height = this.get_height ();
            this.calendar_animation_start_height = current_height > 0 ? current_height : 420;
            this.calendar_animation_target_height = target_height;
            this.calendar_animation_step = 0;

            this.calendar_window_animation = GLib.Timeout.add (16, () => {
                this.calendar_animation_step++;
                var progress = this.calendar_animation_step >= 16 ? 1.0 : this.calendar_animation_step / 16.0;
                var remaining = 1.0 - progress;
                var eased = 1.0 - remaining * remaining * remaining;
                var height = this.calendar_animation_start_height
                    + (int) ((this.calendar_animation_target_height - this.calendar_animation_start_height) * eased);
                this.set_default_size (460, height);
                this.queue_resize ();

                if (progress >= 1.0) {
                    this.set_default_size (460, this.calendar_animation_target_height);
                    this.calendar_window_animation = 0;
                    return GLib.Source.REMOVE;
                }
                return GLib.Source.CONTINUE;
            });
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

        private Gtk.Label warning_label ()
        {
            var label = new Gtk.Label ("");
            label.xalign = 0;
            label.wrap = true;
            label.visible = false;
            label.add_css_class ("caption");
            label.add_css_class ("warning");
            return label;
        }

        private Gtk.Widget field_with_notice (Gtk.Widget field, Gtk.Label notice)
        {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            box.append (field);
            box.append (notice);
            return box;
        }

        private void clear_box (Gtk.Box box)
        {
            var child = box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                box.remove (child);
                child = next;
            }
        }

        private void sync_completed_from_pm ()
        {
            if (this.completed == null || this.pm == null) {
                return;
            }

            var current_pm = this.pm.get_value_as_int ();
            if (current_pm > 0) {
                this.previous_pm_before_completion = current_pm;
            }

            if (current_pm == 0) {
                if (!this.completed.active) {
                    this.completed.active = true;
                }
                return;
            }

            if (this.completed.active) {
                this.completed.active = false;
            }
        }

        private void completed_toggled ()
        {
            if (this.completed == null || this.pm == null) {
                return;
            }

            if (this.completed.active) {
                if (this.pm.get_value_as_int () != 0) {
                    this.previous_pm_before_completion = this.pm.get_value_as_int ();
                    this.pm.value = 0;
                }
                return;
            }

            if (this.pm.get_value_as_int () == 0) {
                this.pm.value = this.previous_pm_before_completion > 0 ? this.previous_pm_before_completion : 1;
            }
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
                var available = priority_value_available (value);
                row.sensitive = available;
                if (available) {
                    row.remove_css_class ("dim-label");
                }
                else {
                    row.add_css_class ("dim-label");
                }
            });
            return factory;
        }

        private void priority_selection_changed ()
        {
            if (this.updating_priority_selection) {
                return;
            }

            var value = selected_priority_value ();
            if (!priority_value_available (value)) {
                var parent = selected_dependency ();
                var fallback = parent == null ? "C" : parent.priority;
                set_priority_value (fallback);
                this.dependency_adjustment_message = "Priority changed to %s because the selected parent is priority %s.".printf (
                    fallback,
                    fallback
                );
                sync_dependency_constraints_and_validation ();
                return;
            }

            this.dependency_adjustment_message = "";
            sync_dependency_constraints_and_validation ();
        }

        private bool priority_value_available (string value)
        {
            var parent = selected_dependency ();
            return priority_option_in_list (this.active_priority_options, value)
                && (parent == null || priority_rank (value) >= priority_rank (parent.priority));
        }

        private void set_priority_value (string value)
        {
            var clean = is_priority (value) ? value : "C";
            if (!priority_option_in_list (this.active_priority_options, clean)) {
                clean = default_priority_for_options (this.active_priority_options);
            }
            this.updating_priority_selection = true;
            this.priority.selected = selected_index (this.active_priority_options, clean, 0);
            this.updating_priority_selection = false;
        }

        private void set_priority_options (string[] options, string selected)
        {
            var next_options = options.length == 0 ? PRIORITY_OPTIONS : options;
            var next_selected = is_priority (selected) ? selected : default_priority_for_options (next_options);
            if (!priority_option_in_list (next_options, next_selected)) {
                next_selected = default_priority_for_options (next_options);
            }

            this.updating_priority_selection = true;
            if (!priority_options_equal (this.active_priority_options, next_options)) {
                var model = new Gtk.StringList (null);
                foreach (var option in next_options) {
                    model.append (option);
                }
                this.active_priority_options = next_options;
                this.priority.model = model;
            }
            this.priority.selected = selected_index (this.active_priority_options, next_selected, 0);
            this.updating_priority_selection = false;
        }

        private string[] priority_options_for_dependency (Todo? dependency)
        {
            if (dependency == null || !is_priority (dependency.priority)) {
                return PRIORITY_OPTIONS;
            }

            string[] options = {};
            var parent_rank = priority_rank (dependency.priority);
            foreach (var option in PRIORITY_OPTIONS) {
                if (priority_rank (option) >= parent_rank) {
                    options += option;
                }
            }
            return options;
        }

        private bool priority_options_equal (string[] left, string[] right)
        {
            if (left.length != right.length) {
                return false;
            }
            for (var index = 0; index < left.length; index++) {
                if (left[index] != right[index]) {
                    return false;
                }
            }
            return true;
        }

        private bool priority_option_in_list (string[] options, string value)
        {
            foreach (var option in options) {
                if (option == value) {
                    return true;
                }
            }
            return false;
        }

        private string default_priority_for_options (string[] options)
        {
            if (priority_option_in_list (options, "C")) {
                return "C";
            }
            return options.length > 0 ? options[0] : "C";
        }

        private void add_priority_key_controller ()
        {
            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect ((keyval, keycode, state) => {
                var priority = priority_from_key (keyval);
                if (priority == "") {
                    return false;
                }
                if (!priority_value_available (priority)) {
                    var parent = selected_dependency ();
                    if (parent != null) {
                        this.dependency_adjustment_message = "%s is unavailable because the selected parent is priority %s.".printf (
                            priority,
                            parent.priority
                        );
                        sync_dependency_notice ();
                    }
                    return true;
                }
                set_priority_value (priority);
                sync_dependency_constraints_and_validation ();
                return true;
            });
            this.priority.add_controller (keys);
        }

        private string priority_from_key (uint keyval)
        {
            switch (keyval)
            {
                case Gdk.Key.a:
                case Gdk.Key.A:
                    return "A";
                case Gdk.Key.b:
                case Gdk.Key.B:
                    return "B";
                case Gdk.Key.c:
                case Gdk.Key.C:
                    return "C";
                case Gdk.Key.d:
                case Gdk.Key.D:
                    return "D";
                case Gdk.Key.e:
                case Gdk.Key.E:
                    return "E";
                case Gdk.Key.f:
                case Gdk.Key.F:
                    return "F";
                case Gdk.Key.g:
                case Gdk.Key.G:
                    return "G";
                case Gdk.Key.h:
                case Gdk.Key.H:
                    return "H";
                default:
                    return "";
            }
        }

        private void autocomplete_subproject ()
        {
            if (this.updating_subproject) {
                return;
            }

            var typed = this.subproject.text.strip ().down ();
            var typed_length = this.subproject.text.length;
            if (typed == "") {
                this.previous_subproject_length = typed_length;
                return;
            }

            int selection_start;
            int selection_end;
            if (this.subproject.get_selection_bounds (out selection_start, out selection_end)
                || this.subproject.get_position () != this.subproject.text.length
                || this.suppress_subproject_autocomplete) {
                this.suppress_subproject_autocomplete = false;
                this.previous_subproject_length = typed_length;
                return;
            }

            if (typed_length < this.previous_subproject_length) {
                this.previous_subproject_length = typed_length;
                return;
            }

            foreach (var suggestion in subprojects_for_main (selected_main_project ())) {
                var candidate = suggestion.down ();
                if (!candidate.has_prefix (typed) || candidate == typed) {
                    continue;
                }

                this.updating_subproject = true;
                this.subproject.text = suggestion;
                this.subproject.select_region (typed_length, suggestion.length);
                this.previous_subproject_length = suggestion.length;
                this.updating_subproject = false;
                return;
            }

            this.previous_subproject_length = typed_length;
        }

        private void refresh_dependency_choices ()
        {
            if (!this.dependencies_enabled || this.depends_on == null || this.dependency_choices == null) {
                return;
            }

            var selected_id = this.selected_dependency_id_value;
            if (selected_id == "") {
                selected_id = this.default_dependency_id;
            }
            if (this.original != null && selected_id == "") {
                selected_id = this.original.dependency_id;
            }

            clear_box (this.dependency_choices);
            var project = current_dialog_project ();
            var search = this.dependency_search == null ? "" : this.dependency_search.text.down ().strip ();
            Todo[] visible_candidates = {};
            var selected_visible = selected_id == "";
            foreach (var candidate in this.dependency_candidates) {
                if (candidate.completed
                    || candidate.id == ""
                    || candidate.project != project
                    || (this.original != null && candidate.id == this.original.id)
                    || dependency_creates_cycle (candidate.id)) {
                    continue;
                }
                var label = dependency_candidate_label (candidate);
                if (search != ""
                    && candidate.id != selected_id
                    && !candidate.body.down ().contains (search)
                    && !label.down ().contains (search)) {
                    continue;
                }
                visible_candidates += candidate;
                if (candidate.id == selected_id) {
                    selected_visible = true;
                }
            }

            if (!selected_visible) {
                selected_id = "";
            }

            if (selected_id == ""
                && this.auto_dependency_enabled
                && !this.manual_dependency_choice
                && this.original == null
                && visible_candidates.length > 0) {
                selected_id = visible_candidates[visible_candidates.length - 1].id;
            }

            this.updating_dependency_choices = true;
            this.selected_dependency_id_value = selected_id;
            this.dependency_choices.append (dependency_choice_button ("None", ""));
            var matches = 0;
            foreach (var candidate in visible_candidates) {
                matches++;
                this.dependency_choices.append (dependency_choice_button (
                    dependency_candidate_label (candidate),
                    candidate.id
                ));
            }
            if (matches == 0 && search != "") {
                var empty = new Gtk.Label ("No matching parents");
                empty.xalign = 0;
                empty.add_css_class ("caption");
                this.dependency_choices.append (empty);
            }
            sync_dependency_button_label ();
            this.updating_dependency_choices = false;
            sync_dependency_constraints_and_validation ();
        }

        private Gtk.Button dependency_choice_button (string label, string id)
        {
            var button = new Gtk.Button ();
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var label_widget = new Gtk.Label (label);
            label_widget.xalign = 0;
            label_widget.ellipsize = Pango.EllipsizeMode.END;
            row.append (label_widget);
            button.child = row;
            button.hexpand = true;
            if (id == selected_dependency_id ()) {
                button.add_css_class ("suggested-action");
            }
            button.clicked.connect (() => {
                if (!this.updating_dependency_choices) {
                    this.manual_dependency_choice = true;
                }
                this.dependency_adjustment_message = "";
                this.selected_dependency_id_value = is_valid_todo_id (id) ? id.down () : "";
                this.default_dependency_id = this.selected_dependency_id_value;
                sync_dependency_button_label ();
                refresh_dependency_choices ();
                if (this.dependency_popover != null) {
                    this.dependency_popover.popdown ();
                }
                sync_dependency_constraints_and_validation ();
            });
            return button;
        }

        private void sync_dependency_button_label ()
        {
            if (this.dependency_button_label == null) {
                return;
            }
            var dependency = selected_dependency ();
            this.dependency_button_label.label = dependency == null
                ? "None"
                : dependency_candidate_label (dependency);
        }

        private string selected_dependency_id ()
        {
            if (!this.dependencies_enabled || this.depends_on == null) {
                return "";
            }
            return is_valid_todo_id (this.selected_dependency_id_value) ? this.selected_dependency_id_value.down () : "";
        }

        private string current_dialog_project ()
        {
            return join_project (
                selected_main_project (),
                project_root (normalize_project (this.subproject.text, "Default"))
            );
        }

        private string dependency_candidate_label (Todo todo)
        {
            return todo_display_summary (todo, TODO_SUMMARY_MAX_CHARS);
        }

        private string recurring_template_label ()
        {
            if (this.original == null || this.original.recurrence_parent_id == "") {
                return "Unknown template";
            }
            foreach (var candidate in this.dependency_candidates) {
                if (candidate.id == this.original.recurrence_parent_id && candidate.recurring) {
                    return "%s - %s".printf (
                        todo_display_summary (candidate, TODO_SUMMARY_MAX_CHARS),
                        recurrence_schedule_label (candidate)
                    );
                }
            }
            return "Template %s".printf (this.original.recurrence_parent_id);
        }

        private void sync_dependency_validation ()
        {
            if (!this.dependencies_enabled
                || this.depends_on == null
                || this.dependency_hint == null
                || this.priority == null
                || this.due == null) {
                return;
            }

            this.depends_on.remove_css_class ("error");
            this.dependency_hint.visible = false;
            if (this.due.text.strip () == "" || current_due_date () != "") {
                clear_due_error ();
            }

            var selector_error = dependency_selector_validation_error ();
            if (selector_error != "") {
                show_dependency_error (selector_error);
            }

            var due_error = dependency_due_validation_error ();
            if (due_error != "") {
                show_due_error (due_error);
                return;
            }

        }

        private void sync_dependency_constraints_and_validation ()
        {
            apply_dependency_constraints ();
            sync_dependency_validation ();
            sync_dependency_notice ();
            sync_child_constraint_warnings ();
        }

        private void apply_dependency_constraints ()
        {
            if (!this.dependencies_enabled
                || this.updating_dependency_constraints
                || this.depends_on == null
                || this.priority == null
                || this.due == null
                || this.calendar == null) {
                return;
            }

            this.updating_dependency_constraints = true;
            var dependency = selected_dependency ();
            var current_priority = selected_priority_value ();
            var next_priority = current_priority;
            var priority_options = priority_options_for_dependency (dependency);
            if (!priority_option_in_list (priority_options, next_priority)) {
                next_priority = dependency == null
                    ? default_priority_for_options (priority_options)
                    : dependency.priority;
            }

            set_priority_options (priority_options, next_priority);

            if (dependency != null && current_priority != next_priority) {
                this.dependency_adjustment_message = "Priority changed to %s because the selected parent is priority %s.".printf (
                    next_priority,
                    dependency.priority
                );
            }

            this.updating_dependency_constraints = false;
        }

        private string selected_priority_value ()
        {
            if (this.active_priority_options.length == 0) {
                this.active_priority_options = PRIORITY_OPTIONS;
            }
            if (this.priority != null && this.priority.selected < this.active_priority_options.length) {
                return this.active_priority_options[this.priority.selected];
            }
            return "C";
        }

        private void show_dependency_error (string message)
        {
            if (this.depends_on == null || this.dependency_hint == null) {
                show_error (message);
                return;
            }

            this.depends_on.add_css_class ("error");
            this.dependency_hint.label = message;
            this.dependency_hint.visible = true;
        }

        private void sync_dependency_notice ()
        {
            if (!this.dependencies_enabled
                || this.dependency_notice == null
                || this.priority == null
                || this.due == null
                || this.body == null) {
                return;
            }

            string[] messages = {};
            if (this.dependency_adjustment_message != "") {
                messages += this.dependency_adjustment_message;
            }

            this.dependency_notice.remove_css_class ("warning");
            this.dependency_notice.remove_css_class ("error");
            this.dependency_notice.add_css_class ("dim-label");

            if (messages.length == 0) {
                this.dependency_notice.label = "";
                this.dependency_notice.visible = false;
                return;
            }

            this.dependency_notice.label = string.joinv ("\n", messages);
            this.dependency_notice.visible = true;
        }

        private bool show_dependency_validation_errors ()
        {
            if (!this.dependencies_enabled || this.depends_on == null) {
                return false;
            }

            var selector_error = dependency_selector_validation_error ();
            if (selector_error != "") {
                show_dependency_error (selector_error);
                return true;
            }

            var priority_error = dependency_priority_validation_error ();
            if (priority_error != "") {
                show_dependency_error (priority_error);
                return true;
            }

            var due_error = dependency_due_validation_error ();
            if (due_error != "") {
                show_due_error (due_error);
                return true;
            }

            return false;
        }

        private string dependency_selector_validation_error ()
        {
            if (!this.dependencies_enabled || this.depends_on == null) {
                return "";
            }

            var dependency_id = selected_dependency_id ();
            if (dependency_id == "") {
                return "";
            }

            if (dependency_creates_cycle (dependency_id)) {
                return "Dependency would create a circular chain.";
            }

            return "";
        }

        private string dependency_priority_validation_error ()
        {
            if (!this.dependencies_enabled || this.depends_on == null) {
                return "";
            }

            var dependency_id = selected_dependency_id ();
            if (dependency_id == "" || dependency_creates_cycle (dependency_id)) {
                return "";
            }

            var dependency = dependency_candidate_by_id (dependency_id);
            if (dependency == null) {
                return "";
            }

            var current_priority = selected_priority_value ();
            if (priority_rank (current_priority) < priority_rank (dependency.priority)) {
                return "Child priority cannot be higher than parent priority.";
            }

            return "";
        }

        private string dependency_due_validation_error ()
        {
            if (!this.dependencies_enabled || this.depends_on == null) {
                return "";
            }

            var dependency_id = selected_dependency_id ();
            if (dependency_id == "" || dependency_creates_cycle (dependency_id)) {
                return "";
            }

            var dependency = dependency_candidate_by_id (dependency_id);
            if (dependency == null) {
                return "";
            }

            var current_due = current_due_date ();
            if (this.due.text.strip () != "" && current_due == "") {
                return "";
            }
            if (dependency.due != "" && (current_due == "" || compare_date_strings (current_due, dependency.due) < 0)) {
                return "Child due date must be on or after parent due date %s.".printf (dependency.due);
            }

            return "";
        }

        private Todo? selected_dependency ()
        {
            return dependency_candidate_by_id (selected_dependency_id ());
        }

        private void sync_child_constraint_warnings ()
        {
            if (this.original == null
                || !this.dependencies_enabled
                || this.body == null
                || this.priority == null
                || this.due == null) {
                set_warning_text (this.priority_child_warning, "");
                set_warning_text (this.due_child_warning, "");
                return;
            }

            var item = current_dialog_todo_for_constraints ();
            set_warning_text (this.priority_child_warning, child_priority_constraint_warning (item));
            set_warning_text (this.due_child_warning, child_due_constraint_warning (item));
        }

        private void set_warning_text (Gtk.Label? label, string message)
        {
            if (label == null) {
                return;
            }
            label.label = message;
            label.visible = message != "";
        }

        private Todo current_dialog_todo_for_constraints ()
        {
            var item = new Todo ();
            item.id = this.original != null ? this.original.id : "";
            item.body = normalize_body_text (this.body.text);
            item.priority = selected_priority_value ();
            item.due = current_due_date ();
            item.project = this.original != null ? this.original.project : current_dialog_project ();
            item.pm = this.pm != null ? this.pm.get_value_as_int () : 1;
            item.completed = item.pm == 0;
            item.dependency_id = selected_dependency_id ();
            return item;
        }

        private string current_due_date ()
        {
            return this.due == null ? "" : due_input_to_iso (this.due.text);
        }

        private bool dependency_creates_cycle (string dependency_id)
        {
            if (this.original == null || this.original.id == "") {
                return false;
            }

            var target_id = this.original.id;
            var current_id = dependency_id.down ();
            var seen = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
            while (current_id != "") {
                if (current_id == target_id || seen.lookup (current_id) != null) {
                    return true;
                }
                seen.insert (current_id, current_id);

                var current = dependency_candidate_by_id (current_id);
                if (current == null) {
                    return false;
                }
                current_id = current.dependency_id;
            }
            return false;
        }

        private Todo? dependency_candidate_by_id (string id)
        {
            var clean = id.down ();
            foreach (var candidate in this.dependency_candidates) {
                if (candidate.id == clean) {
                    return candidate;
                }
            }
            return null;
        }

        private bool has_child_constraint_warning (Todo parent)
        {
            if (!this.dependencies_enabled || this.original == null || parent.id == "") {
                return false;
            }

            return child_priority_constraint_count (parent) > 0 || child_due_constraint_count (parent) > 0;
        }

        private string child_priority_constraint_warning (Todo parent)
        {
            var count = child_priority_constraint_count (parent);
            if (count == 0) {
                return "";
            }
            return "%s %s priority higher than this todo. Save will overwrite children.".printf (
                child_count_text (count),
                count == 1 ? "has" : "have"
            );
        }

        private string child_due_constraint_warning (Todo parent)
        {
            var count = child_due_constraint_count (parent);
            if (count == 0) {
                return "";
            }
            return "%s %s due date earlier than this todo. Save will overwrite children.".printf (
                child_count_text (count),
                count == 1 ? "has" : "have"
            );
        }

        private int child_priority_constraint_count (Todo parent)
        {
            if (!this.dependencies_enabled || this.original == null || parent.id == "") {
                return 0;
            }

            var count = 0;
            foreach (var child in dependency_children_for_parent (parent.id)) {
                if (priority_rank (child.priority) < priority_rank (parent.priority)) {
                    count++;
                }
            }
            return count;
        }

        private int child_due_constraint_count (Todo parent)
        {
            if (!this.dependencies_enabled || this.original == null || parent.id == "" || parent.due == "" || !is_valid_date (parent.due)) {
                return 0;
            }

            var count = 0;
            foreach (var child in dependency_children_for_parent (parent.id)) {
                if (child.due == "" || compare_date_strings (child.due, parent.due) < 0) {
                    count++;
                }
            }
            return count;
        }

        private string child_count_text (int count)
        {
            return count == 1 ? "1 child" : "%d children".printf (count);
        }

        private Todo[] dependency_children_for_parent (string parent_id)
        {
            Todo[] result = {};
            foreach (var candidate in this.dependency_candidates) {
                if (candidate.completed
                    || candidate.id == ""
                    || candidate.id == parent_id
                    || candidate.project != current_dialog_project ()) {
                    continue;
                }
                if (todo_depends_on_parent (candidate, parent_id)) {
                    result += candidate;
                }
            }
            return result;
        }

        private bool todo_depends_on_parent (Todo todo, string parent_id)
        {
            var current_id = todo.dependency_id;
            var seen = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
            while (current_id != "") {
                if (current_id == parent_id) {
                    return true;
                }
                if (seen.lookup (current_id) != null) {
                    return false;
                }
                seen.insert (current_id, current_id);

                var current = dependency_candidate_by_id (current_id);
                if (current == null) {
                    return false;
                }
                current_id = current.dependency_id;
            }
            return false;
        }

        private int compare_date_strings (string left, string right)
        {
            var left_date = parse_date (left);
            var right_date = parse_date (right);
            if (left_date == null || right_date == null) {
                return GLib.strcmp (left, right);
            }
            var left_days = days_from_iso_date (left);
            var right_days = days_from_iso_date (right);
            return left_days - right_days;
        }

        private int days_from_iso_date (string value)
        {
            var date = parse_date (value);
            if (date == null) {
                return 0;
            }
            var today = today_local ();
            return date_delta_days (value)
                + days_from_civil_for_dialog (today.get_year (), today.get_month (), today.get_day_of_month ());
        }

        private int days_from_civil_for_dialog (int year, int month, int day)
        {
            var adjusted_year = year - (month <= 2 ? 1 : 0);
            var era = (adjusted_year >= 0 ? adjusted_year : adjusted_year - 399) / 400;
            var year_of_era = adjusted_year - era * 400;
            var month_prime = month + (month > 2 ? -3 : 9);
            var day_of_year = (153 * month_prime + 2) / 5 + day - 1;
            var day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
            return era * 146097 + day_of_era;
        }

        private string selected_main_project ()
        {
            var index = this.main_project.selected;
            if (index < this.main_projects.length) {
                return this.main_projects[index];
            }
            if (this.main_projects.length > 0) {
                return this.main_projects[0];
            }
            return "Inbox";
        }

        private string[] subprojects_for_main (string main)
        {
            string[] values = {"Default"};
            foreach (var project in this.projects) {
                if (project_root (project) != main) {
                    continue;
                }
                var child = project_child (project);
                if (child != "") {
                    values = append_unique_value (values, child);
                }
            }
            return values;
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

        private static uint selected_index (string[] values, string selected, uint fallback)
        {
            for (uint index = 0; index < values.length; index++) {
                if (values[index] == selected) {
                    return index;
                }
            }
            return fallback < values.length ? fallback : 0;
        }

        private static string[] append_unique (string[] values, string value)
        {
            var clean = normalize_project (value, "Inbox");
            clean = project_root (clean);
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

        private static string[] append_unique_value (string[] values, string value)
        {
            string[] result = {};
            foreach (var item in values) {
                if (item == value) {
                    return values;
                }
                result += item;
            }
            result += value;
            return result;
        }

    }
}
