namespace Tomodoro
{
    private const int DEFAULT_TODO_INDEX = -1;
    private const uint CONTEXT_BANNER_TIMEOUT_SECONDS = 5;
    private const int LONG_REST_INTERVAL = 4;
    private const uint GROUP_MODE_PRIORITY = 0;
    private const uint GROUP_MODE_DUE = 1;
    private const uint GROUP_MODE_PROJECT = 2;
    private const uint GROUP_MODE_RECURRING = 3;
    private delegate void ActionCallback ();
    private delegate void MenuCallback ();

    private enum TimerSession
    {
        POMODORO,
        SHORT_REST,
        LONG_REST
    }

    private class InlineActionGroup : GLib.Object
    {
        public Gtk.Revealer[] revealers = {};

        public InlineActionGroup (Gtk.Revealer[] revealers)
        {
            foreach (var revealer in revealers) {
                this.revealers += revealer;
            }
        }
    }

    public class MainWindow : Adw.ApplicationWindow
    {
        private Store store;
        private ContextConfig context;
        private Todo[] todos = {};
        private ContextConfig[] todo_contexts = {};

        private bool all_contexts = false;
        private bool show_completed = false;
        private bool show_recurring_instances = true;
        private bool show_nested_items = true;
        private string? selected_project = null;
        private string? selected_focus_project = null;
        private int selected_pomodoro_index = DEFAULT_TODO_INDEX;
        private uint timer_source = 0;
        private int remaining_seconds = 0;
        private TimerSession timer_session = TimerSession.POMODORO;
        private bool session_elapsed = false;
        private int completed_pomodoros_in_cycle = 0;

        private Adw.ViewStack view;
        private Adw.ViewSwitcher view_switcher;
        private Adw.Banner context_banner;
        private Gtk.MenuButton main_menu_button;
        private Gtk.Popover main_menu_popover;
        private Gtk.Box context_choices;
        private Gtk.Revealer context_choices_revealer;
        private Gtk.Button context_menu_button;
        private Gtk.Box project_choices;
        private Gtk.Revealer project_choices_revealer;
        private Gtk.Button project_menu_button;
        private Gtk.Revealer[] inline_action_revealers = {};
        private InlineActionGroup[] inline_action_groups = {};

        private Gtk.SearchEntry filter_entry;
        private Gtk.MenuButton group_button;
        private Gtk.Popover group_popover;
        private Gtk.Box group_choices;
        private Gtk.ToggleButton show_completed_toggle;
        private Gtk.ToggleButton nested_items_toggle;
        private Gtk.ToggleButton list_delete_toggle;
        private Gtk.Button recurring_new_button;
        private Gtk.Box todos_box;
        private Gtk.ScrolledWindow todo_scroller;
        private Gtk.Box list_search_row;
        private Gtk.Box list_buttons_row;
        private Gtk.Box list_spacer;
        private bool list_delete_mode = false;
        private bool updating_list_delete_mode = false;
        private bool updating_show_toggle = false;
        private uint group_mode = 0;
        private GLib.HashTable<string, string> collapsed_group_keys = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
        private int highlighted_todo_index = DEFAULT_TODO_INDEX;
        private Gtk.Widget? highlighted_todo_row = null;
        private bool highlighted_todo_clear_armed = true;
        private uint highlight_scroll_source = 0;

        private Gtk.MenuButton focus_button;
        private Gtk.Label focus_button_label;
        private Gtk.SearchEntry focus_search;
        private Gtk.Box focus_choices;
        private Gtk.Popover focus_popover;
        private Gtk.MenuButton pomodoro_current;
        private Gtk.Label pomodoro_current_label;
        private Gtk.SearchEntry pomodoro_search;
        private Gtk.Box pomodoro_choices;
        private Gtk.Popover pomodoro_popover;
        private Gtk.Button pomodoro_edit;
        private Gtk.Revealer timer_focus_revealer;
        private Gtk.Revealer pomodoro_edit_revealer;
        private Gtk.Box pomodoro_meta;
        private Gtk.Box timer_session_indicator;
        private Gtk.Label timer_label;
        private Gtk.Button start_pause_button;
        private Gtk.Button finish_button;
        private Gtk.Button add_minute_button;
        private Gtk.Box pomodoro_root;
        private Gtk.Box selector_controls;
        private Gtk.Box timer_balance_spacer;
        private Gtk.Box timer_focus_row;
        private Gtk.Box timer_todo_row;
        private bool responsive_layout_ready = false;
        private bool narrow_layout = false;
        private int todo_row_pomodoro_line_capacity = 8;
        private bool updating_text_case = false;
        private bool restoring_ui_state = false;
        private uint context_list_hide_source = 0;
        private uint project_list_hide_source = 0;
        private uint context_banner_hide_source = 0;
        public MainWindow (Adw.Application application)
        {
            Object (
                application: application,
                title: Config.APPLICATION_NAME,
                default_width: 900,
                default_height: 640,
                resizable: true
            );

            this.store = new Store ();
            this.restoring_ui_state = true;
            this.set_default_size (this.store.window_width, this.store.window_height);
            this.close_request.connect (() => {
                persist_ui_state ();
                return false;
            });
            this.context = this.store.selected_context ();
            this.selected_project = this.store.selected_project_root == "" ? null : this.store.selected_project_root;
            this.group_mode = this.store.selected_order_index ();
            build_ui ();
            install_actions ();
            reload ();
            restore_selected_view ();
            this.restoring_ui_state = false;
            GLib.Timeout.add (500, () => {
                send_due_notifications ();
                return GLib.Source.REMOVE;
            });
        }

        private void install_actions ()
        {
            add_simple_action ("new-todo", () => new_todo ());
            add_simple_action ("focus-filter", () => this.filter_entry.grab_focus ());
            add_simple_action ("tab-pomodoro", () => select_tab ("pomodoro"));
            add_simple_action ("tab-todos", () => select_tab ("todos"));
            add_simple_action ("show-shortcuts", () => show_shortcuts ());
        }

        private void add_simple_action (string name, owned ActionCallback callback)
        {
            var action = new GLib.SimpleAction (name, null);
            action.activate.connect (() => callback ());
            this.add_action (action);
        }

        private void install_highlight_clear_controllers ()
        {
            var click = new Gtk.GestureClick ();
            click.button = 1;
            click.released.connect (() => {
                if (!this.highlighted_todo_clear_armed) {
                    return;
                }
                GLib.Idle.add (() => {
                    clear_highlighted_todo_marker ();
                    return GLib.Source.REMOVE;
                });
            });
            ((Gtk.Widget) this).add_controller (click);

            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect (() => {
                if (this.highlighted_todo_clear_armed) {
                    clear_highlighted_todo_marker ();
                }
                return false;
            });
            ((Gtk.Widget) this).add_controller (keys);
        }

        private void build_ui ()
        {
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            this.content = content;
            var header = new Adw.HeaderBar ();
            header.centering_policy = Adw.CenteringPolicy.LOOSE;
            content.append (header);

            this.main_menu_button = new Gtk.MenuButton ();
            this.main_menu_button.icon_name = "open-menu-symbolic";
            this.main_menu_popover = new Gtk.Popover ();
            this.main_menu_popover.child = build_main_menu ();
            this.main_menu_popover.notify["visible"].connect (() => {
                if (this.main_menu_popover.visible) {
                    this.context_choices_revealer.reveal_child = false;
                    this.context_choices.visible = false;
                    this.project_choices_revealer.reveal_child = false;
                    this.project_choices.visible = false;
                    refresh_menu_lists ();
                    refresh_project_filter ();
                    sync_context_selector_state ();
                    sync_project_selector_state ();
                }
            });
            this.main_menu_button.popover = this.main_menu_popover;
            header.pack_end (this.main_menu_button);

            this.context_banner = new Adw.Banner ("All Contexts is an overview. Select one context to create, edit, or run a timer.");
            this.context_banner.revealed = false;
            content.append (this.context_banner);

            this.view = new Adw.ViewStack ();
            this.view_switcher = new Adw.ViewSwitcher ();
            this.view_switcher.stack = this.view;
            this.view_switcher.policy = Adw.ViewSwitcherPolicy.WIDE;
            header.title_widget = this.view_switcher;
            content.append (this.view);

            build_pomodoro_tab ();
            build_todos_tab ();
            GLib.Idle.add (() => {
                hide_view_switcher_icons ();
                return GLib.Source.REMOVE;
            });
            this.view.notify["visible-child-name"].connect (() => {
                hide_view_switcher_icons ();
                sync_tabs_for_request (true);
                persist_selected_view ();
            });
            install_highlight_clear_controllers ();
            sync_tabs ();
            GLib.Timeout.add (350, sync_responsive_layout);
        }

        private Gtk.Widget build_main_menu ()
        {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            box.margin_top = 8;
            box.margin_bottom = 8;
            box.margin_start = 8;
            box.margin_end = 8;
            box.width_request = 165;

            var new_button = new Gtk.Button.with_label ("New");
            new_button.tooltip_text = "Create todo (Ctrl+N)";
            new_button.clicked.connect (() => new_todo ());
            box.append (new_button);
            box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            var context_row = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var context_label = new Gtk.Label ("Context");
            context_label.xalign = 0;
            context_label.add_css_class ("caption");
            context_row.append (context_label);

            this.context_menu_button = new Gtk.Button.with_label ("Work");
            this.context_menu_button.add_css_class ("suggested-action");
            this.context_menu_button.clicked.connect (() => {
                cancel_context_list_hide ();
                this.project_choices_revealer.reveal_child = false;
                this.project_choices.visible = false;
                this.context_choices.visible = true;
                this.context_choices_revealer.reveal_child = !this.context_choices_revealer.reveal_child;
                refresh_menu_lists ();
                sync_context_selector_state ();
            });
            context_row.append (this.context_menu_button);

            this.context_choices = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            this.context_choices_revealer = new Gtk.Revealer ();
            this.context_choices_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
            this.context_choices_revealer.transition_duration = 180;
            this.context_choices_revealer.child = this.context_choices;
            context_row.append (this.context_choices_revealer);
            box.append (context_row);
            box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            var project_row = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var project_label = new Gtk.Label ("Project");
            project_label.xalign = 0;
            project_label.add_css_class ("caption");
            project_row.append (project_label);

            this.project_menu_button = new Gtk.Button.with_label ("All");
            this.project_menu_button.add_css_class ("suggested-action");
            this.project_menu_button.clicked.connect (() => {
                cancel_project_list_hide ();
                this.context_choices_revealer.reveal_child = false;
                this.context_choices.visible = false;
                this.project_choices.visible = true;
                this.project_choices_revealer.reveal_child = !this.project_choices_revealer.reveal_child;
                refresh_project_filter ();
                sync_project_selector_state ();
            });
            project_row.append (this.project_menu_button);

            this.project_choices = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            this.project_choices_revealer = new Gtk.Revealer ();
            this.project_choices_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
            this.project_choices_revealer.transition_duration = 180;
            this.project_choices_revealer.child = this.project_choices;
            project_row.append (this.project_choices_revealer);
            box.append (project_row);
            box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            var settings = new Gtk.Button.with_label ("Settings");
            settings.clicked.connect (() => show_settings ());
            box.append (settings);

            var about = new Gtk.Button.with_label ("About");
            about.clicked.connect (() => show_about ());
            box.append (about);

            return box;
        }

        private void build_pomodoro_tab ()
        {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 16);
            this.pomodoro_root = box;
            set_pomodoro_spacing (false);

            this.selector_controls = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            this.timer_focus_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            this.timer_todo_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            this.selector_controls.append (this.timer_focus_row);
            this.selector_controls.append (this.timer_todo_row);

            this.focus_button = new Gtk.MenuButton ();
            this.focus_button_label = new Gtk.Label ("All");
            this.focus_button_label.ellipsize = Pango.EllipsizeMode.END;
            this.focus_button_label.single_line_mode = true;
            this.focus_button_label.width_chars = 1;
            this.focus_button_label.max_width_chars = 20;
            this.focus_button_label.hexpand = true;
            this.focus_button.child = this.focus_button_label;
            this.focus_button.width_request = 1;
            this.focus_popover = new Gtk.Popover ();
            var focus_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            focus_content.margin_top = 10;
            focus_content.margin_bottom = 10;
            focus_content.margin_start = 10;
            focus_content.margin_end = 10;
            focus_content.width_request = 260;
            this.focus_search = new Gtk.SearchEntry ();
            this.focus_search.placeholder_text = "Filter";
            this.focus_search.search_changed.connect (refresh_timer_focuses);
            this.focus_choices = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var focus_scroller = new Gtk.ScrolledWindow ();
            focus_scroller.child = this.focus_choices;
            focus_scroller.min_content_height = 220;
            focus_scroller.max_content_height = 460;
            focus_content.append (this.focus_search);
            focus_content.append (focus_scroller);
            this.focus_popover.child = focus_content;
            this.focus_popover.notify["visible"].connect (() => {
                if (this.focus_popover.visible) {
                    this.focus_search.text = "";
                    refresh_timer_focuses ();
                    this.focus_search.grab_focus ();
                }
            });
            this.focus_button.popover = this.focus_popover;
            this.timer_focus_revealer = timer_action_revealer (this.focus_button, Gtk.RevealerTransitionType.SLIDE_DOWN);
            this.timer_todo_row.append (this.timer_focus_revealer);

            this.pomodoro_current = new Gtk.MenuButton ();
            this.pomodoro_current_label = new Gtk.Label ("Choose Todo");
            this.pomodoro_current_label.ellipsize = Pango.EllipsizeMode.END;
            this.pomodoro_current_label.width_chars = 1;
            this.pomodoro_current_label.single_line_mode = true;
            this.pomodoro_current_label.max_width_chars = TODO_SUMMARY_MAX_CHARS;
            this.pomodoro_current_label.xalign = 0.5f;
            this.pomodoro_current_label.hexpand = true;
            this.pomodoro_current.child = this.pomodoro_current_label;
            this.pomodoro_current.hexpand = true;
            this.pomodoro_current.width_request = 1;
            this.pomodoro_current.tooltip_text = "Click to search todos";

            var current_secondary_click = new Gtk.GestureClick ();
            current_secondary_click.button = 3;
            current_secondary_click.pressed.connect (() => toggle_timer_action_controls ());
            this.pomodoro_current.add_controller (current_secondary_click);
            this.pomodoro_popover = new Gtk.Popover ();
            var selector_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            selector_content.margin_top = 10;
            selector_content.margin_bottom = 10;
            selector_content.margin_start = 10;
            selector_content.margin_end = 10;
            selector_content.width_request = 360;
            this.pomodoro_search = new Gtk.SearchEntry ();
            this.pomodoro_search.placeholder_text = "Type to filter todos";
            this.pomodoro_search.search_changed.connect (refresh_pomodoro_todos);
            this.pomodoro_search.activate.connect (() => create_todo_from_pomodoro_filter_if_empty ());
            this.pomodoro_choices = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            selector_content.append (this.pomodoro_search);
            selector_content.append (this.pomodoro_choices);
            this.pomodoro_popover.child = selector_content;
            this.pomodoro_popover.notify["visible"].connect (() => {
                if (this.pomodoro_popover.visible) {
                    if (open_selected_timer_todo_in_list ()) {
                        return;
                    }
                    this.pomodoro_search.text = "";
                    refresh_pomodoro_todos ();
                    this.pomodoro_search.grab_focus ();
                }
            });
            this.pomodoro_current.popover = this.pomodoro_popover;
            this.timer_todo_row.append (this.pomodoro_current);

            this.pomodoro_edit = new Gtk.Button.from_icon_name ("document-edit-symbolic");
            this.pomodoro_edit.tooltip_text = "Edit selected todo";
            this.pomodoro_edit.clicked.connect (() => edit_selected_pomodoro_todo ());
            this.pomodoro_edit_revealer = timer_action_revealer (this.pomodoro_edit, Gtk.RevealerTransitionType.SLIDE_LEFT);
            this.timer_todo_row.append (this.pomodoro_edit_revealer);
            box.append (this.selector_controls);

            this.pomodoro_meta = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            this.pomodoro_meta.halign = Gtk.Align.START;
            this.pomodoro_meta.valign = Gtk.Align.CENTER;
            this.pomodoro_meta.add_css_class ("caption");
            this.pomodoro_meta.visible = false;
            box.append (this.pomodoro_meta);

            var timer_center_group = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            timer_center_group.add_css_class ("timer-center-group");
            timer_center_group.halign = Gtk.Align.CENTER;
            timer_center_group.valign = Gtk.Align.CENTER;
            timer_center_group.hexpand = true;
            timer_center_group.vexpand = true;

            this.timer_session_indicator = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            this.timer_session_indicator.add_css_class ("timer-session-label");
            this.timer_session_indicator.halign = Gtk.Align.CENTER;
            this.timer_session_indicator.valign = Gtk.Align.CENTER;
            timer_center_group.append (this.timer_session_indicator);
            sync_timer_session_label ();

