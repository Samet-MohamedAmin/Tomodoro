namespace Tomodoro
{
    public delegate void PreferencesChangedFunc ();

    public class PreferencesWindow : Adw.Window
    {
        private Store store;
        private PreferencesChangedFunc on_changed;
        private PreferencesChangedFunc on_shortcuts;
        private Gtk.DropDown profile_dropdown;
        private Adw.ToggleGroup pomodoro_display_group;
        private Gtk.Switch compact_timer_actions;
        private Gtk.Switch show_delete_button;
        private Gtk.Switch dependencies_enabled;
        private Gtk.Switch auto_depend_on_previous_todo;
        private Gtk.Switch project_dependency_graph;
        private Gtk.Switch calendar_events;

        public PreferencesWindow (
            Gtk.Window parent,
            Store store,
            bool show_compact_timer_actions,
            owned PreferencesChangedFunc on_changed,
            owned PreferencesChangedFunc on_shortcuts
        )
        {
            Object (
                transient_for: parent,
                modal: true,
                title: "Settings",
                default_width: 420,
                default_height: 300
            );

            this.store = store;
            this.on_changed = (owned) on_changed;
            this.on_shortcuts = (owned) on_shortcuts;

            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            root.margin_top = 18;
            root.margin_bottom = 18;
            root.margin_start = 18;
            root.margin_end = 18;
            this.content = root;

            var heading = new Gtk.Label ("Pomodoro");
            heading.xalign = 0;
            heading.add_css_class ("title-3");
            root.append (heading);

            string[] profile_names = {};
            foreach (var profile in store.pomodoro_profiles ()) {
                profile_names += profile.summary ();
            }
            if (profile_names.length == 0) {
                profile_names = new string[] {"Classic · 25 / 5 min"};
            }
            this.profile_dropdown = new Gtk.DropDown.from_strings (profile_names);
            uint selected = 0;
            var profiles = store.pomodoro_profiles ();
            for (uint index = 0; index < profiles.length; index++) {
                if (profiles[index].slug == store.selected_profile_slug) {
                    selected = index;
                    break;
                }
            }
            this.profile_dropdown.selected = selected;
            this.profile_dropdown.notify["selected"].connect (() => {
                var selected_index = this.profile_dropdown.selected;
                var current_profiles = this.store.pomodoro_profiles ();
                if (selected_index < current_profiles.length) {
                    this.store.set_selected_profile (current_profiles[selected_index].slug);
                    this.on_changed ();
                }
            });
            root.append (framed ("Profile", this.profile_dropdown));

            var note = new Gtk.Label ("Applies to future timer resets only.");
            note.xalign = 0;
            note.wrap = true;
            note.add_css_class ("caption");
            root.append (note);

            this.pomodoro_display_group = new Adw.ToggleGroup ();
            this.pomodoro_display_group.homogeneous = true;
            this.pomodoro_display_group.can_shrink = false;
            this.pomodoro_display_group.add (display_toggle ("duplicate", true));
            this.pomodoro_display_group.add (display_toggle ("number", false));
            this.pomodoro_display_group.active_name = store.repeat_pomodoro_icons ? "duplicate" : "number";
            this.pomodoro_display_group.notify["active-name"].connect (() => {
                this.store.repeat_pomodoro_icons = this.pomodoro_display_group.active_name != "number";
                this.store.save ();
                this.on_changed ();
            });

            root.append (framed ("Pomodoro display", this.pomodoro_display_group));

            if (show_compact_timer_actions) {
                this.compact_timer_actions = new Gtk.Switch ();
                this.compact_timer_actions.active = store.compact_timer_actions;
                this.compact_timer_actions.notify["active"].connect (() => {
                    this.store.compact_timer_actions = this.compact_timer_actions.active;
                    this.store.save ();
                    this.on_changed ();
                });
                root.append (switch_row ("Compact timer actions", this.compact_timer_actions));

                var compact_hint = new Gtk.Label ("Small windows only.\nRight-click the selected timer todo to enter or leave compact mode.");
                compact_hint.xalign = 0;
                compact_hint.wrap = true;
                compact_hint.add_css_class ("caption");
                root.append (compact_hint);
            }

            this.show_delete_button = new Gtk.Switch ();
            this.show_delete_button.active = store.show_delete_button;
            this.show_delete_button.notify["active"].connect (() => {
                this.store.show_delete_button = this.show_delete_button.active;
                this.store.save ();
                this.on_changed ();
            });
            root.append (switch_row ("Show delete button", this.show_delete_button));

            var todos_heading = new Gtk.Label ("Dependencies");
            todos_heading.xalign = 0;
            todos_heading.add_css_class ("title-3");
            root.append (todos_heading);

            this.dependencies_enabled = new Gtk.Switch ();
            this.dependencies_enabled.active = store.dependencies_enabled;
            this.dependencies_enabled.notify["active"].connect (() => {
                this.store.dependencies_enabled = this.dependencies_enabled.active;
                if (!this.dependencies_enabled.active) {
                    this.store.auto_depend_on_previous_todo = false;
                    this.store.project_dependency_graph = false;
                    if (this.auto_depend_on_previous_todo != null) {
                        this.auto_depend_on_previous_todo.active = false;
                        this.auto_depend_on_previous_todo.sensitive = false;
                    }
                    if (this.project_dependency_graph != null) {
                        this.project_dependency_graph.active = false;
                        this.project_dependency_graph.sensitive = false;
                    }
                }
                else if (this.auto_depend_on_previous_todo != null) {
                    this.auto_depend_on_previous_todo.sensitive = true;
                    if (this.project_dependency_graph != null) {
                        this.project_dependency_graph.sensitive = true;
                    }
                }
                this.store.save ();
                this.on_changed ();
            });
            root.append (switch_row ("Todo dependencies", this.dependencies_enabled));

            this.auto_depend_on_previous_todo = new Gtk.Switch ();
            this.auto_depend_on_previous_todo.active = store.auto_depend_on_previous_todo;
            this.auto_depend_on_previous_todo.sensitive = store.dependencies_enabled;
            this.auto_depend_on_previous_todo.notify["active"].connect (() => {
                this.store.auto_depend_on_previous_todo = this.auto_depend_on_previous_todo.active && this.store.dependencies_enabled;
                this.store.save ();
                this.on_changed ();
            });
            root.append (switch_row ("Depend on previous todo", this.auto_depend_on_previous_todo));

            this.project_dependency_graph = new Gtk.Switch ();
            this.project_dependency_graph.active = store.project_dependency_graph;
            this.project_dependency_graph.sensitive = store.dependencies_enabled;
            this.project_dependency_graph.notify["active"].connect (() => {
                this.store.project_dependency_graph = this.project_dependency_graph.active && this.store.dependencies_enabled;
                this.store.save ();
                this.on_changed ();
            });
            root.append (switch_row ("Project dependency graph", this.project_dependency_graph));

            var integrations_heading = new Gtk.Label ("Integrations");
            integrations_heading.xalign = 0;
            integrations_heading.add_css_class ("title-3");
            root.append (integrations_heading);

            this.calendar_events = new Gtk.Switch ();
            this.calendar_events.active = store.calendar_events_enabled;
            this.calendar_events.notify["active"].connect (() => {
                this.store.update_calendar_events_enabled (this.calendar_events.active);
                this.on_changed ();
            });
            root.append (switch_row ("Calendar events", this.calendar_events));

            var keyboard_heading = new Gtk.Label ("Keyboard");
            keyboard_heading.xalign = 0;
            keyboard_heading.add_css_class ("title-3");
            root.append (keyboard_heading);

            var shortcuts_button = new Gtk.Button.with_label ("Keyboard Shortcuts");
            shortcuts_button.halign = Gtk.Align.START;
            shortcuts_button.clicked.connect (() => this.on_shortcuts ());
            root.append (shortcuts_button);

            var close = new Gtk.Button.with_label ("Close");
            close.halign = Gtk.Align.END;
            close.clicked.connect (() => this.close ());
            root.append (close);
        }

        private Gtk.Widget framed (string title, Gtk.Widget child)
        {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            var label = new Gtk.Label (title);
            label.xalign = 0;
            label.add_css_class ("caption");
            box.append (label);
            box.append (child);
            return box;
        }

        private Gtk.Widget switch_row (string title, Gtk.Switch control)
        {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var label = new Gtk.Label (title);
            label.xalign = 0;
            label.hexpand = true;
            box.append (label);
            box.append (control);
            return box;
        }

        private Adw.Toggle display_toggle (string name, bool repeat_icons)
        {
            var toggle = new Adw.Toggle ();
            toggle.name = name;
            var child = pomodoro_display_widget (4, repeat_icons);
            child.margin_top = 8;
            child.margin_bottom = 8;
            child.margin_start = 10;
            child.margin_end = 10;
            toggle.child = child;
            toggle.tooltip = repeat_icons ? "Repeated tomato icons" : "Number and tomato icon";
            return toggle;
        }

    }
}
