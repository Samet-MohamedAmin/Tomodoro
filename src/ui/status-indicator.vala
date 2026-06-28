namespace Tomodoro
{
    private const string SNI_WATCHER_NAME = "org.kde.StatusNotifierWatcher";
    private const string SNI_WATCHER_PATH = "/StatusNotifierWatcher";
    private const string SNI_ITEM_PATH = "/StatusNotifierItem";
    private const string SNI_MENU_PATH = "/StatusNotifierMenu";

    [DBus (name = "org.kde.StatusNotifierWatcher")]
    private interface StatusNotifierWatcher : GLib.Object
    {
        public abstract void register_status_notifier_item (string service) throws GLib.DBusError, GLib.IOError;
    }

    [DBus (name = "org.kde.StatusNotifierItem")]
    private class StatusNotifierItem : GLib.Object
    {
        private GLib.ObjectPath menu_path;

        public StatusNotifierItem (string menu_path)
        {
            this.menu_path = new GLib.ObjectPath (menu_path);
        }

        public string id {
            owned get {
                return Config.APPLICATION_ID;
            }
        }

        public string category {
            owned get {
                return "ApplicationStatus";
            }
        }

        public string status {
            owned get {
                return "Active";
            }
        }

        public string title {
            owned get {
                return Config.APPLICATION_NAME;
            }
        }

        public string icon_name {
            owned get {
                return @"$(Config.APPLICATION_ID)-symbolic";
            }
        }

        public string icon_theme_path {
            owned get {
                return "";
            }
        }

        public bool item_is_menu {
            get {
                return false;
            }
        }

        public GLib.ObjectPath menu {
            owned get {
                return this.menu_path;
            }
        }

        public int32 window_id {
            get {
                return 0;
            }
        }

        [DBus (signature = "a(iiay)")]
        public GLib.Variant icon_pixmap {
            owned get {
                return empty_pixmaps ();
            }
        }

        public string overlay_icon_name {
            owned get {
                return "";
            }
        }

        [DBus (signature = "a(iiay)")]
        public GLib.Variant overlay_icon_pixmap {
            owned get {
                return empty_pixmaps ();
            }
        }

        public string attention_icon_name {
            owned get {
                return @"$(Config.APPLICATION_ID)-symbolic";
            }
        }

        [DBus (signature = "a(iiay)")]
        public GLib.Variant attention_icon_pixmap {
            owned get {
                return empty_pixmaps ();
            }
        }

        public string attention_movie_name {
            owned get {
                return "";
            }
        }

        [DBus (name = "ToolTip", signature = "(sa(iiay)ss)")]
        public GLib.Variant tooltip {
            owned get {
                return new GLib.Variant.tuple ({
                    new GLib.Variant.string (Config.APPLICATION_ID),
                    empty_pixmaps (),
                    new GLib.Variant.string (Config.APPLICATION_NAME),
                    new GLib.Variant.string ("Open Tomodoro")
                });
            }
        }

        public void context_menu (int32 x, int32 y) throws GLib.DBusError, GLib.IOError
        {
        }

        public void activate (int32 x, int32 y) throws GLib.DBusError, GLib.IOError
        {
            this.activated ();
        }

        public void secondary_activate (int32 x, int32 y) throws GLib.DBusError, GLib.IOError
        {
            this.activated ();
        }

        public void scroll (int32 delta, string orientation) throws GLib.DBusError, GLib.IOError
        {
        }

        public signal void new_title ();
        public signal void new_icon ();
        public signal void new_attention_icon ();
        public signal void new_status ();
        public signal void new_menu ();

        [DBus (name = "NewToolTip")]
        public signal void new_tooltip ();

        [DBus (visible = false)]
        public signal void activated ();

        private static GLib.Variant empty_pixmaps ()
        {
            return new GLib.Variant.array (new GLib.VariantType ("(iiay)"), {});
        }
    }

    [DBus (name = "com.canonical.dbusmenu")]
    private class IndicatorMenu : GLib.Object
    {
        private const int32 ROOT_ID = 0;
        private const int32 OPEN_ID = 1;
        private const int32 NEW_ID = 2;
        private const int32 FIRST_SEPARATOR_ID = 3;
        private const int32 TOGGLE_TIMER_ID = 4;
        private const int32 DONE_ID = 5;
        private const int32 SECOND_SEPARATOR_ID = 6;
        private const int32 QUIT_ID = 7;

        private GLib.Application application;
        private uint32 revision = 1;

        public uint32 version {
            get {
                return 4;
            }
        }

        public string status {
            owned get {
                return "normal";
            }
        }

        public string[] icon_theme_path {
            owned get {
                return {};
            }
        }

        public string text_direction {
            owned get {
                return Gtk.Widget.get_default_direction () == Gtk.TextDirection.RTL ? "rtl" : "ltr";
            }
        }

        public IndicatorMenu (GLib.Application application)
        {
            this.application = application;
        }

        public void get_layout (int32 parent_id,
                                int32 recursion_depth,
                                string[] property_names,
                                out uint32 revision,
                                [DBus (signature = "(ia{sv}av)")] out GLib.Variant layout)
                                throws GLib.DBusError, GLib.IOError
        {
            if (!valid_id (parent_id)) {
                throw new GLib.DBusError.INVALID_ARGS ("Unknown menu item");
            }

            revision = this.revision;
            layout = serialize_layout (parent_id, recursion_depth, property_names);
        }

        [DBus (name = "GetProperty", signature = "v")]
        public GLib.Variant get_property_ (int32 id, string name) throws GLib.DBusError, GLib.IOError
        {
            if (!valid_id (id)) {
                throw new GLib.DBusError.INVALID_ARGS ("Unknown menu item");
            }

            var value = property_value (id, name);
            if (value == null) {
                throw new GLib.DBusError.INVALID_ARGS ("Unknown property");
            }

            return new GLib.Variant.variant (value);
        }

        [DBus (signature = "a(ia{sv})")]
        public GLib.Variant get_group_properties (int32[] ids, string[] property_names)
                                                   throws GLib.DBusError, GLib.IOError
        {
            var builder = new GLib.VariantBuilder (new GLib.VariantType ("a(ia{sv})"));

            foreach (var id in ids) {
                if (!valid_id (id)) {
                    continue;
                }

                builder.add_value (
                    new GLib.Variant.tuple ({
                        new GLib.Variant.int32 (id),
                        properties_for (id, property_names)
                    })
                );
            }

            return builder.end ();
        }

        public void event (int32 id,
                           string event_id,
                           GLib.Variant data,
                           uint32 timestamp) throws GLib.DBusError, GLib.IOError
        {
            handle_event (id, event_id);
        }

        public int32[] event_group ([DBus (signature = "a(isvu)")] GLib.Variant events)
                                    throws GLib.DBusError, GLib.IOError
        {
            int32 id;
            string event_id;
            GLib.Variant data;
            uint32 timestamp;

            for (var index = 0; index < events.n_children (); index++) {
                var event = events.get_child_value (index);
                event.get ("(isvu)", out id, out event_id, out data, out timestamp);
                handle_event (id, event_id);
            }

            return {};
        }

        public bool about_to_show (int32 id) throws GLib.DBusError, GLib.IOError
        {
            return false;
        }

        public void about_to_show_group (int32[] ids,
                                         out int32[] updates_needed,
                                         out int32[] id_errors) throws GLib.DBusError, GLib.IOError
        {
            updates_needed = new int32[ids.length];
            id_errors = new int32[ids.length];

            for (var index = 0; index < ids.length; index++) {
                updates_needed[index] = 0;
                id_errors[index] = valid_id (ids[index]) ? 0 : 1;
            }
        }

        public signal void items_properties_updated (
            [DBus (signature = "a(ia{sv})")] GLib.Variant updated_props,
            [DBus (signature = "a(ias)")] GLib.Variant removed_props);

        public signal void layout_updated (uint32 revision, int32 parent_id);
        public signal void item_activation_requested (int32 id, uint32 timestamp);

        private GLib.Variant serialize_layout (int32 id, int32 recursion_depth, string[] property_names)
        {
            var children = new GLib.VariantBuilder (new GLib.VariantType ("av"));
            if (id == ROOT_ID && recursion_depth != 0) {
                int32[] child_ids = {OPEN_ID, NEW_ID, FIRST_SEPARATOR_ID, TOGGLE_TIMER_ID, DONE_ID, SECOND_SEPARATOR_ID, QUIT_ID};
                foreach (var child_id in child_ids) {
                    children.add_value (new GLib.Variant.variant (
                        serialize_layout (child_id, recursion_depth - 1, property_names)));
                }
            }

            return new GLib.Variant.tuple ({
                new GLib.Variant.int32 (id),
                properties_for (id, property_names),
                children.end ()
            });
        }

        private GLib.Variant properties_for (int32 id, string[] property_names)
        {
            var builder = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));
            string[] names = property_names;
            if (names.length == 0) {
                names = {"type", "label", "enabled", "visible", "children-display"};
            }

            foreach (var name in names) {
                var value = property_value (id, name);
                if (value != null) {
                    builder.add ("{sv}", name, value);
                }
            }

            return builder.end ();
        }

        private GLib.Variant? property_value (int32 id, string name)
        {
            switch (name) {
                case "type":
                    return new GLib.Variant.string (is_separator (id) ? "separator" : "standard");
                case "label":
                    return new GLib.Variant.string (label_for_id (id));
                case "enabled":
                    return new GLib.Variant.boolean (true);
                case "visible":
                    return new GLib.Variant.boolean (true);
                case "children-display":
                    return id == ROOT_ID ? new GLib.Variant.string ("submenu") : null;
                case "icon-name":
                    return new GLib.Variant.string ("");
                default:
                    return null;
            }
        }

        private string label_for_id (int32 id)
        {
            switch (id) {
                case OPEN_ID:
                    return "Open";
                case NEW_ID:
                    return "New";
                case TOGGLE_TIMER_ID:
                    return "Pause/Start";
                case DONE_ID:
                    return "Done";
                case QUIT_ID:
                    return "Quit";
                default:
                    return "";
            }
        }

        private bool valid_id (int32 id)
        {
            return id >= ROOT_ID && id <= QUIT_ID;
        }

        private bool is_separator (int32 id)
        {
            return id == FIRST_SEPARATOR_ID || id == SECOND_SEPARATOR_ID;
        }

        private void handle_event (int32 id, string event_id) throws GLib.DBusError
        {
            if (event_id != "clicked") {
                return;
            }

            switch (id) {
                case OPEN_ID:
                    this.application.activate_action ("indicator-open", null);
                    break;
                case NEW_ID:
                    this.application.activate_action ("indicator-new", null);
                    break;
                case TOGGLE_TIMER_ID:
                    this.application.activate_action ("timer-toggle", null);
                    break;
                case DONE_ID:
                    this.application.activate_action ("timer-done", null);
                    break;
                case QUIT_ID:
                    this.application.activate_action ("indicator-quit", null);
                    break;
                default:
                    throw new GLib.DBusError.INVALID_ARGS ("Unknown menu item");
            }
        }
    }

    private class StatusIndicator : GLib.Object
    {
        private unowned GLib.Application application;
        private GLib.DBusConnection? connection = null;
        private StatusNotifierItem? item = null;
        private IndicatorMenu? menu = null;
        private uint object_id = 0;
        private uint menu_object_id = 0;
        private uint watcher_id = 0;

        public StatusIndicator (GLib.Application application)
        {
            this.application = application;
        }

        public void start ()
        {
            if (this.object_id != 0) {
                return;
            }

            try {
                this.connection = this.application.get_dbus_connection ();
                if (this.connection == null) {
                    GLib.warning ("Unable to export StatusNotifier item before application bus registration");
                    return;
                }
                this.menu = new IndicatorMenu (this.application);
                this.menu_object_id = this.connection.register_object<IndicatorMenu> (SNI_MENU_PATH, this.menu);

                this.item = new StatusNotifierItem (SNI_MENU_PATH);
                this.item.activated.connect (() => {
                    this.application.activate ();
                });
                this.object_id = this.connection.register_object<StatusNotifierItem> (SNI_ITEM_PATH, this.item);
            } catch (GLib.Error error) {
                GLib.warning ("Unable to export StatusNotifier item: %s", error.message);
                return;
            }

            this.watcher_id = GLib.Bus.watch_name (
                GLib.BusType.SESSION,
                SNI_WATCHER_NAME,
                GLib.BusNameWatcherFlags.NONE,
                on_watcher_appeared,
                on_watcher_vanished
            );
        }

        public void stop ()
        {
            if (this.watcher_id != 0) {
                GLib.Bus.unwatch_name (this.watcher_id);
                this.watcher_id = 0;
            }

            if (this.connection != null && this.object_id != 0) {
                this.connection.unregister_object (this.object_id);
                this.object_id = 0;
            }

            if (this.connection != null && this.menu_object_id != 0) {
                this.connection.unregister_object (this.menu_object_id);
                this.menu_object_id = 0;
            }

            this.item = null;
            this.menu = null;
            this.connection = null;
        }

        private void on_watcher_appeared (GLib.DBusConnection connection, string name, string name_owner)
        {
            try {
                var watcher = GLib.Bus.get_proxy_sync<StatusNotifierWatcher> (
                    GLib.BusType.SESSION,
                    SNI_WATCHER_NAME,
                    SNI_WATCHER_PATH
                );
                watcher.register_status_notifier_item (SNI_ITEM_PATH);
            } catch (GLib.Error error) {
                GLib.warning ("Unable to register StatusNotifier item: %s", error.message);
            }
        }

        private void on_watcher_vanished (GLib.DBusConnection connection, string name)
        {
        }
    }
}