            this.timer_label = new Gtk.Label ("25:00");
            this.timer_label.add_css_class ("timer-label");
            this.timer_label.margin_bottom = 6;
            timer_center_group.append (this.timer_label);

            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            buttons.halign = Gtk.Align.CENTER;
            this.start_pause_button = new Gtk.Button.from_icon_name ("media-playback-start-symbolic");
            this.start_pause_button.add_css_class ("timer-control-button");
            this.start_pause_button.tooltip_text = "Start";
            this.start_pause_button.clicked.connect (toggle_timer);
            this.add_minute_button = new Gtk.Button ();
            this.add_minute_button.add_css_class ("timer-control-button");
            this.add_minute_button.child = new Gtk.Image.from_icon_name ("list-add-symbolic");
            this.add_minute_button.tooltip_text = "Add one minute to the current session";
            this.add_minute_button.clicked.connect (add_one_minute);
            this.finish_button = new Gtk.Button ();
            var finish_content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            finish_content.append (new Gtk.Image.from_icon_name ("object-select-symbolic"));
            finish_content.append (new Gtk.Label ("Done"));
            this.finish_button.child = finish_content;
            this.finish_button.tooltip_text = "Finish current session";
            this.finish_button.add_css_class ("timer-done-button");
            this.finish_button.clicked.connect (finish_pomodoro);
            buttons.append (this.start_pause_button);
            buttons.append (this.add_minute_button);
            buttons.append (this.finish_button);
            timer_center_group.append (buttons);
            box.append (timer_center_group);

            this.timer_balance_spacer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            this.timer_balance_spacer.add_css_class ("timer-balance-spacer");
            box.append (this.timer_balance_spacer);
            set_pomodoro_spacing (false);

            var page = this.view.add_titled (box, "pomodoro", "Timer");
            page.icon_name = "";
        }

        private void set_pomodoro_spacing (bool compact)
        {
            if (this.pomodoro_root == null) {
                return;
            }

            var margin = compact ? 12 : 24;
            this.pomodoro_root.margin_top = margin;
            this.pomodoro_root.margin_bottom = margin;
            this.pomodoro_root.margin_start = margin;
            this.pomodoro_root.margin_end = margin;
            this.pomodoro_root.spacing = compact ? 8 : 16;

            if (this.selector_controls != null) {
                this.selector_controls.spacing = compact ? 6 : 8;
            }

            if (this.timer_label != null) {
                this.timer_label.margin_top = compact ? 8 : 28;
                this.timer_label.margin_bottom = compact ? 8 : 18;
            }

            if (this.timer_balance_spacer != null) {
                this.timer_balance_spacer.height_request = compact ? 96 : 84;
            }
        }

        private void build_todos_tab ()
        {
            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            root.margin_top = 12;
            root.margin_bottom = 12;
            root.margin_start = 12;
            root.margin_end = 12;

            var controls = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            this.list_search_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            this.list_buttons_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            controls.append (this.list_search_row);
            controls.append (this.list_buttons_row);

            this.filter_entry = new Gtk.SearchEntry ();
            this.filter_entry.placeholder_text = "Filter todos";
            this.filter_entry.width_request = -1;
            this.filter_entry.hexpand = true;
            this.filter_entry.search_changed.connect (refresh_todos);
            this.filter_entry.activate.connect (activate_single_filtered_todo);
            this.list_search_row.append (this.filter_entry);

            this.group_button = new Gtk.MenuButton ();
            this.group_popover = new Gtk.Popover ();
            var group_content = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            group_content.margin_top = 8;
            group_content.margin_bottom = 8;
            group_content.margin_start = 8;
            group_content.margin_end = 8;
            group_content.width_request = 170;
            this.group_choices = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            group_content.append (this.group_choices);
            this.group_popover.child = group_content;
            this.group_popover.notify["visible"].connect (() => {
                if (this.group_popover.visible) {
                    refresh_group_choices ();
                }
            });
            this.group_button.popover = this.group_popover;
            sync_group_button ();
            this.list_search_row.append (this.group_button);

            this.recurring_new_button = new Gtk.Button.from_icon_name ("list-add-symbolic");
            this.recurring_new_button.tooltip_text = "New recurring";
            this.recurring_new_button.clicked.connect (() => new_recurring_template ());
            this.recurring_new_button.visible = false;
            this.list_search_row.append (this.recurring_new_button);

            this.show_completed_toggle = new Gtk.ToggleButton ();
            this.show_completed_toggle.child = new Gtk.Image.from_icon_name ("object-select-symbolic");
            this.show_completed_toggle.tooltip_text = "Show finished todos";
            this.show_completed_toggle.toggled.connect (show_completed_changed);
            this.nested_items_toggle = new Gtk.ToggleButton ();
            this.nested_items_toggle.child = new Gtk.Image.from_icon_name ("view-list-symbolic");
            this.nested_items_toggle.tooltip_text = "Hide nested todos";
            this.nested_items_toggle.visible = false;
            this.nested_items_toggle.toggled.connect (nested_items_changed);
            this.list_delete_toggle = new Gtk.ToggleButton ();
            this.list_delete_toggle.child = new Gtk.Image.from_icon_name ("user-trash-symbolic");
            this.list_delete_toggle.tooltip_text = "Delete todos";
            this.list_delete_toggle.toggled.connect (list_delete_mode_changed);
            this.list_spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            this.list_spacer.hexpand = true;
            this.list_search_row.append (this.list_spacer);
            this.list_search_row.append (this.nested_items_toggle);
            this.list_search_row.append (this.show_completed_toggle);
            this.list_search_row.append (this.list_delete_toggle);

            root.append (controls);

            this.todos_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            this.todo_scroller = new Gtk.ScrolledWindow ();
            this.todo_scroller.vexpand = true;
            this.todo_scroller.child = this.todos_box;
            root.append (this.todo_scroller);

            var page = this.view.add_titled (root, "todos", "List");
            page.icon_name = "";
        }

        private void hide_view_switcher_icons ()
        {
            if (this.view_switcher == null) {
                return;
            }

            hide_widget_images (this.view_switcher);
        }

        private void hide_widget_images (Gtk.Widget widget)
        {
            var image = widget as Gtk.Image;
            if (image != null) {
                image.visible = false;
                image.width_request = 0;
                image.height_request = 0;
            }

            var child = widget.get_first_child ();
            while (child != null) {
                hide_widget_images (child);
                child = child.get_next_sibling ();
            }
        }

        private void reload ()
        {
            if (!this.all_contexts) {
                this.context = this.store.selected_context ();
            }

            hide_context_hint ();
            this.todos = load_visible_todos ();
            set_timer_from_profile ();
            restore_selected_todo ();
            refresh_all ();
        }

        private Todo[] load_visible_todos ()
        {
            Todo[] visible = {};
            this.todo_contexts = {};

            if (!this.all_contexts) {
                visible = this.store.load_todos (this.context);
                foreach (var todo in visible) {
                    this.todo_contexts += this.context;
                }
                return visible;
            }

            foreach (var item in this.store.contexts ()) {
                foreach (var todo in this.store.load_todos (item)) {
                    visible += todo;
                    this.todo_contexts += item;
                }
            }
            return visible;
        }

        private void refresh_all ()
        {
            refresh_menu_lists ();
            refresh_project_filter ();
            if (!this.all_contexts) {
                refresh_timer_focuses ();
                ensure_selected_timer_todo_for_current_filter ();
                refresh_pomodoro_todos ();
            }
            else {
                set_selected_pomodoro_index (DEFAULT_TODO_INDEX);
            }
            sync_list_delete_button ();
            sync_show_toggle ();
            refresh_todos ();
            sync_context_sensitivity ();
            sync_tabs ();
            sync_timer_action_controls ();
        }

        private void refresh_menu_lists ()
        {
            if (this.context_menu_button == null) {
                return;
            }

            this.context_menu_button.label = this.all_contexts ? "All" : this.context.name;
            clear_box (this.context_choices);

            if (!this.all_contexts) {
                this.context_choices.append (menu_choice ("All", false, () => select_context (null)));
            }

            var contexts = this.store.contexts ();
            foreach (var item in contexts) {
                if (!this.all_contexts && item.slug == this.context.slug) {
                    continue;
                }
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                row.append (menu_choice (item.name, false, () => select_context (item.slug)));
                if (contexts.length > 1) {
                    var delete_button = new Gtk.Button.from_icon_name ("user-trash-symbolic");
                    delete_button.add_css_class ("destructive-action");
                    delete_button.tooltip_text = "Delete context";
                    delete_button.clicked.connect (() => confirm_delete_context (item));
                    row.append (animated_action (row, delete_button));
                }
                this.context_choices.append (row);
            }

            var creator = new Gtk.Entry ();
            creator.placeholder_text = "+New";
            creator.tooltip_text = "Type a context name and press Enter";
            creator.changed.connect (() => {
                sanitize_creator_entry (creator, CONTEXT_NAME_MAX_LENGTH);
                sync_context_creator_state (creator);
            });
            creator.activate.connect (() => {
                if (!valid_context_name_text (creator.text) || context_name_exists_ignore_case (creator.text)) {
                    mark_creator_error (creator, !valid_context_name_text (creator.text) ? "Type a valid context name" : "Context already exists");
                    return;
                }
                this.store.add_context (creator.text.strip (), "folder-symbolic");
                creator.text = "";
                reload ();
            });
            this.context_choices.append (creator);
        }

        private void sync_context_selector_state ()
        {
            if (this.context_menu_button == null) {
                return;
            }

            this.context_menu_button.tooltip_text = this.context_choices_revealer.reveal_child ? "Hide contexts" : "Show contexts";
            this.context_menu_button.add_css_class ("suggested-action");
        }

        private Gtk.Button menu_choice (string label, bool active, owned MenuCallback callback)
        {
            var button = new Gtk.Button ();
            var label_widget = new Gtk.Label ("");
            label_widget.xalign = 0;
            if (active) {
                label_widget.use_markup = true;
                label_widget.label = "<b>%s</b>".printf (GLib.Markup.escape_text (label));
            }
            else {
                label_widget.label = label;
            }
            button.child = label_widget;
            button.hexpand = true;
            button.clicked.connect (() => callback ());
            return button;
        }

        private void sync_context_creator_state (Gtk.Entry creator)
        {
            if (creator.text.strip () != "" && !valid_context_name_text (creator.text)) {
                mark_creator_error (creator, "Type a valid context name");
            }
            else if (context_name_exists_ignore_case (creator.text)) {
                mark_creator_error (creator, "Context already exists");
            }
            else {
                clear_creator_error (creator, "Type a context name and press Enter");
            }
        }

        private void sync_project_creator_state (Gtk.Entry creator)
        {
            var project = project_root (normalize_project (creator.text, ""));
            if (project_root_exists_ignore_case (project)) {
                mark_creator_error (creator, "Project already exists");
            }
            else {
                clear_creator_error (creator, "Type a project name and press Enter");
            }
        }

        private void mark_creator_error (Gtk.Entry creator, string tooltip)
        {
            creator.add_css_class ("error");
            creator.tooltip_text = tooltip;
        }

        private void clear_creator_error (Gtk.Entry creator, string tooltip)
        {
            creator.remove_css_class ("error");
            creator.tooltip_text = tooltip;
        }

        private bool context_name_exists_ignore_case (string name)
        {
            var target = duplicate_compare_key (name);
            if (target == "") {
                return false;
            }
            foreach (var item in this.store.contexts ()) {
                if (duplicate_compare_key (item.name) == target) {
                    return true;
                }
            }
            return false;
        }

        private bool project_root_exists_ignore_case (string project)
        {
            var target = duplicate_compare_key (project);
            if (target == "") {
                return false;
            }
            foreach (var item in known_projects ()) {
                if (duplicate_compare_key (project_root (item)) == target) {
                    return true;
                }
            }
            return false;
        }

        private string duplicate_compare_key (string value)
        {
            return compact_text (value).down ();
        }

        private void refresh_project_filter ()
        {
            if (this.project_menu_button == null) {
                return;
            }

            var selected = selected_project_filter ();
            this.project_menu_button.label = selected == null ? "All" : format_project_label (selected);
            this.project_menu_button.sensitive = !this.all_contexts;
            if (this.all_contexts) {
                this.project_menu_button.remove_css_class ("suggested-action");
            }
            else {
                this.project_menu_button.add_css_class ("suggested-action");
            }
            clear_box (this.project_choices);

            if (this.all_contexts) {
                this.project_choices_revealer.reveal_child = false;
                this.project_choices.visible = false;
                sync_project_selector_state ();
                return;
            }

            if (selected != null) {
                this.project_choices.append (menu_choice ("All", false, () => select_project_filter (null)));
            }
            foreach (var project in list_project_roots ()) {
                if (selected == project) {
                    continue;
                }
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                row.append (menu_choice (format_project_label (project), false, () => select_project_filter (project)));
                if (can_delete_project ()) {
                    var delete_button = new Gtk.Button.from_icon_name ("user-trash-symbolic");
                    delete_button.add_css_class ("destructive-action");
                    delete_button.tooltip_text = "Delete project";
                    delete_button.clicked.connect (() => confirm_delete_project (project));
                    row.append (animated_action (row, delete_button));
                }
                this.project_choices.append (row);
            }

            var creator = new Gtk.Entry ();
            creator.placeholder_text = "+New";
            creator.tooltip_text = "Type a project name and press Enter";
            creator.changed.connect (() => {
                sanitize_creator_entry (creator, PROJECT_PART_MAX_LENGTH);
                sync_project_creator_state (creator);
            });
            creator.activate.connect (() => {
                var project = project_root (normalize_project (creator.text, ""));
                if (!valid_project_part_text (project) || project_root_exists_ignore_case (project)) {
                    mark_creator_error (creator, !valid_project_part_text (project) ? "Type a valid project name" : "Project already exists");
                    return;
                }
                this.context.set_project_icon (project, "folder-symbolic");
                this.store.save ();
                creator.text = "";
                refresh_all ();
            });
            this.project_choices.append (creator);

            sync_project_selector_state ();
        }

        private void sync_project_selector_state ()
        {
            if (this.project_menu_button == null) {
                return;
            }

            this.project_menu_button.tooltip_text = this.all_contexts
                ? "Select a specific context to filter projects"
                : (this.project_choices_revealer.reveal_child ? "Hide projects" : "Show projects");
        }

        private void collapse_context_choices ()
        {
            if (this.context_choices_revealer == null) {
                return;
            }

            cancel_context_list_hide ();
            this.context_choices.visible = true;
            this.context_choices_revealer.reveal_child = false;
            this.context_list_hide_source = GLib.Timeout.add (190, () => {
                this.context_choices.visible = false;
                this.context_list_hide_source = 0;
                sync_context_selector_state ();
                return GLib.Source.REMOVE;
            });
            sync_context_selector_state ();
        }

        private void collapse_project_choices ()
        {
            if (this.project_choices_revealer == null) {
                return;
            }

            cancel_project_list_hide ();
            this.project_choices.visible = true;
            this.project_choices_revealer.reveal_child = false;
            this.project_list_hide_source = GLib.Timeout.add (190, () => {
                this.project_choices.visible = false;
                this.project_list_hide_source = 0;
                sync_project_selector_state ();
                return GLib.Source.REMOVE;
            });
            sync_project_selector_state ();
        }

        private void cancel_context_list_hide ()
        {
            if (this.context_list_hide_source != 0) {
                GLib.Source.remove (this.context_list_hide_source);
                this.context_list_hide_source = 0;
            }
        }

        private void cancel_project_list_hide ()
        {
            if (this.project_list_hide_source != 0) {
                GLib.Source.remove (this.project_list_hide_source);
                this.project_list_hide_source = 0;
            }
        }

        private void refresh_timer_focuses ()
        {
            if (this.focus_choices == null) {
                return;
            }

            var projects = timer_focus_projects ();
            if (!string_array_contains (projects, this.selected_focus_project)) {
                this.selected_focus_project = default_timer_focus_project (projects);
            }
            set_focus_button_label (this.selected_focus_project == null ? "No Project" : timer_focus_label (this.selected_focus_project));
            clear_box (this.focus_choices);

            var filter = this.focus_search.text.down ().strip ();
            if (projects.length == 0) {
                var empty = new Gtk.Label ("No projects");
                empty.xalign = 0;
                empty.add_css_class ("caption");
                this.focus_choices.append (empty);
                return;
            }

            if (selected_timer_project () == null) {
                string[] roots = {};
                foreach (var project in projects) {
                    roots = append_unique_string (roots, project_root (project));
                }

                foreach (var root in roots) {
                    var added_heading = false;
                    foreach (var project in projects) {
                        if (project_root (project) != root || !focus_filter_matches (project, filter)) {
                            continue;
                        }
                        if (!added_heading) {
                            var heading = new Gtk.Label (root);
                            heading.xalign = 0;
                            heading.add_css_class ("caption");
                            this.focus_choices.append (heading);
                            added_heading = true;
                        }
                        this.focus_choices.append (focus_choice_button (project));
                    }
                }
                return;
            }

            foreach (var project in projects) {
                if (!focus_filter_matches (project, filter)) {
                    continue;
                }
                this.focus_choices.append (focus_choice_button (project));
            }
        }

        private void refresh_pomodoro_todos ()
        {
            if (this.pomodoro_choices == null) {
                return;
            }

            clear_box (this.pomodoro_choices);
            var raw_filter = this.pomodoro_search.text.strip ();
            var filter = raw_filter.down ();
            var matches = 0;

            for (int index = 0; index < this.todos.length; index++) {
                var todo = this.todos[index];
                if (index == this.selected_pomodoro_index || todo.completed || !todo_matches_timer_filter (todo)) {
                    continue;
                }
                var summary = todo_summary (todo);
                if (filter != "" && !timer_todo_filter_text (todo).contains (filter)) {
                    continue;
                }
                matches++;
                var todo_index = index;
                var button = new Gtk.Button.with_label (summary);
                button.hexpand = true;
                button.clicked.connect (() => select_pomodoro_todo (todo_index));
                this.pomodoro_choices.append (button);
            }

            if (matches == 0) {
                if (raw_filter == "") {
                    var empty = new Gtk.Label ("No other todos");
                    empty.xalign = 0;
                    empty.add_css_class ("caption");
                    this.pomodoro_choices.append (empty);
                }
                else {
                    var create = new Gtk.Button.with_label ("Create: %s".printf (normalize_body_text (raw_filter)));
                    create.hexpand = true;
                    create.add_css_class ("suggested-action");
                    create.clicked.connect (() => create_todo_from_pomodoro_filter ());
                    this.pomodoro_choices.append (create);
                }
            }

            if (!valid_selected_pomodoro ()) {
                select_best_timer_todo_for_current_filter ();
            }

            if (!valid_selected_pomodoro ()) {
                set_pomodoro_current_label ("No Todo");
            }
            else {
                set_pomodoro_current_label (timer_todo_body (this.todos[this.selected_pomodoro_index]));
            }
            sync_pomodoro_meta ();
            sync_timer_availability ();
        }

