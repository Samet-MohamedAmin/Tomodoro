namespace Tomodoro
{
    private const string CALENDAR_UID_TAG_PREFIX = "tomodoro-";
    private const string CALENDAR_UID_DOMAIN = "io.github.samet_mohamedamin.Tomodoro";
    private const int RECURRENCE_CALENDAR_DAYS = 40;

    public class CalendarSync : GLib.Object
    {
        public static Todo[] prepare_for_save (Todo[] previous, Todo[] current)
        {
            Todo[] removed = {};
            var current_by_id = new GLib.HashTable<string, Todo> (GLib.str_hash, GLib.str_equal);
            var current_active_recurring_instances = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
            var removed_uids = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);

            foreach (var todo in current) {
                if (todo.id != "") {
                    current_by_id.insert (todo.id, todo);
                }
                if (todo.recurring_instance && !todo.completed && is_valid_date (todo.due)) {
                    var key = recurring_instance_key (todo.recurrence_parent_id, todo.due);
                    current_active_recurring_instances.insert (key, key);
                }

                if (calendar_todo_active (todo)) {
                    if (todo.recurring) {
                        var uid = todo.calendar_uid ();
                        if (uid != "") {
                            removed = add_removed_uid (removed, removed_uids, todo, uid);
                            todo.clear_calendar_uid ();
                        }
                    }
                    else if (todo.calendar_uid () == "") {
                        todo.set_calendar_uid (calendar_uid_for_todo (todo));
                    }
                }
                else if (todo.calendar_uid () != "") {
                    var uid = calendar_uid_for_existing_todo (todo);
                    removed = add_removed_uid (removed, removed_uids, todo, uid);
                    todo.clear_calendar_uid ();
                }
            }

            foreach (var todo in previous) {
                var current_todo = todo.id == "" ? null : current_by_id.lookup (todo.id);
                if (todo.recurring_instance) {
                    var key = recurring_instance_key (todo.recurrence_parent_id, todo.due);
                    if (!todo.completed
                        && is_valid_date (todo.due)
                        && current_active_recurring_instances.lookup (key) == null) {
                        removed = add_removed_recurring_instance_event (removed, removed_uids, todo);
                    }
                    continue;
                }
                if (todo.recurring) {
                    if (recurring_events_should_be_removed (todo, current_todo)) {
                        removed = add_removed_recurring_events (removed, removed_uids, todo);
                    }
                    var base_uid = todo.calendar_uid ();
                    if (base_uid != "" && (current_todo == null || current_todo.calendar_uid () == "")) {
                        removed = add_removed_uid (removed, removed_uids, todo, base_uid);
                    }
                    continue;
                }

                var uid = calendar_uid_for_existing_todo (todo);
                if (uid == "") {
                    continue;
                }

                if (current_todo == null || !calendar_todo_active (current_todo) || current_todo.recurring) {
                    removed = add_removed_uid (removed, removed_uids, todo, uid);
                }
            }

            return removed;
        }

        public static Todo[] prepare_remove_all (Todo[] todos)
        {
            Todo[] removed = {};
            var removed_uids = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);

            foreach (var todo in todos) {
                if (todo.recurring_instance) {
                    removed = add_removed_recurring_instance_event (removed, removed_uids, todo);
                }
                else if (todo.recurring) {
                    removed = add_removed_recurring_events (removed, removed_uids, todo);
                }
                else {
                    var uid = calendar_uid_for_existing_todo (todo);
                    if (uid == "" && todo.id != "" && is_valid_date (todo.due)) {
                        uid = calendar_uid_for_todo (todo);
                    }
                    removed = add_removed_uid (removed, removed_uids, todo, uid);
                }

                var stored_uid = todo.calendar_uid ();
                if (stored_uid != "") {
                    removed = add_removed_uid (removed, removed_uids, todo, stored_uid);
                    todo.clear_calendar_uid ();
                }
            }

            return removed;
        }

        public static void schedule_context_sync (string context_name, Todo[] current, Todo[] removed)
        {
            if (!sync_enabled ()) {
                return;
            }

            var context_copy = context_name;
            var current_copy = copy_todos (current);
            var removed_copy = copy_todos (removed);

            new GLib.Thread<bool> (
                "tomodoro-calendar-sync",
                () => {
                    sync_context (context_copy, current_copy, removed_copy);
                    return true;
                });
        }

        private static bool sync_enabled ()
        {
            return GLib.Environment.get_variable ("TOMODORO_DISABLE_CALENDAR_SYNC") != "1";
        }

        private static Todo[] copy_todos (Todo[] todos)
        {
            Todo[] result = {};
            foreach (var todo in todos) {
                result += todo.copy ();
            }
            return result;
        }

        private static void sync_context (string context_name, Todo[] current, Todo[] removed)
        {
            try {
                var client = connect_calendar ();

                foreach (var todo in removed) {
                    remove_event (client, todo.calendar_uid ());
                }

                foreach (var todo in current) {
                    if (!calendar_todo_active (todo)) {
                        continue;
                    }
                    if (todo.recurring) {
                        foreach (var instance in recurring_event_instances (todo, current)) {
                            upsert_event (client, context_name, instance);
                        }
                    }
                    else if (todo.calendar_uid () != "") {
                        upsert_event (client, context_name, todo);
                    }
                }
            }
            catch (GLib.Error error) {
                warning ("Calendar sync failed: %s", error.message);
            }
        }

        private static ECal.Client connect_calendar () throws GLib.Error
        {
            var registry = new E.SourceRegistry.sync (null);
            E.Source? source = registry.ref_default_calendar ();
            if (source == null || !registry.check_enabled (source) || !source.get_writable ()) {
                source = first_writable_calendar (registry);
            }

            if (source == null) {
                throw new GLib.IOError.NOT_FOUND ("No writable calendar source found");
            }

            var client = ECal.Client.connect_sync (source, ECal.ClientSourceType.EVENTS, 5, null) as ECal.Client;
            if (client == null) {
                throw new GLib.IOError.FAILED ("Could not connect to the default calendar");
            }
            return client;
        }

        private static E.Source? first_writable_calendar (E.SourceRegistry registry)
        {
            var sources = registry.list_enabled (E.SOURCE_EXTENSION_CALENDAR);
            for (unowned GLib.List<E.Source> item = sources; item != null; item = item.next) {
                var source = item.data;
                if (source != null && source.get_writable ()) {
                    return source;
                }
            }
            return null;
        }

        private static void upsert_event (ECal.Client client, string context_name, Todo todo)
        {
            var uid = todo.calendar_uid ();
            var component = event_component (context_name, todo, uid);

            try {
                ICal.Component existing;
                client.get_object_sync (uid, null, out existing, null);
                client.modify_object_sync (
                    component,
                    ECal.ObjModType.THIS,
                    ECal.OperationFlags.CONFLICT_KEEP_LOCAL,
                    null);
            }
            catch (GLib.Error get_error) {
                try {
                    string? created_uid = null;
                    client.create_object_sync (
                        component,
                        ECal.OperationFlags.CONFLICT_KEEP_LOCAL,
                        out created_uid,
                        null);
                }
                catch (GLib.Error create_error) {
                    warning ("Could not sync calendar event for '%s': %s", todo.body, create_error.message);
                }
            }
        }

        private static void remove_event (ECal.Client client, string uid)
        {
            if (uid == "") {
                return;
            }

            try {
                client.remove_object_sync (
                    uid,
                    null,
                    ECal.ObjModType.THIS,
                    ECal.OperationFlags.NONE,
                    null);
            }
            catch (GLib.Error error) {
                debug ("Could not remove calendar event '%s': %s", uid, error.message);
            }
        }

        private static ICal.Component event_component (string context_name, Todo todo, string uid)
        {
            var component = new ICal.Component.vevent ();
            component.set_uid (uid);
            component.set_summary (event_summary (context_name, todo));
            component.set_description (event_description (context_name, todo));
            component.set_dtstamp (new ICal.Time.current_with_zone (ICal.Timezone.get_utc_timezone ()));
            component.set_dtstart (ical_date (todo.due, 0));
            component.set_dtend (ical_date (todo.due, 1));
            component.set_status (ICal.PropertyStatus.CONFIRMED);
            component.add_property (new ICal.Property.categories ("Tomodoro"));
            component.add_property (new ICal.Property.transp (ICal.PropertyTransp.TRANSPARENT));
            return component;
        }

        public static string event_summary (string context_name, Todo todo)
        {
            var context = context_name.strip ();
            var summary = todo_body_summary (todo.body);
            if (context == "") {
                return summary;
            }
            if (summary == "") {
                return context;
            }
            return "%s: %s".printf (context, summary);
        }

        private static ICal.Time ical_date (string date, int days_offset)
        {
            var year = parse_int_safe (date.substring (0, 4), 1970);
            var month = parse_int_safe (date.substring (5, 2), 1);
            var day = parse_int_safe (date.substring (8, 2), 1);
            var time = new ICal.Time ();
            time.set_date (year, month, day);
            time.set_time (0, 0, 0);
            time.set_is_date (true);
            if (days_offset != 0) {
                time.adjust (days_offset, 0, 0, 0);
            }
            return time;
        }

        private static string event_description (string context_name, Todo todo)
        {
            return "Tomodoro todo\nContext: %s\nProject: %s\nPriority: %s\nPomodoros left: %d\nID: %s\n\n%s".printf (
                context_name,
                todo.project,
                todo.priority,
                todo.pm,
                todo.id,
                todo.body);
        }

        private static bool calendar_todo_active (Todo todo)
        {
            if (todo.recurring_instance) {
                return false;
            }
            if (todo.recurring) {
                return !todo.completed && todo.pm > 0;
            }
            return todo.due != "" && !todo.completed;
        }

        private static bool recurring_events_should_be_removed (Todo previous, Todo? current)
        {
            if (!calendar_todo_active (previous) || !previous.recurring) {
                return false;
            }
            if (current == null || !calendar_todo_active (current) || !current.recurring) {
                return true;
            }
            return previous.due != current.due
                || previous.recurrence != current.recurrence
                || previous.recurrence_anchor_day != current.recurrence_anchor_day
                || previous.recurrence_weekdays != current.recurrence_weekdays;
        }

        public static string[] recurring_event_dates (Todo todo)
        {
            string[] dates = {};
            if (!calendar_todo_active (todo) || !todo.recurring) {
                return dates;
            }

            if (!is_valid_date (todo.due)) {
                var today = today_local ();
                for (var offset = 0; offset < RECURRENCE_CALENDAR_DAYS; offset++) {
                    var date = today.add_days (offset);
                    if (recurring_template_matches_date (todo, date)) {
                        dates += date.format ("%F");
                    }
                }
                return dates;
            }

            var date = todo.due;
            for (var guard = 0; guard < 5000; guard++) {
                var delta = date_delta_days (date);
                if (delta >= RECURRENCE_CALENDAR_DAYS) {
                    break;
                }
                if (delta >= 0) {
                    dates += date;
                }

                var next_date = next_recurring_due (date, todo.recurrence, todo.recurrence_anchor_day);
                if (next_date == "" || next_date == date) {
                    break;
                }
                date = next_date;
            }
            return dates;
        }

        private static bool recurring_template_matches_date (Todo todo, DateTime date)
        {
            switch (todo.recurrence)
            {
                case RECURRENCE_DAILY:
                    return true;

                case RECURRENCE_WEEKLY:
                    return recurrence_weekday_enabled (todo.recurrence_weekdays, date.get_day_of_week () - 1);

                case RECURRENCE_MONTHLY:
                    var anchor = int.max (1, int.min (31, todo.recurrence_anchor_day));
                    var clamped = int.min (anchor, days_in_month (date.get_year (), date.get_month ()));
                    return date.get_day_of_month () == clamped;

                default:
                    return false;
            }
        }

        private static Todo[] recurring_event_instances (Todo todo, Todo[] current)
        {
            Todo[] instances = {};
            foreach (var date in recurring_event_dates (todo)) {
                if (!recurring_calendar_date_active (todo, current, date)) {
                    continue;
                }
                var instance = todo.copy ();
                instance.due = date;
                instance.body = recurring_instance_body (todo, date);
                instance.recurrence = RECURRENCE_NONE;
                instance.recurrence_parent_id = todo.id;
                instance.set_calendar_uid (recurring_calendar_uid_for_todo (todo, date));
                instances += instance;
            }
            return instances;
        }

        private static bool recurring_calendar_date_active (Todo template, Todo[] current, string due)
        {
            var latest = template.recurrence_latest_due;
            if (latest == "" || GLib.strcmp (due, latest) > 0) {
                return true;
            }

            foreach (var todo in current) {
                if (todo.recurring_instance
                    && todo.recurrence_parent_id == template.id
                    && todo.due == due) {
                    return !todo.completed;
                }
            }
            return false;
        }

        private static Todo[] add_removed_recurring_events (
            Todo[] removed,
            GLib.HashTable<string, string> removed_uids,
            Todo todo
        ) {
            var result = removed;
            foreach (var date in recurring_event_dates (todo)) {
                result = add_removed_uid (result, removed_uids, todo, recurring_calendar_uid_for_todo (todo, date), date);
            }
            return result;
        }

        private static Todo[] add_removed_recurring_instance_event (
            Todo[] removed,
            GLib.HashTable<string, string> removed_uids,
            Todo instance
        ) {
            if (instance.recurrence_parent_id == "" || !is_valid_date (instance.due)) {
                return removed;
            }
            var source = instance.copy ();
            source.id = instance.recurrence_parent_id;
            return add_removed_uid (
                removed,
                removed_uids,
                source,
                recurring_calendar_uid_for_todo (source, instance.due),
                instance.due
            );
        }

        private static Todo[] add_removed_uid (
            Todo[] removed,
            GLib.HashTable<string, string> removed_uids,
            Todo todo,
            string uid,
            string due = ""
        ) {
            if (uid == "" || removed_uids.lookup (uid) != null) {
                return removed;
            }

            var result = removed;
            result += removed_copy_with_uid (todo, uid, due);
            removed_uids.insert (uid, uid);
            return result;
        }

        private static string calendar_uid_for_todo (Todo todo)
        {
            return "%s%s@%s".printf (CALENDAR_UID_TAG_PREFIX, todo.id, CALENDAR_UID_DOMAIN);
        }

        private static string calendar_uid_for_existing_todo (Todo todo)
        {
            var uid = todo.calendar_uid ();
            if (uid != "") {
                return uid;
            }
            if (todo.id == "" || todo.due == "") {
                return "";
            }
            return calendar_uid_for_todo (todo);
        }

        private static string recurring_calendar_uid_for_todo (Todo todo, string due)
        {
            return "%s%s-%s@%s".printf (
                CALENDAR_UID_TAG_PREFIX,
                todo.id,
                compact_date_for_uid (due),
                CALENDAR_UID_DOMAIN
            );
        }

        private static string recurring_instance_key (string template_id, string due)
        {
            return "%s|%s".printf (template_id, due);
        }

        private static string compact_date_for_uid (string due)
        {
            var builder = new GLib.StringBuilder ();
            for (var index = 0; index < due.length; index++) {
                var ch = due[index];
                if (ch >= '0' && ch <= '9') {
                    builder.append_c (ch);
                }
            }
            return builder.str;
        }

        private static Todo removed_copy_with_uid (Todo todo, string uid, string due = "")
        {
            var result = todo.copy ();
            if (due != "") {
                result.due = due;
            }
            result.set_calendar_uid (uid);
            return result;
        }
    }
}