        private void refresh_todos ()
        {
            clear_box (this.todos_box);
            this.highlighted_todo_row = null;

            var indexes = sorted_todo_indexes (filtered_todo_indexes ());
            if (indexes.length == 0) {
                var status = new Adw.StatusPage ();
                status.title = this.group_mode == GROUP_MODE_RECURRING ? "No Recurring Todos" : "No Todos";
                status.description = this.all_contexts
                    ? "No todos in any context."
                    : (this.group_mode == GROUP_MODE_RECURRING ? "Click here to create a recurring template." : "Click here to create a todo.");
                if (!this.all_contexts) {
                    add_pointer_cursor (status);
                    var click = new Gtk.GestureClick ();
                    click.button = 1;
                    click.released.connect (() => {
                        if (this.group_mode == GROUP_MODE_RECURRING) {
                            new_recurring_template ();
                        }
                        else {
                            new_todo ();
                        }
                    });
                    status.add_controller (click);
                }
                this.todos_box.append (status);
                return;
            }

            if (this.group_mode == GROUP_MODE_RECURRING) {
                refresh_recurring_todos (indexes);
                return;
            }

            if (dependency_graph_enabled ()) {
                refresh_dependency_graph (indexes);
                return;
            }

            string[] group_titles = {};
            foreach (var index in indexes) {
                group_titles = append_unique_string (group_titles, group_key (this.todos[index]));
            }

            foreach (var title in group_titles) {
                Todo[] group_todos = {};
                int[] active_group_indexes = {};
                int[] completed_group_indexes = {};
                foreach (var index in indexes) {
                    if (group_key (this.todos[index]) == title) {
                        group_todos += this.todos[index];
                        if (this.todos[index].completed) {
                            completed_group_indexes += index;
                        }
                        else {
                            active_group_indexes += index;
                        }
                    }
                }

                var group_indexes = sorted_group_row_indexes (active_group_indexes);
                foreach (var index in sorted_group_row_indexes (completed_group_indexes)) {
                    group_indexes += index;
                }

                var expander = new Adw.ExpanderRow ();
                expander.title = title;
                bind_group_expansion (expander, title);
                expander.add_css_class ("todo-card");
                if (this.group_mode == GROUP_MODE_DUE) {
                    expander.add_prefix (colored_dot (due_color (earliest_due (group_todos))));
                }
                else {
                    expander.add_prefix (colored_dot (priority_color (highest_priority (group_todos))));
                }

                for (int row_index = 0; row_index < group_indexes.length; row_index++) {
                    var index = group_indexes[row_index];
                    var row = create_todo_row (index);
                    expander.add_row (row);
                }

                this.todos_box.append (expander);
            }
        }

        private void refresh_recurring_todos (int[] indexes)
        {
            string[] group_titles = {};
            foreach (var index in indexes) {
                group_titles = append_unique_string (group_titles, group_key (this.todos[index]));
            }

            foreach (var title in group_titles) {
                int[] group_indexes = {};
                foreach (var index in indexes) {
                    if (group_key (this.todos[index]) == title) {
                        group_indexes += index;
                    }
                }

                var expander = new Adw.ExpanderRow ();
                expander.title = title;
                bind_group_expansion (expander, title);
                expander.add_css_class ("todo-card");

                foreach (var index in sorted_group_row_indexes (group_indexes)) {
                    var child_indexes = recurring_instance_indexes (this.todos[index].id);
                    expander.add_row (create_todo_row (
                        index,
                        false,
                        0,
                        false,
                        this.show_recurring_instances ? 0 : child_indexes.length
                    ));
                    if (this.show_recurring_instances) {
                        foreach (var child_index in child_indexes) {
                            expander.add_row (create_todo_row (child_index, true, 1));
                        }
                    }
                }

                this.todos_box.append (expander);
            }
        }

        private int[] recurring_instance_indexes (string template_id)
        {
            int[] result = {};
            if (template_id == "") {
                return result;
            }
            for (int index = 0; index < this.todos.length; index++) {
                var todo = this.todos[index];
                if (!todo.recurring_instance || todo.recurrence_parent_id != template_id) {
                    continue;
                }
                if (todo.completed) {
                    continue;
                }
                result += index;
            }

            for (int left = 0; left < result.length; left++) {
                for (int right = left + 1; right < result.length; right++) {
                    if (compare_due_todo_indexes (result[left], result[right]) > 0) {
                        var tmp = result[left];
                        result[left] = result[right];
                        result[right] = tmp;
                    }
                }
            }
            return result;
        }

        private Adw.ActionRow create_todo_row (
            int index,
            bool indented = false,
            int indent_depth = 0,
            bool dependency_graph = false,
            int hidden_child_count = 0
        )
        {
            var todo = this.todos[index];
            var row = new Adw.ActionRow ();
            row.title = recurring_instance_row_title (todo);
            row.title_lines = 1;
            var subtitle = todo.recurring
                ? recurring_template_subtitle (todo)
                : (dependency_graph ? dependency_graph_row_subtitle (index, todo, indent_depth) : row_subtitle (index, todo, indented));
            if (hidden_child_count > 0) {
                var note = child_count_note (hidden_child_count);
                subtitle = subtitle == "" ? note : "%s\n%s".printf (subtitle, note);
            }
            row.subtitle = subtitle;
            row.subtitle_lines = hidden_child_count > 0 ? 2 : (dependency_graph ? 1 : row_subtitle_lines ());
            row.activatable = !todo.completed || todo.recurring;
            add_pointer_cursor (row);
            row.activated.connect (() => row_activated (index));
            if (todo.completed) {
                row.add_css_class ("dim-label");
            }
            if (indented || dependency_graph) {
                row.add_css_class ("dependency-graph-row");
            }
            if (index == this.highlighted_todo_index) {
                row.add_css_class ("todo-jump-highlight");
                this.highlighted_todo_row = row;
            }
            if (indented || dependency_graph) {
                row.add_prefix (indented_priority_prefix (todo, indent_depth));
            }
            else {
                row.add_prefix (priority_label (
                    todo.priority,
                    priority_letters_colored (),
                    show_priority_letter ()
                ));
            }

            row.add_suffix (todo_row_suffix (row, index, todo));
            return row;
        }

        private Gtk.Widget todo_row_suffix (Adw.ActionRow row, int index, Todo todo)
        {
            var suffix = new Gtk.Box (this.narrow_layout ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL, 4);
            suffix.add_css_class ("todo-row-suffix");
            suffix.valign = Gtk.Align.CENTER;
            suffix.halign = Gtk.Align.END;

            var pomodoros = pomodoro_display_widget (
                todo.pm,
                this.store.repeat_pomodoro_icons,
                todo_row_pomodoro_icon_limit (),
                todo_row_pomodoro_icons_per_line ()
            );
            pomodoros.add_css_class ("todo-row-pomodoros");
            pomodoros.halign = Gtk.Align.END;
            suffix.append (pomodoros);

            var actions_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            actions_box.add_css_class ("todo-row-actions");
            actions_box.halign = this.narrow_layout && !this.list_delete_mode ? Gtk.Align.START : Gtk.Align.END;

            if (this.list_delete_mode) {
                actions_box.halign = Gtk.Align.END;
                var delete_button = new Gtk.Button.from_icon_name ("user-trash-symbolic");
                delete_button.tooltip_text = "Delete";
                delete_button.add_css_class ("destructive-action");
                style_inline_action_button (delete_button);
                delete_button.clicked.connect (() => delete_todo_at (index));
                actions_box.append (delete_button);
                suffix.append (actions_box);
            }
            else {
                var edit = new Gtk.Button.from_icon_name ("document-edit-symbolic");
                edit.tooltip_text = "Edit";
                edit.clicked.connect (() => edit_todo (index));
                var edit_revealer = action_revealer_for_row (edit);
                actions_box.append (edit_revealer);

                Gtk.Revealer[] row_actions = {edit_revealer};
                if (!this.all_contexts) {
                    var duplicate = new Gtk.Button.from_icon_name ("edit-copy-symbolic");
                    duplicate.tooltip_text = "Duplicate";
                    duplicate.clicked.connect (() => duplicate_todo (index));
                    var duplicate_revealer = action_revealer_for_row (duplicate);
                    actions_box.append (duplicate_revealer);
                    row_actions += duplicate_revealer;
                }

                suffix.append (actions_box);

                if (!todo.recurring) {
                    var complete = new Gtk.Button.from_icon_name (todo.completed ? "edit-undo-symbolic" : "object-select-symbolic");
                    complete.tooltip_text = todo.completed ? "Mark active" : "Complete";
                    complete.clicked.connect (() => toggle_todo_completed (index));
                    var complete_revealer = action_revealer_for_row (complete);
                    actions_box.append (complete_revealer);
                    row_actions += complete_revealer;
                }
                add_right_click_toggle (row, row_actions);
            }
            return suffix;
        }

        private void refresh_dependency_graph (int[] indexes)
        {
            string[] group_titles = {};
            foreach (var index in indexes) {
                group_titles = append_unique_string (group_titles, dependency_graph_group_key (this.todos[index]));
            }
            group_titles = sorted_dependency_graph_group_titles (group_titles, indexes);

            foreach (var title in group_titles) {
                Todo[] group_todos = {};
                int[] active_group_indexes = {};
                int[] completed_group_indexes = {};
                foreach (var index in indexes) {
                    if (dependency_graph_group_key (this.todos[index]) != title) {
                        continue;
                    }
                    group_todos += this.todos[index];
                    if (this.todos[index].completed) {
                        completed_group_indexes += index;
                    }
                    else {
                        active_group_indexes += index;
                    }
                }

                int[] group_indexes = {};
                foreach (var index in dependency_graph_order (active_group_indexes)) {
                    group_indexes += index;
                }
                foreach (var index in dependency_graph_order (completed_group_indexes)) {
                    group_indexes += index;
                }

                var expander = new Adw.ExpanderRow ();
                expander.title = title;
                bind_group_expansion (expander, title);
                expander.add_css_class ("todo-card");
                expander.add_css_class ("dependency-graph-group");
                expander.add_prefix (dependency_graph_group_prefix (group_todos));

                for (int row_index = 0; row_index < group_indexes.length; row_index++) {
                    var index = group_indexes[row_index];
                    var depth = dependency_graph_depth (index, group_indexes);
                    if (!this.show_nested_items && depth > 0) {
                        continue;
                    }
                    expander.add_row (create_todo_row (
                        index,
                        true,
                        depth,
                        true,
                        this.show_nested_items ? 0 : dependency_graph_descendant_count (index, group_indexes)
                    ));
                }

                this.todos_box.append (expander);
            }
        }

        private string dependency_graph_group_key (Todo todo)
        {
            return group_key (todo);
        }

        private Gtk.Widget dependency_graph_group_prefix (Todo[] group_todos)
        {
            if (this.group_mode == GROUP_MODE_DUE) {
                return colored_dot (due_color (earliest_due (group_todos)));
            }
            return colored_dot (priority_color (highest_priority (group_todos)));
        }

        private bool dependency_graph_enabled ()
        {
            return this.store.dependencies_enabled && this.store.project_dependency_graph;
        }

        private string[] sorted_dependency_graph_group_titles (string[] titles, int[] indexes)
        {
            string[] result = {};
            foreach (var title in titles) {
                result += title;
            }

            if (this.group_mode != GROUP_MODE_PROJECT || selected_project_filter () != null) {
                return result;
            }

            for (int left = 0; left < result.length; left++) {
                for (int right = left + 1; right < result.length; right++) {
                    if (compare_dependency_graph_project_groups (result[left], result[right], indexes) > 0) {
                        var tmp = result[left];
                        result[left] = result[right];
                        result[right] = tmp;
                    }
                }
            }
            return result;
        }

        private int compare_dependency_graph_project_groups (string left_title, string right_title, int[] indexes)
        {
            var left_priority = priority_rank (highest_priority_for_group (left_title, indexes));
            var right_priority = priority_rank (highest_priority_for_group (right_title, indexes));
            if (left_priority != right_priority) {
                return left_priority - right_priority;
            }
            return GLib.strcmp (left_title, right_title);
        }

        private string highest_priority_for_group (string title, int[] indexes)
        {
            Todo[] group_todos = {};
            foreach (var index in indexes) {
                if (index >= 0 && index < this.todos.length && dependency_graph_group_key (this.todos[index]) == title) {
                    group_todos += this.todos[index];
                }
            }
            return highest_priority (group_todos);
        }

        private void bind_group_expansion (Adw.ExpanderRow expander, string title)
        {
            expander.expanded = group_expanded (title);
            expander.notify["expanded"].connect (() => remember_group_expanded (title, expander.expanded));
        }

        private bool group_expanded (string title)
        {
            return this.collapsed_group_keys.lookup (group_expansion_key (title)) == null;
        }

        private void remember_group_expanded (string title, bool expanded)
        {
            var key = group_expansion_key (title);
            if (expanded) {
                this.collapsed_group_keys.remove (key);
            }
            else {
                this.collapsed_group_keys.insert (key, key);
            }
        }

        private string group_expansion_key (string title)
        {
            var context_key = this.all_contexts ? "@all-contexts" : this.context.slug;
            var project_key = selected_project_filter () ?? "@all-projects";
            return "%u|%s|%s|%s".printf (this.group_mode, context_key, project_key, title);
        }

        private void clear_group_expansion_memory ()
        {
            this.collapsed_group_keys.remove_all ();
        }

        private Gtk.Widget indented_priority_prefix (Todo todo, int depth)
        {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            box.width_request = 18 + depth * 22;
            box.add_css_class ("dependency-graph-prefix");
            if (depth > 0) {
                var spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                spacer.width_request = depth * 22;
                box.append (spacer);
            }
            box.append (priority_label (todo.priority, priority_letters_colored (), show_priority_letter ()));
            return box;
        }

        private string dependency_graph_row_subtitle (int index, Todo todo, int depth)
        {
            string[] parts = {};
            if (this.all_contexts && index < this.todo_contexts.length) {
                parts += this.todo_contexts[index].name;
            }
            if (depth == 0) {
                var project_label = "";
                if (!(selected_project_filter () != null && this.group_mode == GROUP_MODE_PROJECT)) {
                    project_label = selected_project_filter () != null || this.group_mode == GROUP_MODE_PROJECT
                        ? (project_child (todo.project) == "" ? "" : project_child (todo.project))
                        : format_project_label (todo.project);
                }
                if (project_label != "") {
                    parts += project_label;
                }
            }
            if (this.group_mode != GROUP_MODE_DUE) {
                parts += due_label (todo.due);
            }
            return string.joinv (" · ", parts);
        }

        private int[] dependency_graph_order (int[] group_indexes)
        {
            var sorted = sorted_dependency_graph_candidates (group_indexes);
            int[] result = {};
            var emitted = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);

            foreach (var index in sorted) {
                if (dependency_graph_parent_index (index, group_indexes) == DEFAULT_TODO_INDEX) {
                    foreach (var branch_index in dependency_graph_branch (index, group_indexes, emitted)) {
                        result += branch_index;
                    }
                }
            }
            foreach (var index in sorted) {
                foreach (var branch_index in dependency_graph_branch (index, group_indexes, emitted)) {
                    result += branch_index;
                }
            }
            return result;
        }

        private int[] dependency_graph_branch (
            int index,
            int[] group_indexes,
            GLib.HashTable<string, string> emitted
        ) {
            int[] result = {};
            var key = dependency_graph_node_key (index);
            if (emitted.lookup (key) != null) {
                return result;
            }
            emitted.insert (key, key);
            result += index;

            foreach (var child in sorted_dependency_graph_candidates (dependency_graph_children (index, group_indexes))) {
                foreach (var branch_index in dependency_graph_branch (child, group_indexes, emitted)) {
                    result += branch_index;
                }
            }
            return result;
        }

        private int[] dependency_graph_children (int parent_index, int[] group_indexes)
        {
            int[] result = {};
            foreach (var index in group_indexes) {
                if (dependency_graph_parent_index (index, group_indexes) == parent_index) {
                    result += index;
                }
            }
            return result;
        }

        private int dependency_graph_descendant_count (int parent_index, int[] group_indexes)
        {
            var count = 0;
            foreach (var child in dependency_graph_children (parent_index, group_indexes)) {
                count++;
                count += dependency_graph_descendant_count (child, group_indexes);
            }
            return count;
        }

        private int dependency_graph_parent_index (int index, int[] group_indexes)
        {
            if (index < 0 || index >= this.todos.length || this.todos[index].dependency_id == "") {
                return DEFAULT_TODO_INDEX;
            }
            foreach (var candidate in group_indexes) {
                if (candidate >= 0
                    && candidate < this.todos.length
                    && this.todos[candidate].completed == this.todos[index].completed
                    && this.todos[candidate].id == this.todos[index].dependency_id) {
                    return candidate;
                }
            }
            return DEFAULT_TODO_INDEX;
        }

        private int dependency_graph_depth (int index, int[] group_indexes)
        {
            var depth = 0;
            var current = index;
            var seen = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
            while (depth < 24) {
                var key = dependency_graph_node_key (current);
                if (seen.lookup (key) != null) {
                    return depth;
                }
                seen.insert (key, key);

                var parent = dependency_graph_parent_index (current, group_indexes);
                if (parent == DEFAULT_TODO_INDEX) {
                    return depth;
                }
                current = parent;
                depth++;
            }
            return depth;
        }

        private int[] sorted_dependency_graph_candidates (int[] indexes)
        {
            int[] result = {};
            foreach (var index in indexes) {
                result += index;
            }
            for (int left = 0; left < result.length; left++) {
                for (int right = left + 1; right < result.length; right++) {
                    if (compare_priority_todo_indexes (result[left], result[right]) > 0) {
                        var tmp = result[left];
                        result[left] = result[right];
                        result[right] = tmp;
                    }
                }
            }
            return result;
        }

        private string dependency_graph_node_key (int index)
        {
            if (index >= 0 && index < this.todos.length && this.todos[index].id != "") {
                return this.todos[index].id;
            }
            return "@%d".printf (index);
        }

        private int[] filtered_todo_indexes ()
        {
            int[] indexes = {};
            var raw_filter = this.filter_entry.text.down ().strip ();
            string project_prefix;
            string filter_text;
            parse_project_prefix_filter (raw_filter, out project_prefix, out filter_text);
            var selected = selected_project_filter ();
            var priority_filter = project_prefix == "" && filter_text.length == 1 && is_priority (filter_text.up ()) ? filter_text.up () : "";
            var project_filter = normalize_project_filter (filter_text);

            for (int index = 0; index < this.todos.length; index++) {
                var todo = this.todos[index];
                if (this.group_mode == GROUP_MODE_RECURRING && !todo.recurring) {
                    continue;
                }
                if (this.group_mode != GROUP_MODE_RECURRING && todo.recurring) {
                    continue;
                }
                if (selected != null && todo.root_project != selected) {
                    continue;
                }
                if (todo.completed && !this.show_completed) {
                    continue;
                }
                if (project_prefix != "" && !todo.project.has_prefix (project_prefix)) {
                    continue;
                }
                if (priority_filter != "" && todo.priority != priority_filter) {
                    continue;
                }
                var haystack = "%s %s %s %s".printf (todo.body, todo.project, todo.priority, due_label (todo.due)).down ();
                var project_haystack = normalize_project_filter ("%s %s".printf (todo.project, format_project_label (todo.project)));
                if (filter_text != "" && project_prefix != "" && !todo.body.down ().contains (filter_text)) {
                    continue;
                }
                if (filter_text != "" && project_prefix == "" && priority_filter == "" && !haystack.contains (filter_text) && !project_haystack.contains (project_filter)) {
                    continue;
                }
                indexes += index;
            }
            return indexes;
        }

        private void parse_project_prefix_filter (string raw_filter, out string project_prefix, out string filter_text)
        {
            project_prefix = "";
            filter_text = raw_filter;
            if (!raw_filter.has_prefix ("+")) {
                return;
            }

            var space = raw_filter.index_of (" ");
            var first = space < 0 ? raw_filter : raw_filter.substring (0, space);
            filter_text = space < 0 ? "" : raw_filter.substring (space + 1).strip ();
            var project_text = normalize_project_filter (first.substring (1));
            if (project_text == "") {
                return;
            }

            var selected = selected_project_filter ();
            if (selected != null) {
                var root = project_root (project_text);
                var child = project_child (project_text);
                project_prefix = child == "" ? join_project (selected, root) : join_project (selected, child);
            }
            else {
                project_prefix = project_text;
            }
        }

        private int[] sorted_todo_indexes (int[] indexes)
        {
            int[] result = {};
            foreach (var index in indexes) {
                result += index;
            }

            for (int left = 0; left < result.length; left++) {
                for (int right = left + 1; right < result.length; right++) {
                    if (compare_todo_indexes (result[left], result[right]) > 0) {
                        var tmp = result[left];
                        result[left] = result[right];
                        result[right] = tmp;
                    }
                }
            }
            return result;
        }

        private int[] sorted_group_row_indexes (int[] indexes)
        {
            int[] result = {};
            foreach (var index in indexes) {
                result += index;
            }

            for (int left = 0; left < result.length; left++) {
                for (int right = left + 1; right < result.length; right++) {
                    if (compare_group_row_indexes (result[left], result[right]) > 0) {
                        var tmp = result[left];
                        result[left] = result[right];
                        result[right] = tmp;
                    }
                }
            }
            return result;
        }

        private int compare_group_row_indexes (int left_index, int right_index)
        {
            if (this.group_mode == GROUP_MODE_DUE || this.group_mode == GROUP_MODE_PROJECT) {
                return compare_priority_then_dependency_todo_indexes (left_index, right_index);
            }
            if (this.group_mode == GROUP_MODE_RECURRING) {
                return compare_due_todo_indexes (left_index, right_index);
            }
            return compare_todo_indexes (left_index, right_index);
        }

        private int compare_todo_indexes (int left_index, int right_index)
        {
            switch (this.group_mode)
            {
                case GROUP_MODE_DUE:
                    return compare_due_todo_indexes (left_index, right_index);

                case GROUP_MODE_PROJECT:
                    return compare_project_todo_indexes (left_index, right_index);

                case GROUP_MODE_RECURRING:
                    return compare_recurring_todo_indexes (left_index, right_index);

                default:
                    return compare_priority_todo_indexes (left_index, right_index);
            }
        }

        private int compare_recurring_todo_indexes (int left_index, int right_index)
        {
            var left = this.todos[left_index];
            var right = this.todos[right_index];
            var recurrence_cmp = recurrence_rank (left.recurrence) - recurrence_rank (right.recurrence);
            if (recurrence_cmp != 0) {
                return recurrence_cmp;
            }
            var due_cmp = compare_due_values (left, right);
            if (due_cmp != 0) {
                return due_cmp;
            }
            var priority_cmp = priority_rank (left.priority) - priority_rank (right.priority);
            if (priority_cmp != 0) {
                return priority_cmp;
            }
            return compare_dependency_or_creation (left_index, right_index);
        }

        private int recurrence_rank (string recurrence)
        {
            switch (recurrence_kind (recurrence))
            {
                case RECURRENCE_DAILY:
                    return 0;
                case RECURRENCE_WEEKLY:
                    return 1;
                case RECURRENCE_MONTHLY:
                    return 2;
                default:
                    return 3;
            }
        }

        private int compare_priority_todo_indexes (int left_index, int right_index)
        {
            var left = this.todos[left_index];
            var right = this.todos[right_index];
            var priority_cmp = priority_rank (left.priority) - priority_rank (right.priority);
            if (priority_cmp != 0) {
                return priority_cmp;
            }
            var due_cmp = compare_due_values (left, right);
            if (due_cmp != 0) {
                return due_cmp;
            }
            return compare_dependency_or_creation (left_index, right_index);
        }

        private int compare_priority_then_dependency_todo_indexes (int left_index, int right_index)
        {
            var left = this.todos[left_index];
            var right = this.todos[right_index];
            var priority_cmp = priority_rank (left.priority) - priority_rank (right.priority);
            if (priority_cmp != 0) {
                return priority_cmp;
            }
            return compare_dependency_or_creation (left_index, right_index);
        }

        private int compare_due_todo_indexes (int left_index, int right_index)
        {
            var left = this.todos[left_index];
            var right = this.todos[right_index];
            var due_cmp = compare_due_values (left, right);
            if (due_cmp != 0) {
                return due_cmp;
            }
            var priority_cmp = priority_rank (left.priority) - priority_rank (right.priority);
            if (priority_cmp != 0) {
                return priority_cmp;
            }
            return compare_dependency_or_creation (left_index, right_index);
        }

        private int compare_due_values (Todo left, Todo right)
        {
            var left_has_due = left.due != "";
            var right_has_due = right.due != "";
            if (left_has_due != right_has_due) {
                return left_has_due ? -1 : 1;
            }
            if (left.due != right.due) {
                return GLib.strcmp (left.due == "" ? "9999-12-31" : left.due, right.due == "" ? "9999-12-31" : right.due);
            }
            return 0;
        }

        private int compare_project_todo_indexes (int left_index, int right_index)
        {
            var left = this.todos[left_index];
            var right = this.todos[right_index];
            if (selected_project_filter () != null) {
                var left_child = project_child (left.project) == "" ? "Default" : project_child (left.project);
                var right_child = project_child (right.project) == "" ? "Default" : project_child (right.project);
                var child_cmp = GLib.strcmp (left_child, right_child);
                if (child_cmp != 0) {
                    return child_cmp;
                }
            }
            else {
                var root_cmp = GLib.strcmp (left.root_project, right.root_project);
                if (root_cmp != 0) {
                    return root_cmp;
                }
                var depth_cmp = project_depth (left.project) - project_depth (right.project);
                if (depth_cmp != 0) {
                    return depth_cmp;
                }
                var project_cmp = GLib.strcmp (left.project, right.project);
                if (project_cmp != 0) {
                    return project_cmp;
                }
            }
            return compare_dependency_or_creation (left_index, right_index);
        }

        private int compare_dependency_or_creation (int left_index, int right_index)
        {
            if (left_index == right_index) {
                return 0;
            }
            var left = this.todos[left_index];
            var right = this.todos[right_index];
            if (todo_depends_on_id (right, left.id)) {
                return -1;
            }
            if (todo_depends_on_id (left, right.id)) {
                return 1;
            }
            return left_index - right_index;
        }

        private bool todo_depends_on_id (Todo todo, string dependency_id)
        {
            if (dependency_id == "" || todo.dependency_id == "") {
                return false;
            }

            var current_id = todo.dependency_id;
            var seen = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
            while (current_id != "") {
                if (current_id == dependency_id) {
                    return true;
                }
                if (seen.lookup (current_id) != null) {
                    return false;
                }
                seen.insert (current_id, current_id);

                var current_index = todo_index_for_id (current_id);
                if (current_index == DEFAULT_TODO_INDEX) {
                    return false;
                }
                current_id = this.todos[current_index].dependency_id;
            }
            return false;
        }

        private int todo_index_for_id (string id)
        {
            for (int index = 0; index < this.todos.length; index++) {
                if (this.todos[index].id == id) {
                    return index;
                }
            }
            return DEFAULT_TODO_INDEX;
        }

        private void activate_single_filtered_todo ()
        {
            var indexes = filtered_todo_indexes ();
            var active_count = 0;
            var selected_index = DEFAULT_TODO_INDEX;
            foreach (var index in indexes) {
                if (!this.todos[index].completed) {
                    active_count++;
                    selected_index = index;
                }
            }
            if (active_count == 1) {
                row_activated (selected_index);
            }
        }

        private void select_context (string? slug)
        {
            clear_group_expansion_memory ();
            collapse_context_choices ();
            collapse_project_choices ();
            if (slug == null) {
                this.all_contexts = true;
                stop_timer ();
            }
            else {
                this.all_contexts = false;
                this.store.set_selected_context (slug);
            }
            set_selected_project_filter_state (null);
            this.selected_focus_project = null;
            set_selected_pomodoro_index (DEFAULT_TODO_INDEX);
            this.filter_entry.text = "";
            reload ();
            refresh_menu_lists ();
            refresh_project_filter ();
            sync_context_selector_state ();
            sync_project_selector_state ();
        }

        private void show_completed_changed ()
        {
            if (this.updating_show_toggle) {
                return;
            }

            this.show_completed = this.show_completed_toggle.active;
            sync_show_toggle ();
            refresh_project_filter ();
            refresh_todos ();
        }

        private void nested_items_changed ()
        {
            if (this.updating_show_toggle) {
                return;
            }

            if (this.group_mode == GROUP_MODE_RECURRING) {
                this.show_recurring_instances = this.nested_items_toggle.active;
            }
            else {
                this.show_nested_items = this.nested_items_toggle.active;
            }
            sync_show_toggle ();
            refresh_todos ();
        }

        private void sync_show_toggle ()
        {
            if (this.show_completed_toggle == null) {
                return;
            }

            var recurring_mode = this.group_mode == GROUP_MODE_RECURRING;
            var nested_mode = !recurring_mode && dependency_graph_enabled ();
            this.updating_show_toggle = true;
            this.show_completed_toggle.active = this.show_completed;
            if (this.nested_items_toggle != null) {
                this.nested_items_toggle.active = recurring_mode ? this.show_recurring_instances : this.show_nested_items;
            }
            this.updating_show_toggle = false;
            this.show_completed_toggle.visible = !recurring_mode;
            this.show_completed_toggle.tooltip_text = this.show_completed ? "Hide finished todos" : "Show finished todos";
            if (this.show_completed_toggle.active) {
                this.show_completed_toggle.add_css_class ("suggested-action");
            }
            else {
                this.show_completed_toggle.remove_css_class ("suggested-action");
            }

            if (this.nested_items_toggle != null) {
                this.nested_items_toggle.visible = recurring_mode || nested_mode;
                this.nested_items_toggle.tooltip_text = recurring_mode
                    ? (this.show_recurring_instances ? "Hide next instances" : "Show next instances")
                    : (this.show_nested_items ? "Hide nested todos" : "Show nested todos");
                if (this.nested_items_toggle.active) {
                    this.nested_items_toggle.add_css_class ("suggested-action");
                }
                else {
                    this.nested_items_toggle.remove_css_class ("suggested-action");
                }
            }

            if (this.recurring_new_button != null) {
                this.recurring_new_button.visible = recurring_mode;
                this.recurring_new_button.sensitive = !this.all_contexts;
            }
        }

        private void list_delete_mode_changed ()
        {
            if (this.updating_list_delete_mode) {
                return;
            }

            if (!this.store.show_delete_button && this.list_delete_toggle.active) {
                set_list_delete_mode (false, false);
                return;
            }

            this.list_delete_mode = this.list_delete_toggle.active;
            sync_list_delete_button ();
            refresh_todos ();
        }

        private void set_list_delete_mode (bool active, bool refresh_rows)
        {
            this.list_delete_mode = active && this.store.show_delete_button;
            if (this.list_delete_toggle != null) {
                this.updating_list_delete_mode = true;
                this.list_delete_toggle.active = this.list_delete_mode;
                this.updating_list_delete_mode = false;
            }
            sync_list_delete_button ();
            if (refresh_rows) {
                refresh_todos ();
            }
        }

        private void sync_list_delete_button ()
        {
            if (this.list_delete_toggle == null) {
                return;
            }

            var delete_button_visible = this.store.show_delete_button;
            if (!delete_button_visible && this.list_delete_mode) {
                this.list_delete_mode = false;
                this.updating_list_delete_mode = true;
                this.list_delete_toggle.active = false;
                this.updating_list_delete_mode = false;
            }

            this.list_delete_toggle.visible = delete_button_visible;
            this.list_delete_toggle.sensitive = delete_button_visible;
            this.list_delete_toggle.tooltip_text = this.list_delete_mode ? "Leave delete mode" : "Delete todos";
            if (this.list_delete_mode) {
                this.list_delete_toggle.add_css_class ("destructive-action");
            }
            else {
                this.list_delete_toggle.remove_css_class ("destructive-action");
            }
        }

        private void refresh_group_choices ()
        {
            if (this.group_choices == null) {
                return;
            }

            clear_box (this.group_choices);
            uint[] modes = {GROUP_MODE_DUE, GROUP_MODE_PRIORITY, GROUP_MODE_PROJECT, GROUP_MODE_RECURRING};
            foreach (var mode in modes) {
                this.group_choices.append (group_choice_button (mode));
            }
        }

        private Gtk.Button group_choice_button (uint mode)
        {
            var button = new Gtk.Button ();
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            row.append (new Gtk.Image.from_icon_name (group_icon_name (mode)));

            var label = new Gtk.Label (group_label (mode));
            label.xalign = 0;
            row.append (label);

            button.child = row;
            button.hexpand = true;
            if (mode == this.group_mode) {
                button.add_css_class ("suggested-action");
            }
            button.clicked.connect (() => select_group_mode (mode));
            return button;
        }

        private void select_group_mode (uint mode)
        {
            if (mode == this.group_mode) {
                this.group_popover.popdown ();
                return;
            }
            clear_group_expansion_memory ();
            this.group_mode = mode;
            if (!this.restoring_ui_state) {
                this.store.update_selected_order_mode (this.group_mode);
            }
            sync_group_button ();
            sync_show_toggle ();
            refresh_group_choices ();
            refresh_todos ();
            this.group_popover.popdown ();
        }

        private void sync_group_button ()
        {
            if (this.group_button == null) {
                return;
            }

            this.group_button.icon_name = group_icon_name (this.group_mode);
            this.group_button.tooltip_text = "Order by %s".printf (group_label (this.group_mode));
            sync_show_toggle ();
        }

        private string group_label (uint mode)
        {
            switch (mode)
            {
                case 1:
                    return "Due";
                case 2:
                    return "Project";
                case 3:
                    return "Recurring";
                default:
                    return "Priority";
            }
        }

        private string group_icon_name (uint mode)
        {
            switch (mode)
            {
                case 1:
                    return "x-office-calendar-symbolic";
                case 2:
                    return "folder-symbolic";
                case 3:
                    return "view-refresh-symbolic";
                default:
                    return "view-sort-descending-symbolic";
            }
        }

        private void select_project_filter (string? project)
        {
            if (this.all_contexts) {
                return;
            }
            collapse_project_choices ();
            collapse_context_choices ();
            set_selected_project_filter_state (project);
            this.selected_focus_project = null;
            select_best_timer_todo_for_current_filter ();
            refresh_all ();
            sync_project_selector_state ();
        }

        private void set_selected_project_filter_state (string? project)
        {
            var clean = project == null ? "" : project_root (normalize_project (project, ""));
            var previous = this.selected_project;
            this.selected_project = clean == "" ? null : clean;
            if (previous != this.selected_project) {
                clear_group_expansion_memory ();
            }
            this.store.set_selected_project (this.selected_project);
        }

        private void select_tab (string name)
        {
            if (name == "pomodoro" && !timer_available ()) {
                show_timer_unavailable_hint ();
                this.view.visible_child_name = "todos";
                return;
            }
            this.view.visible_child_name = name;
        }

        private void sync_tabs ()
        {
            sync_tabs_for_request (false);
        }

        private void sync_tabs_for_request (bool show_hint)
        {
            var can_timer = timer_available ();
            var current = this.view.visible_child_name ?? "pomodoro";
            if (!can_timer && current == "pomodoro") {
                if (show_hint) {
                    show_timer_unavailable_hint ();
                }
                this.view.visible_child_name = "todos";
                current = "todos";
            }

        }

        private void sync_context_sensitivity ()
        {
            if (this.start_pause_button == null) {
                return;
            }

            var can_timer = timer_available ();
            this.start_pause_button.sensitive = can_timer;
            this.finish_button.sensitive = can_timer;
            if (this.add_minute_button != null) {
                this.add_minute_button.sensitive = can_timer;
            }
            this.focus_button.sensitive = !this.all_contexts;
            this.pomodoro_current.sensitive = !this.all_contexts;
            this.pomodoro_edit.sensitive = can_timer;
            this.timer_label.remove_css_class ("timer-inactive");
            if (this.timer_session_indicator != null) {
                this.timer_session_indicator.remove_css_class ("timer-inactive");
            }
            if (!can_timer) {
                this.timer_label.add_css_class ("timer-inactive");
                if (this.timer_session_indicator != null) {
                    this.timer_session_indicator.add_css_class ("timer-inactive");
                }
            }
        }

        private void show_context_hint ()
        {
            show_context_hint_message ("All Contexts is an overview. Select one context to create, duplicate, or run a timer.");
        }

        private void show_timer_unavailable_hint ()
        {
            show_context_hint_message (timer_unavailable_message ());
        }

        private void show_context_hint_message (string message)
        {
            if (this.context_banner_hide_source != 0) {
                GLib.Source.remove (this.context_banner_hide_source);
                this.context_banner_hide_source = 0;
            }
            this.context_banner.title = message;
            this.context_banner.revealed = true;
            this.context_banner_hide_source = GLib.Timeout.add_seconds (CONTEXT_BANNER_TIMEOUT_SECONDS, () => {
                this.context_banner_hide_source = 0;
                hide_context_hint ();
                return GLib.Source.REMOVE;
            });
        }

        private void hide_context_hint ()
        {
            if (this.context_banner_hide_source != 0) {
                GLib.Source.remove (this.context_banner_hide_source);
                this.context_banner_hide_source = 0;
            }
            if (this.context_banner != null) {
                this.context_banner.revealed = false;
            }
        }

        private void set_timer_from_profile ()
        {
            set_timer_session (TimerSession.POMODORO);
        }

        private int timer_duration_for_session (TimerSession session)
        {
            var profile = this.store.selected_profile ();
            switch (session)
            {
                case TimerSession.SHORT_REST:
                    return profile.short_break_duration_seconds ();

                case TimerSession.LONG_REST:
                    return profile.long_break_duration_seconds ();

                default:
                    return profile.work_duration_seconds ();
            }
        }

        private void set_timer_session (TimerSession session)
        {
            this.timer_session = session;
            this.session_elapsed = false;
            this.remaining_seconds = timer_duration_for_session (session);
            update_timer_label ();
            sync_timer_session_label ();
            sync_finish_button ();
        }

        private void toggle_timer ()
        {
            if (!timer_available ()) {
                show_timer_unavailable_hint ();
                sync_timer_availability ();
                return;
            }
            if (this.timer_source != 0) {
                stop_timer ();
            }
            else {
                start_timer ();
            }
        }

        private void start_timer ()
        {
            if (this.timer_source != 0 || !timer_available ()) {
                return;
            }
            if (this.remaining_seconds <= 0) {
                this.session_elapsed = true;
                sync_finish_button ();
                return;
            }
            this.session_elapsed = false;
            sync_finish_button ();
            this.timer_source = GLib.Timeout.add_seconds (1, tick);
            sync_timer_button ();
        }

        private void stop_timer ()
        {
            if (this.timer_source != 0) {
                GLib.Source.remove (this.timer_source);
                this.timer_source = 0;
            }
            sync_timer_button ();
        }

        private bool tick ()
        {
            this.remaining_seconds = int.max (0, this.remaining_seconds - 1);
            update_timer_label ();
            if (this.remaining_seconds == 0) {
                this.timer_source = 0;
                sync_timer_button ();
                this.session_elapsed = true;
                sync_finish_button ();
                send_timer_session_finished_notification ();
                return GLib.Source.REMOVE;
            }
            return GLib.Source.CONTINUE;
        }

        public void notification_toggle_timer ()
        {
            this.present ();
            if (timer_available ()) {
                this.view.visible_child_name = "pomodoro";
            }
            toggle_timer ();
        }

        public void notification_finish_timer_session ()
        {
            this.present ();
            if (timer_available ()) {
                this.view.visible_child_name = "pomodoro";
            }
            finish_pomodoro ();
        }

        private void finish_pomodoro ()
        {
            if (!timer_available ()) {
                show_timer_unavailable_hint ();
                sync_timer_availability ();
                return;
            }

            var start_next_session = this.session_elapsed || this.remaining_seconds == 0;
            this.session_elapsed = false;
            sync_finish_button ();
            stop_timer ();
            if (timer_session_is_rest ()) {
                set_timer_session (TimerSession.POMODORO);
                refresh_all ();
                sync_timer_availability ();
                if (start_next_session && timer_available ()) {
                    start_timer ();
                }
                return;
            }

            if (this.selected_pomodoro_index >= 0 && this.selected_pomodoro_index < this.todos.length) {
                var todo = this.todos[this.selected_pomodoro_index];
                if (todo.pm <= 1) {
                    show_last_pomodoro_dialog (todo.copy (), start_next_session);
                    return;
                }
            }

            finish_current_pomodoro_at (this.selected_pomodoro_index, 0, start_next_session);
        }

        private void add_one_minute ()
        {
            if (!timer_available ()) {
                show_timer_unavailable_hint ();
                sync_timer_availability ();
                return;
            }
            this.remaining_seconds += 60;
            this.session_elapsed = false;
            update_timer_label ();
            sync_finish_button ();
        }

        private void show_last_pomodoro_dialog (Todo target, bool start_next_session)
        {
            var dialog = new Adw.AlertDialog (
                "Last Pomodoro Finished",
                target.body
            );
            dialog.prefer_wide_layout = true;

            var add_count = new Gtk.SpinButton.with_range (1, 99, 1);
            add_count.value = 1;
            add_count.numeric = true;
            add_count.halign = Gtk.Align.CENTER;
            add_count.valign = Gtk.Align.CENTER;
            add_count.margin_top = 6;
            dialog.extra_child = add_count;

            dialog.add_response ("add", "Add pomodoros");
            dialog.add_response ("complete", "Mark Complete");
            dialog.set_response_appearance ("complete", Adw.ResponseAppearance.SUGGESTED);
            dialog.set_default_response ("complete");
            dialog.set_close_response ("complete");
            dialog.response.connect ((response) => {
                var index = find_matching_todo_index (target);
                if (index == DEFAULT_TODO_INDEX) {
                    sync_timer_availability ();
                    return;
                }
                set_selected_pomodoro_index (index);
                var pomodoros_to_add = response == "add" ? int.max (1, add_count.get_value_as_int ()) : 0;
                finish_current_pomodoro_at (index, pomodoros_to_add, start_next_session);
            });
            dialog.present (this);
        }

        private void finish_current_pomodoro_at (int index, int pomodoros_to_add_before_finish, bool start_next_session)
        {
            if (index < 0 || index >= this.todos.length || this.todos[index].completed) {
                sync_timer_availability ();
                return;
            }

            var todo = this.todos[index];
            var completed_focus = todo_focus_project (todo);
            var completed_root = todo.root_project;
            if (pomodoros_to_add_before_finish > 0) {
                todo.pm = int.max (1, todo.pm) + pomodoros_to_add_before_finish;
                todo.completed = false;
            }
            todo.finish_pomodoro ();
            var completed_occurrence = todo.pm == 0;
            save_current_todos ();
            this.store.record_pomodoro (this.context.slug, todo.project, this.store.selected_profile_slug);

            if (completed_occurrence) {
                move_timer_to_next_todo (completed_focus, completed_root, index);
            }
            if (timer_duration_for_session (TimerSession.SHORT_REST) > 0) {
                set_timer_session (next_rest_session_after_pomodoro ());
            }
            else {
                set_timer_session (TimerSession.POMODORO);
            }

            refresh_all ();
            sync_timer_availability ();
            if (start_next_session && timer_available ()) {
                start_timer ();
            }
        }

        private void update_timer_label ()
        {
            var hours = this.remaining_seconds / 3600;
            var minutes = (this.remaining_seconds / 60) % 60;
            var seconds = this.remaining_seconds % 60;
            if (hours > 0) {
                this.timer_label.label = "%d:%02d:%02d".printf (hours, minutes, seconds);
            }
            else {
                this.timer_label.label = "%02d:%02d".printf (minutes, seconds);
            }
        }

        private void sync_timer_button ()
        {
            if (this.start_pause_button != null) {
                var running = this.timer_source != 0;
                this.start_pause_button.child = new Gtk.Image.from_icon_name (
                    running ? "media-playback-pause-symbolic" : "media-playback-start-symbolic"
                );
                this.start_pause_button.tooltip_text = running ? "Pause" : "Start";
            }
        }

        private void sync_timer_session_label ()
        {
            if (this.timer_session_indicator != null) {
                clear_box (this.timer_session_indicator);
                var label = new Gtk.Label (timer_session_text ());
                label.add_css_class ("numeric");
                this.timer_session_indicator.append (label);
                this.timer_session_indicator.tooltip_text = timer_session_tooltip ();
            }
        }

        private bool timer_session_is_rest ()
        {
            return this.timer_session == TimerSession.SHORT_REST || this.timer_session == TimerSession.LONG_REST;
        }

        private TimerSession next_rest_session_after_pomodoro ()
        {
            this.completed_pomodoros_in_cycle++;
            if (this.completed_pomodoros_in_cycle >= LONG_REST_INTERVAL) {
                this.completed_pomodoros_in_cycle = 0;
                return TimerSession.LONG_REST;
            }
            return TimerSession.SHORT_REST;
        }

        private string timer_session_text ()
        {
            switch (this.timer_session)
            {
                case TimerSession.SHORT_REST:
                    return "Short Break";

                case TimerSession.LONG_REST:
                    return "Long Break";

                default:
                    return "Pomodoro";
            }
        }

        private string timer_session_tooltip ()
        {
            switch (this.timer_session)
            {
                case TimerSession.SHORT_REST:
                    return "Short Break";

                case TimerSession.LONG_REST:
                    return "Long Break";

                default:
                    return "Pomodoro";
            }
        }

        private void sync_finish_button ()
        {
            if (this.finish_button == null) {
                return;
            }
            if (this.session_elapsed) {
                this.finish_button.add_css_class ("timer-finish-due");
            }
            else {
                this.finish_button.remove_css_class ("timer-finish-due");
            }
        }

        private void new_todo ()
        {
            if (this.all_contexts) {
                show_context_hint ();
                return;
            }
            this.main_menu_popover.popdown ();
            if (this.group_mode == GROUP_MODE_RECURRING) {
                open_recurring_template_dialog (null, DEFAULT_TODO_INDEX);
                return;
            }
            open_todo_dialog (null, DEFAULT_TODO_INDEX);
        }

        private void new_recurring_template ()
        {
            if (this.all_contexts) {
                show_context_hint ();
                return;
            }
            open_recurring_template_dialog (null, DEFAULT_TODO_INDEX);
        }

        private void edit_todo (int index)
        {
            if (index >= 0 && index < this.todos.length) {
                if (this.todos[index].recurring) {
                    open_recurring_template_dialog (this.todos[index], index);
                    return;
                }
                open_todo_dialog (this.todos[index], index);
            }
        }

        private void duplicate_todo (int index)
        {
            if (this.all_contexts || index < 0 || index >= this.todos.length) {
                return;
            }

            var duplicate = this.todos[index].copy ();
            duplicate.id = "";
            duplicate.body = "%s (2)".printf (duplicate.body);
            if (duplicate.recurring) {
                duplicate.recurrence_latest_due = "";
                open_recurring_template_dialog (duplicate, DEFAULT_TODO_INDEX, true);
                return;
            }
            duplicate.recurrence_parent_id = "";
            open_duplicate_todo_dialog (duplicate);
        }

        private void create_todo_from_pomodoro_filter_if_empty ()
        {
            if (this.pomodoro_search.text.strip () != "" && pomodoro_filter_match_count () == 0) {
                create_todo_from_pomodoro_filter ();
            }
        }

        private void create_todo_from_pomodoro_filter ()
        {
            var body = normalize_body_text (this.pomodoro_search.text);
            if (body == "") {
                return;
            }
            this.pomodoro_popover.popdown ();
            open_todo_dialog_with_defaults (null, DEFAULT_TODO_INDEX, body, timer_new_todo_default_project ());
        }

        private int pomodoro_filter_match_count ()
        {
            var filter = this.pomodoro_search.text.down ().strip ();
            var matches = 0;
            for (int index = 0; index < this.todos.length; index++) {
                var todo = this.todos[index];
                if (index == this.selected_pomodoro_index || todo.completed || !todo_matches_timer_filter (todo)) {
                    continue;
                }
                if (filter != "" && !timer_todo_filter_text (todo).contains (filter)) {
                    continue;
                }
                matches++;
            }
            return matches;
        }

        private void toggle_todo_completed (int index)
        {
            if (index < 0 || index >= this.todos.length) {
                return;
            }
            if (this.todos[index].recurring) {
                return;
            }

            if (this.todos[index].completed) {
                this.todos[index].restore_pm_after_completion ();
                save_todo_update_at (index, this.todos[index], false);
                refresh_all ();
                return;
            }

            var completed_focus = todo_focus_project (this.todos[index]);
            var completed_root = this.todos[index].root_project;
            this.todos[index].complete_with_zero_pm ();
            if (this.selected_pomodoro_index == index) {
                move_timer_to_next_todo (completed_focus, completed_root, index);
            }
            save_todo_update_at (index, this.todos[index], false);
            refresh_all ();
        }

        private void delete_todo_at (int index)
        {
            if (index < 0 || index >= this.todos.length) {
                return;
            }
            if (this.todos[index].recurring) {
                confirm_delete_recurring_template (this.todos[index].copy ());
                return;
            }

            delete_todo_at_confirmed (index);
        }

        private void confirm_delete_recurring_template (Todo target)
        {
            var dialog = new Adw.AlertDialog (
                "Delete Recurring Template",
                "Delete %s?\n\nGenerated recurring todos from this template will also stop appearing.".printf (
                    todo_body_summary (target.body)
                )
            );
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("delete", "Delete");
            dialog.set_close_response ("cancel");
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.response.connect ((response) => {
                if (response != "delete") {
                    return;
                }
                var index = find_matching_todo_index (target);
                if (index != DEFAULT_TODO_INDEX) {
                    delete_todo_at_confirmed (index);
                }
            });
            dialog.present (this);
        }

        private void delete_todo_at_confirmed (int index)
        {
            if (this.all_contexts) {
                save_todo_delete_at (index);
                if (this.selected_pomodoro_index == index) {
                    set_selected_pomodoro_index (DEFAULT_TODO_INDEX);
                }
                if (this.todos.length == 0) {
                    set_list_delete_mode (false, false);
                }
                refresh_all ();
                return;
            }

            Todo[] next = {};
            for (int current = 0; current < this.todos.length; current++) {
                if (current != index) {
                    next += this.todos[current];
                }
            }
            this.todos = next;
            if (this.selected_pomodoro_index == index) {
                set_selected_pomodoro_index (DEFAULT_TODO_INDEX);
            }
            else if (this.selected_pomodoro_index > index) {
                set_selected_pomodoro_index (this.selected_pomodoro_index - 1);
            }
            if (this.todos.length == 0) {
                set_list_delete_mode (false, false);
            }
            save_current_todos ();
            refresh_all ();
        }

        private void row_activated (int index)
        {
            if (this.all_contexts) {
                activate_all_contexts_todo (index);
                return;
            }
            if (index < 0 || index >= this.todos.length || this.todos[index].completed) {
                return;
            }
            if (this.todos[index].recurring) {
                open_recurring_template_dialog (this.todos[index], index);
                return;
            }
            select_pomodoro_todo_checked (index, true);
        }

        private void activate_all_contexts_todo (int index)
        {
            if (index < 0 || index >= this.todos.length || index >= this.todo_contexts.length || this.todos[index].completed) {
                return;
            }

            var target_context = this.todo_contexts[index];
            var target = this.todos[index].copy ();
            clear_group_expansion_memory ();
            this.all_contexts = false;
            this.store.set_selected_context (target_context.slug);
            this.context = this.store.selected_context ();
            set_selected_project_filter_state (null);
            this.selected_focus_project = todo_focus_project (target);
            set_selected_pomodoro_index (DEFAULT_TODO_INDEX);
            this.filter_entry.text = "";
            hide_context_hint ();
            this.todos = load_visible_todos ();
            set_timer_from_profile ();

            var local_index = find_matching_todo_index (target);
            if (local_index != DEFAULT_TODO_INDEX) {
                this.selected_focus_project = todo_focus_project (this.todos[local_index]);
                set_selected_pomodoro_index (local_index);
            }
            else {
                select_best_timer_todo_for_current_filter ();
            }

            refresh_menu_lists ();
            refresh_project_filter ();
            refresh_timer_focuses ();
            refresh_pomodoro_todos ();
            refresh_todos ();
            sync_context_sensitivity ();
            this.view.visible_child_name = "pomodoro";
            sync_tabs ();
            if (valid_selected_pomodoro ()) {
                var blocker = dependency_blocker_index (this.todos[this.selected_pomodoro_index]);
                if (blocker != DEFAULT_TODO_INDEX) {
                    show_dependency_dialog (this.selected_pomodoro_index, blocker, true);
                    return;
                }
            }
            start_timer ();
        }

        private int find_matching_todo_index (Todo target)
        {
            if (target.id != "") {
                for (int index = 0; index < this.todos.length; index++) {
                    if (this.todos[index].same_id (target)) {
                        return index;
                    }
                }
            }

            var target_line = target.to_line ();
            for (int index = 0; index < this.todos.length; index++) {
                if (this.todos[index].to_line () == target_line) {
                    return index;
                }
            }
            for (int index = 0; index < this.todos.length; index++) {
                if (this.todos[index].same_identity (target)) {
                    return index;
                }
            }
            return DEFAULT_TODO_INDEX;
        }

        private void edit_selected_pomodoro_todo ()
        {
            if (this.all_contexts) {
                show_context_hint ();
                return;
            }

            if (this.selected_pomodoro_index != DEFAULT_TODO_INDEX) {
                edit_todo (this.selected_pomodoro_index);
            }
        }

        private void select_pomodoro_todo (int index)
        {
            select_pomodoro_todo_checked (index, false);
        }

        private void select_pomodoro_todo_checked (int index, bool switch_to_timer)
        {
            if (index < 0 || index >= this.todos.length) {
                return;
            }
            var blocker = dependency_blocker_index (this.todos[index]);
            if (blocker != DEFAULT_TODO_INDEX) {
                show_dependency_dialog (index, blocker, switch_to_timer);
                return;
            }
            activate_pomodoro_todo (index, switch_to_timer);
        }

        private void activate_pomodoro_todo (int index, bool switch_to_timer)
        {
            if (index < 0 || index >= this.todos.length) {
                return;
            }
            this.selected_focus_project = todo_focus_project (this.todos[index]);
            set_selected_pomodoro_index (index);
            this.pomodoro_search.text = "";
            this.pomodoro_popover.popdown ();
            refresh_timer_focuses ();
            refresh_pomodoro_todos ();
            if (switch_to_timer) {
                this.view.visible_child_name = "pomodoro";
            }
        }

        private int dependency_blocker_index (Todo todo)
        {
            if (!this.store.dependencies_enabled || !todo_has_dependency (todo)) {
                return DEFAULT_TODO_INDEX;
            }

            var current_id = todo.dependency_id;
            var highest_unfinished = DEFAULT_TODO_INDEX;
            var seen = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
            while (current_id != "") {
                if (seen.lookup (current_id) != null) {
                    return highest_unfinished;
                }
                seen.insert (current_id, current_id);

                var index = todo_index_for_id (current_id);
                if (index == DEFAULT_TODO_INDEX) {
                    return highest_unfinished;
                }
                if (!this.todos[index].completed) {
                    highest_unfinished = index;
                }
                current_id = this.todos[index].dependency_id;
            }
            return highest_unfinished;
        }

        private void show_dependency_dialog (int todo_index, int dependency_index, bool switch_to_timer)
        {
            var todo = this.todos[todo_index];
            var dependency = this.todos[dependency_index];
            this.pomodoro_popover.popdown ();

            var dialog = new Adw.AlertDialog (
                "Dependency Not Complete",
                "%s depends on unfinished parent %s.\n\nWork on the highest dependency first.".printf (
                    todo_body_summary (todo.body),
                    todo_body_summary (dependency.body)
                )
            );
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("dependency", "Work on Highest Dependency");
            dialog.add_response ("remove", "Remove Dependency and Start");
            dialog.set_default_response ("dependency");
            dialog.set_close_response ("cancel");
            dialog.set_response_appearance ("dependency", Adw.ResponseAppearance.SUGGESTED);
            dialog.response.connect ((response) => {
                if (response == "dependency") {
                    select_pomodoro_todo_checked (dependency_index, true);
                    return;
                }
                if (response == "remove") {
                    if (todo_index >= 0 && todo_index < this.todos.length) {
                        this.todos[todo_index].dependency_id = "";
                        save_current_todos ();
                        activate_pomodoro_todo (todo_index, switch_to_timer);
                    }
                }
            });
            dialog.present (this);
        }

        private void open_recurring_template_dialog (Todo? todo, int index, bool template_mode = false)
        {
            if (this.all_contexts && index == DEFAULT_TODO_INDEX) {
                show_context_hint ();
                return;
            }

            var dialog_context = context_for_todo_index (index);
            var defaults = new_todo_default_project ();
            var projects = known_projects_for_context (dialog_context);

            TodoSaveFunc save = (item, cascade_children) => {
                var scope_todos = this.all_contexts ? this.store.load_todos (dialog_context) : this.todos;
                var owner_index = this.all_contexts && index != DEFAULT_TODO_INDEX
                    ? find_matching_todo_index_in (scope_todos, this.todos[index])
                    : index;
                for (int current = 0; current < scope_todos.length; current++) {
                    if (owner_index != DEFAULT_TODO_INDEX && current == owner_index) {
                        continue;
                    }
                    if (scope_todos[current].same_identity (item)) {
                        return "Identical recurring template already exists.";
                    }
                }

                if (this.all_contexts && index != DEFAULT_TODO_INDEX) {
                    save_todo_update_at (index, item, false);
                    refresh_all ();
                    return null;
                }

                if (index == DEFAULT_TODO_INDEX) {
                    this.todos += item;
                }
                else {
                    this.todos[index] = item;
                }

                if (this.context.project_icons.lookup (item.root_project) == null) {
                    this.context.set_project_icon (item.root_project, "folder-symbolic");
                    this.store.save ();
                }
                save_current_todos ();
                this.store.update_last_todo_defaults (
                    item.priority,
                    item.root_project,
                    project_child (item.project) == "" ? "Default" : project_child (item.project),
                    ""
                );
                refresh_all ();
                return null;
            };

            TodoDeleteFunc? delete_callback = null;
            if (index != DEFAULT_TODO_INDEX) {
                delete_callback = () => delete_todo_at (index);
            }

            var dialog = new RecurringDialog (
                this,
                dialog_context,
                projects,
                todo,
                (owned) save,
                (owned) delete_callback,
                defaults[0],
                defaults[1],
                this.store.last_todo_priority,
                index != DEFAULT_TODO_INDEX || selected_project_filter () != null,
                index != DEFAULT_TODO_INDEX && selected_project_filter () == null
            );
            dialog.present ();
        }

        private void open_todo_dialog (Todo? todo, int index)
        {
            open_todo_dialog_with_defaults (todo, index, "", new_todo_default_project ());
        }

        private void open_duplicate_todo_dialog (Todo todo)
        {
            open_todo_dialog_with_defaults (todo, DEFAULT_TODO_INDEX, "", new_todo_default_project (), true, true);
        }

        private void open_todo_dialog_with_defaults (
            Todo? todo,
            int index,
            string default_body,
            string[] defaults,
            bool focus_body_at_end = false,
            bool template_mode = false
        )
        {
            var dialog_context = context_for_todo_index (index);
            var projects = known_projects_for_context (dialog_context);

            TodoSaveFunc save = (item, cascade_children) => {
                var scope_todos = this.all_contexts ? this.store.load_todos (dialog_context) : this.todos;
                var owner_index = this.all_contexts && index != DEFAULT_TODO_INDEX
                    ? find_matching_todo_index_in (scope_todos, this.todos[index])
                    : index;
                for (int current = 0; current < scope_todos.length; current++) {
                    if (owner_index != DEFAULT_TODO_INDEX && current == owner_index) {
                        continue;
                    }
                    if (scope_todos[current].same_identity (item)) {
                        return "Identical todo already exists.";
                    }
                }

                if (this.all_contexts && index != DEFAULT_TODO_INDEX) {
                    save_todo_update_at (index, item, cascade_children);
                    refresh_all ();
                    return null;
                }

                if (index == DEFAULT_TODO_INDEX) {
                    this.todos += item;
                }
                else {
                    this.todos[index] = item;
                    if (cascade_children) {
                        cascade_dependency_constraints_from (index);
                    }
                    if (item.completed && this.selected_pomodoro_index == index) {
                        set_selected_pomodoro_index (DEFAULT_TODO_INDEX);
                    }
                }
                if (this.context.project_icons.lookup (item.root_project) == null) {
                    this.context.set_project_icon (item.root_project, "folder-symbolic");
                    this.store.save ();
                }
                save_current_todos ();
                this.store.update_last_todo_defaults (
                    item.priority,
                    item.root_project,
                    project_child (item.project) == "" ? "Default" : project_child (item.project),
                    item.due
                );
                refresh_all ();
                return null;
            };

            TodoDeleteFunc? delete_callback = null;
            if (index != DEFAULT_TODO_INDEX) {
                delete_callback = () => {
                    delete_todo_at (index);
                };
            }

            var dialog = new TodoDialog (
                this,
                dialog_context,
                projects,
                todo,
                (owned) save,
                (owned) delete_callback,
                default_body,
                defaults[0],
                defaults[1],
                this.store.last_todo_priority,
                todo == null ? this.store.last_todo_due_for_default () : todo.due,
                this.todos,
                this.store.dependencies_enabled,
                this.store.auto_depend_on_previous_todo,
                default_dependency_id (todo, defaults),
                index != DEFAULT_TODO_INDEX || selected_project_filter () != null,
                focus_body_at_end,
                template_mode,
                index != DEFAULT_TODO_INDEX && selected_project_filter () == null
            );
            dialog.present ();
        }

        private string[] new_todo_default_project ()
        {
            string root;
            var selected = selected_project_filter ();
            if (selected != null) {
                root = selected;
                return {root, this.store.last_todo_subproject_for_project (root)};
            }
            if (this.selected_focus_project != null) {
                root = project_root (this.selected_focus_project);
                return {root, this.store.last_todo_subproject_for_project (root)};
            }
            root = project_root (this.context.default_project);
            return {root, this.store.last_todo_subproject_for_project (root)};
        }

        private string[] timer_new_todo_default_project ()
        {
            var focus = valid_selected_focus_project ();
            if (focus != null) {
                return {project_root (focus), project_child (focus) == "" ? "Default" : project_child (focus)};
            }
            return new_todo_default_project ();
        }

        private string default_dependency_id (Todo? todo, string[] defaults)
        {
            if (!this.store.dependencies_enabled) {
                return "";
            }
            if (todo != null) {
                return todo.dependency_id;
            }
            if (!this.store.auto_depend_on_previous_todo || defaults.length < 2) {
                return "";
            }

            var project = join_project (defaults[0], defaults[1]);
            for (int index = this.todos.length - 1; index >= 0; index--) {
                if (this.todos[index].completed || this.todos[index].id == "" || this.todos[index].project != project) {
                    continue;
                }
                return this.todos[index].id;
            }
            return "";
        }

        private void confirm_delete_context (ContextConfig context)
        {
            if (this.store.contexts ().length <= 1) {
                return;
            }

            var count = this.store.load_todos (context).length;
            if (count == 0) {
                delete_context_confirmed (context);
                return;
            }

            delete_confirmation (
                "Delete Context",
                "Delete %s?".printf (context.name),
                delete_message ("context", count),
                () => delete_context_confirmed (context)
            );
        }

        private void delete_context_confirmed (ContextConfig context)
        {
            this.store.delete_context (context.slug);
            this.all_contexts = false;
            this.context = this.store.selected_context ();
            set_selected_project_filter_state (null);
            this.selected_focus_project = null;
            set_selected_pomodoro_index (DEFAULT_TODO_INDEX);
            reload ();
        }

        private void confirm_delete_project (string project)
        {
            if (!can_delete_project ()) {
                return;
            }

            var count = todos_for_project (project, true).length;
            if (count == 0) {
                delete_project_confirmed (project);
                return;
            }

            delete_confirmation (
                "Delete Project",
                "Delete %s?".printf (project),
                delete_message ("project", count),
                () => delete_project_confirmed (project)
            );
        }

        private string delete_message (string item_type, int linked_todo_count)
        {
            if (linked_todo_count <= 0) {
                return "This will delete the %s.".printf (item_type);
            }
            var todo_word = linked_todo_count == 1 ? "todo" : "todos";
            return "This will delete the %s. %d associated %s will disappear.".printf (item_type, linked_todo_count, todo_word);
        }

        private void delete_confirmation (string title, string heading, string message, owned MenuCallback on_delete)
        {
            var dialog = new Adw.Window ();
            dialog.transient_for = this;
            dialog.modal = true;
            dialog.title = title;
            dialog.default_width = 380;
            dialog.default_height = 170;

            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            root.margin_top = 16;
            root.margin_bottom = 16;
            root.margin_start = 16;
            root.margin_end = 16;
            dialog.content = root;

            var heading_label = new Gtk.Label (heading);
            heading_label.xalign = 0;
            heading_label.add_css_class ("heading");
            root.append (heading_label);

            var message_label = new Gtk.Label (message);
            message_label.xalign = 0;
            message_label.wrap = true;
            message_label.add_css_class ("caption");
            root.append (message_label);

            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            buttons.halign = Gtk.Align.END;
            var cancel = new Gtk.Button.with_label ("Cancel");
            cancel.clicked.connect (() => dialog.close ());
            var delete_button = new Gtk.Button.with_label ("Delete");
            delete_button.add_css_class ("destructive-action");
            delete_button.clicked.connect (() => {
                on_delete ();
                dialog.close ();
            });
            buttons.append (cancel);
            buttons.append (delete_button);
            root.append (buttons);
            dialog.present ();
        }

        private void delete_project_confirmed (string project)
        {
            if (!can_delete_project ()) {
                return;
            }

            Todo[] next = {};
            foreach (var todo in this.todos) {
                if (todo.project != project && !todo.project.has_prefix ("%s.".printf (project))) {
                    next += todo;
                }
            }
            this.todos = next;
            if (project_root (this.context.default_project) == project) {
                var remaining_roots = remaining_project_roots_after_delete (known_projects (), project);
                if (remaining_roots.length > 0) {
                    this.store.update_context (this.context, this.context.name, this.context.icon, remaining_roots[0]);
                }
            }
            this.store.delete_project_icons (this.context, project);
            this.store.delete_project_history (this.context.slug, project);
            set_selected_project_filter_state (null);
            this.selected_focus_project = null;
            set_selected_pomodoro_index (DEFAULT_TODO_INDEX);
            save_current_todos ();
            refresh_all ();
        }

        private bool can_delete_project ()
        {
            return !this.all_contexts && list_project_roots ().length > 1;
        }

        private void save_current_todos ()
        {
            apply_project_rules ();
            apply_completion_rules ();
            this.store.save_todos (this.todos, this.context);
            this.todos = this.store.load_todos (this.context);
            this.store.save ();
        }

        private void save_todo_update_at (int index, Todo item, bool cascade_children)
        {
            if (!this.all_contexts) {
                if (index >= 0 && index < this.todos.length) {
                    this.todos[index] = item;
                    if (cascade_children) {
                        cascade_dependency_constraints_from (index);
                    }
                }
                save_current_todos ();
                return;
            }

            var owner = context_for_todo_index (index);
            var owner_todos = this.store.load_todos (owner);
            var owner_index = find_matching_todo_index_in (owner_todos, this.todos[index]);
            if (owner_index == DEFAULT_TODO_INDEX) {
                return;
            }

            owner_todos[owner_index] = item;
            save_todos_for_context (owner, owner_todos, cascade_children ? owner_index : DEFAULT_TODO_INDEX);
            this.todos = load_visible_todos ();
        }

        private void save_todo_delete_at (int index)
        {
            if (!this.all_contexts || index < 0 || index >= this.todos.length) {
                return;
            }

            var owner = context_for_todo_index (index);
            var owner_todos = this.store.load_todos (owner);
            var owner_index = find_matching_todo_index_in (owner_todos, this.todos[index]);
            if (owner_index == DEFAULT_TODO_INDEX) {
                return;
            }

            Todo[] next = {};
            for (int current = 0; current < owner_todos.length; current++) {
                if (current != owner_index) {
                    next += owner_todos[current];
                }
            }
            save_todos_for_context (owner, next);
            this.todos = load_visible_todos ();
        }

        private void save_todos_for_context (
            ContextConfig target_context,
            Todo[] target_todos,
            int cascade_parent_index = DEFAULT_TODO_INDEX
        ) {
            var previous_context = this.context;
            var previous_todos = this.todos;

            this.context = target_context;
            this.todos = target_todos;
            if (cascade_parent_index != DEFAULT_TODO_INDEX) {
                cascade_dependency_constraints_from (cascade_parent_index);
            }
            apply_project_rules ();
            apply_completion_rules ();
            this.store.save_todos (this.todos, target_context);

            this.context = previous_context;
            this.todos = previous_todos;
            this.store.save ();
        }

        private ContextConfig context_for_todo_index (int index)
        {
            if (this.all_contexts && index >= 0 && index < this.todo_contexts.length) {
                return this.todo_contexts[index];
            }
            return this.context;
        }

        private int find_matching_todo_index_in (Todo[] values, Todo target)
        {
            if (target.id != "") {
                for (int index = 0; index < values.length; index++) {
                    if (values[index].same_id (target)) {
                        return index;
                    }
                }
            }

            var target_line = target.to_line ();
            for (int index = 0; index < values.length; index++) {
                if (values[index].to_line () == target_line) {
                    return index;
                }
            }
            for (int index = 0; index < values.length; index++) {
                if (values[index].same_identity (target)) {
                    return index;
                }
            }
            return DEFAULT_TODO_INDEX;
        }

        private void apply_completion_rules ()
        {
            foreach (var todo in this.todos) {
                if (todo.recurring) {
                    todo.pm = int.max (1, todo.pm);
                    todo.pm_done = 0;
                    todo.completed = false;
                }
                else {
                    todo.completed = todo.pm == 0;
                }
            }
        }

        private void apply_project_rules ()
        {
            for (int index = 0; index < this.todos.length; index++) {
                var main = this.todos[index];
                if (project_child (main.project) != "") {
                    continue;
                }

                var pm = 0;
                var pm_done = 0;
                var has_children = false;
                for (int child_index = 0; child_index < this.todos.length; child_index++) {
                    var child = this.todos[child_index];
                    if (!child.project.has_prefix ("%s.".printf (main.project))) {
                        continue;
                    }
                    has_children = true;
                    if (priority_rank (child.priority) < priority_rank (main.priority)) {
                        child.priority = main.priority;
                    }
                    if (main.due != "" && (child.due == "" || child.due > main.due)) {
                        child.due = main.due;
                    }
                    pm += child.pm;
                    pm_done += child.pm_done;
                }
                if (has_children) {
                    main.pm = pm;
                    main.pm_done = pm_done;
                }
            }
        }

        private void cascade_dependency_constraints_from (int parent_index)
        {
            if (!this.store.dependencies_enabled || parent_index < 0 || parent_index >= this.todos.length) {
                return;
            }

            var parent = this.todos[parent_index];
            if (parent.id == "") {
                return;
            }

            for (int index = 0; index < this.todos.length; index++) {
                var child = this.todos[index];
                if (child.completed || child.dependency_id != parent.id) {
                    continue;
                }
                if (priority_rank (child.priority) < priority_rank (parent.priority)) {
                    child.priority = parent.priority;
                }
                if (parent.due != "" && (child.due == "" || GLib.strcmp (child.due, parent.due) < 0)) {
                    child.due = parent.due;
                }
                cascade_dependency_constraints_from (index);
            }
        }

        private void move_timer_to_next_todo (string completed_focus, string completed_root, int completed_index)
        {
            var next = best_dependent_timer_todo_index (completed_index, completed_focus, completed_root);
            if (next == DEFAULT_TODO_INDEX) {
                next = best_timer_todo_index (completed_focus, completed_root, completed_index);
            }
            if (next < 0) {
                set_selected_pomodoro_index (DEFAULT_TODO_INDEX);
                return;
            }

            var todo = this.todos[next];
            set_selected_project_filter_state (todo.root_project);
            this.selected_focus_project = todo_focus_project (todo);
            set_selected_pomodoro_index (next);
        }

        private int best_dependent_timer_todo_index (int completed_index, string? preferred_focus, string? preferred_root)
        {
            if (!this.store.dependencies_enabled || completed_index < 0 || completed_index >= this.todos.length) {
                return DEFAULT_TODO_INDEX;
            }

            var completed_id = this.todos[completed_index].id;
            if (completed_id == "") {
                return DEFAULT_TODO_INDEX;
            }

            var best = DEFAULT_TODO_INDEX;
            for (int pass = 0; pass < 3; pass++) {
                for (int index = 0; index < this.todos.length; index++) {
                    if (index == completed_index
                        || this.todos[index].completed
                        || this.todos[index].dependency_id != completed_id
                        || !todo_matches_timer_filter (this.todos[index])
                        || dependency_blocker_index (this.todos[index]) != DEFAULT_TODO_INDEX) {
                        continue;
                    }
                    if (pass == 0 && preferred_focus != null && todo_focus_project (this.todos[index]) != preferred_focus) {
                        continue;
                    }
                    if (pass == 1 && preferred_root != null && this.todos[index].root_project != preferred_root) {
                        continue;
                    }
                    if (best == DEFAULT_TODO_INDEX || compare_timer_todo_indexes (index, best) < 0) {
                        best = index;
                    }
                }
                if (best != DEFAULT_TODO_INDEX) {
                    return best;
                }
            }
            return best;
        }

        private int best_timer_todo_index (string? preferred_focus = null, string? preferred_root = null, int exclude = -2)
        {
            var best = DEFAULT_TODO_INDEX;
            for (int pass = 0; pass < 3; pass++) {
                for (int index = 0; index < this.todos.length; index++) {
                    if (index == exclude || this.todos[index].completed || !todo_matches_timer_filter (this.todos[index])) {
                        continue;
                    }
                    if (dependency_blocker_index (this.todos[index]) != DEFAULT_TODO_INDEX) {
                        continue;
                    }
                    if (pass == 0 && preferred_focus != null && todo_focus_project (this.todos[index]) != preferred_focus) {
                        continue;
                    }
                    if (pass == 1 && preferred_root != null && this.todos[index].root_project != preferred_root) {
                        continue;
                    }
                    if (best == DEFAULT_TODO_INDEX || compare_timer_todo_indexes (index, best) < 0) {
                        best = index;
                    }
                }
                if (best != DEFAULT_TODO_INDEX) {
                    return best;
                }
            }
            return best;
        }

        private int compare_timer_todo_indexes (int left_index, int right_index)
        {
            var left = this.todos[left_index];
            var right = this.todos[right_index];
            var rank = priority_rank (left.priority) - priority_rank (right.priority);
            if (rank != 0) {
                return rank;
            }
            var left_due = left.due == "" ? "9999-12-31" : left.due;
            var right_due = right.due == "" ? "9999-12-31" : right.due;
            var due_cmp = GLib.strcmp (left_due, right_due);
            if (due_cmp != 0) {
                return due_cmp;
            }
            return compare_dependency_or_creation (left_index, right_index);
        }

        private void select_best_timer_todo_for_current_filter ()
        {
            set_selected_pomodoro_index (best_timer_todo_index ());
        }

        private void ensure_selected_timer_todo_for_current_filter ()
        {
            if (valid_selected_pomodoro ()) {
                persist_selected_todo ();
                return;
            }

            select_best_timer_todo_for_current_filter ();
        }

        private void restore_selected_todo ()
        {
            var saved_id = this.store.selected_todo_id;
            this.selected_pomodoro_index = DEFAULT_TODO_INDEX;
            if (saved_id == "") {
                return;
            }

            for (int index = 0; index < this.todos.length; index++) {
                if (this.todos[index].id != saved_id || this.todos[index].completed) {
                    continue;
                }

                this.selected_focus_project = todo_focus_project (this.todos[index]);
                if (todo_matches_timer_filter (this.todos[index])) {
                    set_selected_pomodoro_index (index);
                    return;
                }
            }

            persist_selected_todo ();
        }

        private void set_selected_pomodoro_index (int index)
        {
            this.selected_pomodoro_index = (index >= 0 && index < this.todos.length) ? index : DEFAULT_TODO_INDEX;
            persist_selected_todo ();
        }

        private void persist_selected_todo ()
        {
            if (this.restoring_ui_state) {
                return;
            }

            this.store.update_selected_todo_id (selected_timer_todo_id ());
        }

        private string selected_timer_todo_id ()
        {
            if (this.selected_pomodoro_index >= 0
                && this.selected_pomodoro_index < this.todos.length
                && !this.todos[this.selected_pomodoro_index].completed) {
                return this.todos[this.selected_pomodoro_index].id;
            }

            return "";
        }

        private void persist_selected_view ()
        {
            if (!this.restoring_ui_state && this.view != null) {
                this.store.update_selected_view (this.view.visible_child_name ?? "todos");
            }
        }

        private void persist_ui_state ()
        {
            if (this.restoring_ui_state) {
                return;
            }

            var width = this.get_width ();
            var height = this.get_height ();
            if (width <= 0 || height <= 0) {
                width = this.store.window_width;
                height = this.store.window_height;
            }

            this.store.update_ui_state (
                width,
                height,
                this.view != null ? this.view.visible_child_name : "todos",
                selected_timer_todo_id (),
                this.group_mode
            );
        }

        private void restore_selected_view ()
        {
            var target = this.store.selected_view;
            if (target == "pomodoro" && !timer_available ()) {
                target = "todos";
            }
            this.view.visible_child_name = target;
            persist_selected_view ();
        }

        private bool valid_selected_pomodoro ()
        {
            return this.selected_pomodoro_index >= 0
                && this.selected_pomodoro_index < this.todos.length
                && !this.todos[this.selected_pomodoro_index].completed
                && todo_matches_timer_filter (this.todos[this.selected_pomodoro_index]);
        }

        private bool timer_available ()
        {
            return !this.all_contexts && valid_selected_pomodoro ();
        }

        private string timer_unavailable_message ()
        {
            if (this.all_contexts) {
                return "Timer inactive. Select a specific context to use the timer.";
            }
            return "Select an active todo to use the timer.";
        }

        private void sync_timer_availability ()
        {
            if (!timer_available ()) {
                this.session_elapsed = false;
                sync_finish_button ();
                stop_timer ();
                if (this.view != null && this.view.visible_child_name == "pomodoro") {
                    this.view.visible_child_name = "todos";
                }
            }
            sync_context_sensitivity ();
            sync_tabs ();
        }

        private string? default_timer_focus_project (string[] focus_projects)
        {
            if (focus_projects.length == 0) {
                return null;
            }
            var best = best_timer_todo_index ();
            if (best >= 0) {
                return todo_focus_project (this.todos[best]);
            }
            return focus_projects[0];
        }

        private bool todo_matches_timer_filter (Todo todo)
        {
            if (todo.recurring) {
                return false;
            }
            if (selected_timer_project () != null && todo.root_project != selected_timer_project ()) {
                return false;
            }
            return valid_selected_focus_project () == null || todo_focus_project (todo) == valid_selected_focus_project ();
        }

        private string todo_focus_project (Todo todo)
        {
            return project_child (todo.project) == "" ? join_project (todo.root_project, "Default") : todo.project;
        }

        private string[] timer_focus_projects ()
        {
            string[] projects = {};
            foreach (var todo in this.todos) {
                if (todo.completed) {
                    continue;
                }
                if (selected_timer_project () != null && todo.root_project != selected_timer_project ()) {
                    continue;
                }
                projects = append_unique_string (projects, todo_focus_project (todo));
            }
            return projects;
        }

        private string timer_focus_label (string? project)
        {
            if (project == null) {
                return "No Project";
            }
            if (selected_timer_project () != null) {
                var child = project_child (project);
                return child == "" ? "Default" : child;
            }
            return format_project_label (project);
        }

        private bool focus_filter_matches (string project, string filter)
        {
            if (filter == "") {
                return true;
            }

            var label = timer_focus_label (project);
            var project_filter = normalize_project_filter (filter);
            var slash_project = project.replace (".", "/");
            var target = normalize_project_filter ("%s %s %s".printf (project, slash_project, label));
            return project.down ().contains (filter)
                || slash_project.down ().contains (filter)
                || label.down ().contains (filter)
                || (project_filter != "" && target.contains (project_filter));
        }

        private Gtk.Button focus_choice_button (string project)
        {
            var button = new Gtk.Button.with_label (timer_focus_label (project));
            button.hexpand = true;
            if (project == this.selected_focus_project) {
                button.add_css_class ("suggested-action");
            }
            button.clicked.connect (() => {
                this.selected_focus_project = project;
                this.focus_search.text = "";
                this.focus_popover.popdown ();
                select_best_timer_todo_for_current_filter ();
                refresh_timer_focuses ();
                refresh_pomodoro_todos ();
            });
            return button;
        }

        private string? selected_timer_project ()
        {
            return selected_project_filter ();
        }

        private string? selected_project_filter ()
        {
            var selected = string_array_contains (list_project_roots (), this.selected_project) ? this.selected_project : null;
            if (this.selected_project != null && selected == null) {
                set_selected_project_filter_state (null);
            }
            return selected;
        }

        private string? valid_selected_focus_project ()
        {
            return string_array_contains (timer_focus_projects (), this.selected_focus_project) ? this.selected_focus_project : null;
        }

        private string[] list_project_roots ()
        {
            return project_roots_from_projects (known_projects ());
        }

        private string[] known_projects ()
        {
            return known_projects_for_context (this.context);
        }

        private string[] known_projects_for_context (ContextConfig target_context)
        {
            string[] projects = {target_context.default_project};
            foreach (var key in target_context.project_icons.get_keys ()) {
                projects = append_unique_string (projects, key);
            }
            var source_todos = this.all_contexts ? this.store.load_todos (target_context) : this.todos;
            foreach (var todo in source_todos) {
                projects = append_unique_string (projects, todo.project);
            }
            return projects;
        }

        private Todo[] todos_for_project (string project, bool include_children)
        {
            Todo[] result = {};
            foreach (var todo in this.todos) {
                if ((include_children && project_child (project) == "" && (todo.project == project || todo.project.has_prefix ("%s.".printf (project))))
                    || todo.project == project) {
                    result += todo;
                }
            }
            return result;
        }

        private string group_key (Todo todo)
        {
            switch (this.group_mode)
            {
                case GROUP_MODE_DUE:
                    return due_group_label (todo.due);
                case GROUP_MODE_PROJECT:
                    if (selected_project_filter () != null) {
                        return project_child (todo.project) == "" ? "Default" : project_child (todo.project);
                    }
                    return todo.root_project;
                case GROUP_MODE_RECURRING:
                    return recurrence_label (todo.recurrence);
                default:
                    return todo.priority;
            }
        }

        private string row_subtitle (int index, Todo todo, bool child_row = false)
        {
            if (this.group_mode == GROUP_MODE_RECURRING && todo.recurring_instance) {
                return "";
            }

            string[] parts = {};
            if (this.all_contexts && index < this.todo_contexts.length) {
                parts += this.todo_contexts[index].name;
            }
            if (!child_row) {
                var project_label = "";
                if (!(selected_project_filter () != null && this.group_mode == GROUP_MODE_PROJECT)) {
                    project_label = selected_project_filter () != null || this.group_mode == GROUP_MODE_PROJECT
                        ? (project_child (todo.project) == "" ? "" : project_child (todo.project))
                        : format_project_label (todo.project);
                }
                if (project_label != "") {
                    parts += project_label;
                }
            }
            if (this.group_mode != GROUP_MODE_DUE) {
                parts += due_label (todo.due);
            }
            if (row_due_on_separate_line () && parts.length >= 2) {
                var due = parts[parts.length - 1];
                string[] first_line = {};
                for (int part_index = 0; part_index < parts.length - 1; part_index++) {
                    first_line += parts[part_index];
                }
                return "%s\n%s".printf (string.joinv (" · ", first_line), due);
            }
            return string.joinv (" · ", parts);
        }

        private string child_count_note (int count)
        {
            return count == 1 ? "1 child" : "%d children".printf (count);
        }

        private string recurring_template_subtitle (Todo todo)
        {
            string[] parts = {};
            var project = format_project_label (todo.project);
            if (project != "") {
                parts += project;
            }
            parts += recurrence_schedule_label (todo);
            return string.joinv (" · ", parts);
        }

        private string recurring_instance_row_title (Todo todo)
        {
            if (this.group_mode != GROUP_MODE_RECURRING || !todo.recurring_instance) {
                return todo.body;
            }
            return uppercase_first_letter (due_group_label (todo.due));
        }

        private bool priority_letters_colored ()
        {
            return this.group_mode == GROUP_MODE_PROJECT || this.group_mode == GROUP_MODE_RECURRING;
        }

        private bool show_priority_letter ()
        {
            return this.group_mode != GROUP_MODE_PRIORITY;
        }

        private int row_subtitle_lines ()
        {
            return row_due_on_separate_line () ? 2 : 1;
        }

        private bool row_due_on_separate_line ()
        {
            return this.narrow_layout && this.group_mode == GROUP_MODE_PRIORITY && selected_project_filter () == null;
        }

        private string earliest_due (Todo[] values)
        {
            var result = "";
            foreach (var todo in values) {
                if (todo.due == "") {
                    continue;
                }
                if (result == "" || todo.due < result) {
                    result = todo.due;
                }
            }
            return result;
        }

        private Gtk.Widget colored_dot (string color)
        {
            var label = new Gtk.Label ("");
            label.add_css_class ("priority-dot");
            label.set_markup ("<span foreground='%s'>●</span>".printf (color));
            return label;
        }

        private Gtk.Widget priority_label (string priority, bool colored, bool show_letter = true)
        {
            var label = new Gtk.Label (show_letter ? priority : "");
            label.width_request = 18;
            label.add_css_class ("heading");
            if (show_letter && colored) {
                label.set_markup ("<span foreground='%s' weight='bold'>%s</span>".printf (priority_color (priority), priority));
            }
            return label;
        }

        private Gtk.Widget animated_action (Gtk.Widget host, Gtk.Button button)
        {
            var revealer = action_revealer (button);
            add_right_click_toggle (host, {revealer});
            return revealer;
        }

        private void style_inline_action_button (Gtk.Button button)
        {
            button.width_request = 34;
            button.height_request = 34;
            button.halign = Gtk.Align.CENTER;
            button.valign = Gtk.Align.CENTER;
            button.add_css_class ("flat");
            button.add_css_class ("todo-inline-action");
        }

        private Gtk.Revealer action_revealer_for_row (Gtk.Button button)
        {
            return action_revealer_with_transition (
                button,
                this.narrow_layout ? Gtk.RevealerTransitionType.SLIDE_DOWN : Gtk.RevealerTransitionType.SLIDE_LEFT
            );
        }

        private Gtk.Revealer action_revealer (Gtk.Button button)
        {
            return action_revealer_with_transition (button, Gtk.RevealerTransitionType.SLIDE_LEFT);
        }

        private Gtk.Revealer action_revealer_with_transition (Gtk.Button button, Gtk.RevealerTransitionType transition_type)
        {
            style_inline_action_button (button);
            var revealer = new Gtk.Revealer ();
            revealer.transition_type = transition_type;
            revealer.transition_duration = 160;
            revealer.reveal_child = false;
            revealer.visible = false;
            revealer.child = button;
            this.inline_action_revealers += revealer;
            return revealer;
        }

        private Gtk.Revealer timer_action_revealer (Gtk.Widget child, Gtk.RevealerTransitionType transition_type)
        {
            var revealer = new Gtk.Revealer ();
            revealer.transition_type = transition_type;
            revealer.transition_duration = 160;
            revealer.reveal_child = true;
            revealer.child = child;
            return revealer;
        }

        private int todo_row_pomodoro_icon_limit ()
        {
            return this.narrow_layout ? 8 : 15;
        }

        private int todo_row_pomodoro_icons_per_line ()
        {
            return this.todo_row_pomodoro_line_capacity;
        }

        private int todo_row_pomodoro_icons_per_line_for_width (int width)
        {
            if (width < 620) {
                return 4;
            }
            if (width >= 1000) {
                return 12;
            }
            return 8;
        }

        private void add_right_click_toggle (Gtk.Widget host, Gtk.Revealer[] revealers)
        {
            var group = new InlineActionGroup (revealers);
            this.inline_action_groups += group;
            var click = new Gtk.GestureClick ();
            click.button = 3;
            click.pressed.connect (() => {
                clear_highlighted_todo_marker ();
                toggle_inline_actions (group.revealers);
            });
            host.add_controller (click);
        }

        private void toggle_timer_action_controls ()
        {
            if (!this.narrow_layout) {
                return;
            }

            this.store.compact_timer_actions = !this.store.compact_timer_actions;
            this.store.save ();
            sync_timer_action_controls ();
            refresh_pomodoro_todos ();
        }

        private bool open_selected_timer_todo_in_list ()
        {
            if (!timer_actions_are_compact () || !valid_selected_pomodoro ()) {
                return false;
            }

            this.highlighted_todo_index = this.selected_pomodoro_index;
            this.highlighted_todo_clear_armed = false;
            if (!todo_index_visible_in_list (this.highlighted_todo_index)) {
                this.filter_entry.text = "";
            }

            this.pomodoro_popover.popdown ();
            this.view.visible_child_name = "todos";
            refresh_todos ();
            schedule_highlight_scroll ();
            GLib.Timeout.add (120, () => {
                this.highlighted_todo_clear_armed = true;
                return GLib.Source.REMOVE;
            });
            return true;
        }

        private bool todo_index_visible_in_list (int target)
        {
            foreach (var index in filtered_todo_indexes ()) {
                if (index == target) {
                    return true;
                }
            }
            return false;
        }

        private void schedule_highlight_scroll ()
        {
            GLib.Idle.add (() => {
                scroll_to_highlighted_todo ();
                return GLib.Source.REMOVE;
            });
        }

        private void scroll_to_highlighted_todo ()
        {
            if (this.todo_scroller == null || this.highlighted_todo_row == null || this.todos_box == null) {
                return;
            }

            Graphene.Rect bounds;
            if (!this.highlighted_todo_row.compute_bounds (this.todos_box, out bounds)) {
                return;
            }

            var adjustment = this.todo_scroller.vadjustment;
            var target = double.max (adjustment.lower, double.min (adjustment.upper - adjustment.page_size, bounds.origin.y - 18));
            animate_scroll_to (adjustment, target);
        }

        private void animate_scroll_to (Gtk.Adjustment adjustment, double target)
        {
            if (this.highlight_scroll_source != 0) {
                GLib.Source.remove (this.highlight_scroll_source);
                this.highlight_scroll_source = 0;
            }

            var start = adjustment.value;
            var distance = target - start;
            if (distance.abs () < 1.0) {
                adjustment.value = target;
                return;
            }

            var started_at = GLib.get_monotonic_time ();
            this.highlight_scroll_source = GLib.Timeout.add (16, () => {
                var elapsed_ms = (double) (GLib.get_monotonic_time () - started_at) / 1000.0;
                var progress = double.min (1.0, elapsed_ms / 220.0);
                var eased = progress * progress * (3.0 - 2.0 * progress);
                adjustment.value = start + (distance * eased);
                if (progress >= 1.0) {
                    this.highlight_scroll_source = 0;
                    return GLib.Source.REMOVE;
                }
                return GLib.Source.CONTINUE;
            });
        }

        private void clear_highlighted_todo_marker ()
        {
            if (this.highlighted_todo_index == DEFAULT_TODO_INDEX) {
                return;
            }

            if (this.highlighted_todo_row != null) {
                this.highlighted_todo_row.remove_css_class ("todo-jump-highlight");
            }
            this.highlighted_todo_index = DEFAULT_TODO_INDEX;
            this.highlighted_todo_row = null;
        }

        private bool timer_actions_are_compact ()
        {
            return this.narrow_layout && this.store.compact_timer_actions;
        }

        private void sync_timer_action_controls ()
        {
            if (this.timer_focus_revealer == null || this.pomodoro_edit_revealer == null || this.pomodoro_current == null) {
                return;
            }

            var compact = timer_actions_are_compact ();
            var reveal = !compact;
            this.timer_focus_revealer.reveal_child = reveal;
            this.pomodoro_edit_revealer.reveal_child = reveal;
            if (this.timer_focus_row != null && this.narrow_layout) {
                this.timer_focus_row.visible = reveal;
            }
            if (!this.narrow_layout) {
                this.pomodoro_current.tooltip_text = "Click to search todos";
            }
            else if (compact) {
                this.pomodoro_current.tooltip_text = "Click to open this todo in the list.\nRight-click to leave compact mode.";
            }
            else {
                this.pomodoro_current.tooltip_text = "Click to search todos.\nRight-click to enter compact mode.";
            }
        }

        private bool sync_responsive_layout ()
        {
            if (this.filter_entry == null || this.focus_button == null) {
                return GLib.Source.CONTINUE;
            }

            var width = this.get_width ();
            if (width <= 0) {
                return GLib.Source.CONTINUE;
            }

            var narrow = width < 620;
            var line_capacity = todo_row_pomodoro_icons_per_line_for_width (width);
            if (this.responsive_layout_ready && narrow == this.narrow_layout && line_capacity == this.todo_row_pomodoro_line_capacity) {
                return GLib.Source.CONTINUE;
            }

            this.responsive_layout_ready = true;
            this.narrow_layout = narrow;
            this.todo_row_pomodoro_line_capacity = line_capacity;
            set_pomodoro_spacing (narrow);
            sync_timer_todo_label_width ();

            if (narrow) {
                this.filter_entry.hexpand = true;
                this.filter_entry.width_request = -1;
                this.list_spacer.hexpand = true;
                place_in_box (this.list_search_row, {this.filter_entry});
                place_in_box (this.list_buttons_row, {this.group_button, this.nested_items_toggle, this.show_completed_toggle, this.recurring_new_button, this.list_spacer, this.list_delete_toggle});
                this.list_buttons_row.visible = true;

                this.timer_focus_revealer.hexpand = true;
                this.focus_button.hexpand = true;
                place_in_box (this.timer_focus_row, {this.timer_focus_revealer});
                place_in_box (this.timer_todo_row, {this.pomodoro_current, this.pomodoro_edit_revealer});
                this.timer_focus_row.visible = true;
            }
            else {
                this.filter_entry.hexpand = true;
                this.filter_entry.width_request = -1;
                this.list_spacer.hexpand = false;
                place_in_box (this.list_search_row, {this.filter_entry, this.group_button, this.list_spacer, this.nested_items_toggle, this.show_completed_toggle, this.recurring_new_button, this.list_delete_toggle});
                this.list_buttons_row.visible = false;

                this.timer_focus_revealer.hexpand = false;
                this.focus_button.hexpand = false;
                this.timer_focus_row.visible = false;
                place_in_box (this.timer_todo_row, {this.timer_focus_revealer, this.pomodoro_current, this.pomodoro_edit_revealer});
            }

            sync_timer_action_controls ();
            refresh_pomodoro_todos ();
            refresh_todos ();

            return GLib.Source.CONTINUE;
        }

        private void place_in_box (Gtk.Box box, Gtk.Widget[] widgets)
        {
            foreach (var widget in widgets) {
                var parent = widget.parent;
                if (parent is Gtk.Box) {
                    ((Gtk.Box) parent).remove (widget);
                }
            }

            foreach (var widget in widgets) {
                box.append (widget);
            }
        }

        private void toggle_inline_actions (Gtk.Revealer[] selected)
        {
            var hide_selected = true;
            foreach (var revealer in selected) {
                if (!revealer.reveal_child) {
                    hide_selected = false;
                    break;
                }
            }

            if (hide_selected) {
                foreach (var revealer in selected) {
                    hide_inline_action (revealer);
                }
                return;
            }

            Gtk.Revealer[] live = {};
            foreach (var revealer in this.inline_action_revealers) {
                if (revealer.parent != null) {
                    if (revealer_in_array (selected, revealer)) {
                        show_inline_action (revealer);
                    }
                    else {
                        hide_inline_action (revealer);
                    }
                    live += revealer;
                }
            }
            this.inline_action_revealers = live;
        }

        private void show_inline_action (Gtk.Revealer revealer)
        {
            revealer.visible = true;
            revealer.reveal_child = true;
        }

        private void hide_inline_action (Gtk.Revealer revealer)
        {
            revealer.reveal_child = false;
            GLib.Timeout.add (170, () => {
                if (!revealer.reveal_child) {
                    revealer.visible = false;
                }
                return GLib.Source.REMOVE;
            });
        }

        private bool revealer_in_array (Gtk.Revealer[] revealers, Gtk.Revealer target)
        {
            foreach (var revealer in revealers) {
                if (revealer == target) {
                    return true;
                }
            }
            return false;
        }

        private void add_pointer_cursor (Gtk.Widget widget)
        {
            var hover = new Gtk.EventControllerMotion ();
            hover.enter.connect (() => widget.set_cursor_from_name ("pointer"));
            hover.leave.connect (() => widget.set_cursor_from_name (null));
            widget.add_controller (hover);
        }

        private void sanitize_creator_entry (Gtk.Entry entry, int max_length)
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

        private string todo_summary (Todo todo)
        {
            return trim_text_to_word (todo.body, 44);
        }

        private string timer_todo_body (Todo todo)
        {
            return todo_display_summary (todo, TODO_SUMMARY_MAX_CHARS);
        }

        private string timer_todo_filter_text (Todo todo)
        {
            var focus = todo_focus_project (todo);
            return "%s %s %s %s".printf (
                todo.body,
                focus,
                focus.replace (".", "/"),
                format_project_label (focus)
            ).down ();
        }

        private void set_pomodoro_current_label (string label)
        {
            if (this.pomodoro_current_label != null) {
                this.pomodoro_current_label.label = label;
            }
            else if (this.pomodoro_current != null) {
                this.pomodoro_current.label = label;
            }
        }

        private void sync_pomodoro_meta ()
        {
            if (this.all_contexts) {
                set_pomodoro_meta_text ("Timer inactive · Select a specific context");
                return;
            }
            if (!valid_selected_pomodoro ()) {
                set_pomodoro_meta_text ("Timer inactive · Select an active todo");
                return;
            }
            var todo = this.todos[this.selected_pomodoro_index];
            clear_box (this.pomodoro_meta);
            this.pomodoro_meta.append (pomodoro_meta_label ("%s · %s ·".printf (todo.priority, due_label (todo.due))));
            var pomodoros = pomodoro_display_widget (
                todo.pm,
                this.store.repeat_pomodoro_icons,
                todo_row_pomodoro_icon_limit (),
                todo_row_pomodoro_icons_per_line ()
            );
            pomodoros.halign = Gtk.Align.START;
            this.pomodoro_meta.append (pomodoros);
            this.pomodoro_meta.visible = true;
        }

        private void set_pomodoro_meta_text (string text)
        {
            clear_box (this.pomodoro_meta);
            this.pomodoro_meta.append (pomodoro_meta_label (text));
            this.pomodoro_meta.visible = true;
        }

        private void sync_timer_todo_label_width ()
        {
            if (this.pomodoro_current_label == null) {
                return;
            }

            this.pomodoro_current_label.max_width_chars = TODO_SUMMARY_MAX_CHARS;
            if (this.focus_button_label != null) {
                this.focus_button_label.max_width_chars = this.narrow_layout ? 18 : 20;
            }
        }

        private void set_focus_button_label (string label)
        {
            if (this.focus_button_label != null) {
                this.focus_button_label.label = label;
            }
            else if (this.focus_button != null) {
                this.focus_button.label = label;
            }
        }

        private Gtk.Label pomodoro_meta_label (string text)
        {
            var label = new Gtk.Label (text);
            label.xalign = 0;
            label.add_css_class ("caption");
            return label;
        }

        private void show_settings ()
        {
            this.main_menu_popover.popdown ();
            new PreferencesWindow (this, this.store, this.narrow_layout, () => {
                set_timer_from_profile ();
                refresh_all ();
            }, () => show_shortcuts_from_settings ()).present ();
        }

        private void show_shortcuts ()
        {
            this.main_menu_popover.popdown ();
            show_shortcuts_dialog ();
        }

        private void show_shortcuts_from_settings ()
        {
            show_shortcuts_dialog ();
        }

        private void show_shortcuts_dialog ()
        {
            var dialog = new Adw.ShortcutsDialog ();
            var section = new Adw.ShortcutsSection ("Tomodoro");
            section.add (new Adw.ShortcutsItem ("New todo", "<primary>n"));
            section.add (new Adw.ShortcutsItem ("Focus list search", "<primary>f"));
            section.add (new Adw.ShortcutsItem ("Timer view", "<primary>1"));
            section.add (new Adw.ShortcutsItem ("List view", "<primary>2"));
            section.add (new Adw.ShortcutsItem ("Keyboard shortcuts", "<primary>?"));
            dialog.add ((owned) section);
            dialog.present (this);
        }

        private void show_about ()
        {
            this.main_menu_popover.popdown ();
            var about = new Adw.AboutDialog ();
            about.application_name = Config.APPLICATION_NAME;
            about.application_icon = Config.APPLICATION_ID;
            about.developer_name = "Mohamed Amin";
            about.version = Config.PACKAGE_VERSION;
            about.comments = "Todo + Pomodoro = Tomodoro. Plan todo.txt tasks and work through them with focused Pomodoro sessions.";
            about.website = Config.PACKAGE_WEBSITE;
            about.set_release_notes_version (Config.PACKAGE_VERSION);
            about.release_notes = """
<ul>
  <li>Prepare Flathub packaging with a GitHub-matching application ID and source manifest.</li>
</ul>
""";
            about.present (this);
        }

        private void send_due_notifications ()
        {
            foreach (var message in this.store.due_notifications ()) {
                var notification = new GLib.Notification (Config.APPLICATION_NAME);
                notification.set_body (message);
                this.application.send_notification (message, notification);
            }
        }

        private void send_timer_session_finished_notification ()
        {
            send_timer_notification ("Start/Pause");
        }

        private string timer_notification_body ()
        {
            if (valid_selected_pomodoro ()) {
                return timer_todo_body (this.todos[this.selected_pomodoro_index]);
            }
            return "";
        }

        private void send_timer_notification (string toggle_label)
        {
            var notification = new GLib.Notification (timer_session_text ());
            var body = timer_notification_body ();
            if (body != "") {
                notification.set_body (body);
            }

            notification.set_priority (GLib.NotificationPriority.HIGH);
            notification.set_category ("timer");
            notification.set_default_action (this.session_elapsed ? "app.timer-done" : "app.timer-toggle");
            notification.add_button (toggle_label, "app.timer-toggle");
            notification.add_button ("Done", "app.timer-done");
            this.application.send_notification ("timer-session", notification);
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

        private static string[] append_unique_string (string[] values, string? value)
        {
            if (value == null || value == "") {
                return values;
            }
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

        private static bool string_array_contains (string[] values, string? needle)
        {
            if (needle == null) {
                return false;
            }
            foreach (var value in values) {
                if (value == needle) {
                    return true;
                }
            }
            return false;
        }
    }
}
