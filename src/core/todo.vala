namespace Tomodoro
{
    public const string[] PRIORITY_OPTIONS = {"A", "B", "C", "D", "E", "F", "G", "H"};
    public const int TODO_SUMMARY_MAX_CHARS = 37;
    public const string RECURRENCE_NONE = "";
    public const string RECURRENCE_DAILY = "daily";
    public const string RECURRENCE_WEEKLY = "weekly";
    public const string RECURRENCE_MONTHLY = "monthly";
    public const string[] RECURRENCE_OPTIONS = {"", "daily", "weekly", "monthly"};
    public const string[] RECURRENCE_WEEKDAY_TOKENS = {"mon", "tue", "wed", "thu", "fri", "sat", "sun"};
    public const string[] RECURRENCE_WEEKDAY_LABELS = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
    public const string[] RECURRENCE_WEEKDAY_FULL_LABELS = {"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"};
    public const string[] RECURRENCE_WEEKDAY_PLURAL_LABELS = {"Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays"};

    public class Todo : GLib.Object
    {
        public string id { get; set; default = ""; }
        public string body { get; set; default = ""; }
        public string priority { get; set; default = "C"; }
        public string due { get; set; default = ""; }
        public string project { get; set; default = "Inbox"; }
        public int pm { get; set; default = 0; }
        public int pm_done { get; set; default = 0; }
        public bool completed { get; set; default = false; }
        public string dependency_id { get; set; default = ""; }
        public string recurrence { get; set; default = ""; }
        public int recurrence_anchor_day { get; set; default = 0; }
        public string recurrence_weekdays { get; set; default = ""; }
        public string recurrence_parent_id { get; set; default = ""; }
        public string recurrence_latest_due { get; set; default = ""; }

        internal string[] extra_tags = {};

        public string root_project
        {
            owned get { return project_root (this.project); }
        }

        public int remaining_pm
        {
            get { return int.max (0, this.pm); }
        }

        public bool recurring
        {
            get { return is_recurrence (this.recurrence); }
        }

        public bool recurring_instance
        {
            get { return this.recurrence_parent_id != ""; }
        }

        public Todo copy ()
        {
            var result = new Todo ();
            result.id = this.id;
            result.body = this.body;
            result.priority = this.priority;
            result.due = this.due;
            result.project = this.project;
            result.pm = this.pm;
            result.pm_done = this.pm_done;
            result.completed = this.completed;
            result.dependency_id = this.dependency_id;
            result.recurrence = this.recurrence;
            result.recurrence_anchor_day = this.recurrence_anchor_day;
            result.recurrence_weekdays = this.recurrence_weekdays;
            result.recurrence_parent_id = this.recurrence_parent_id;
            result.recurrence_latest_due = this.recurrence_latest_due;
            foreach (var tag in this.extra_tags) {
                result.add_extra_tag (tag);
            }
            return result;
        }

        public string[] get_extra_tags ()
        {
            return this.extra_tags;
        }

        public void add_extra_tag (string tag)
        {
            this.extra_tags += tag;
        }

        public string calendar_uid ()
        {
            foreach (var tag in this.extra_tags) {
                if (tag.has_prefix ("cal-uid:")) {
                    return tag.substring (8).strip ();
                }
            }
            return "";
        }

        public void set_calendar_uid (string uid)
        {
            set_extra_tag ("cal-uid", uid.strip ());
        }

        public void clear_calendar_uid ()
        {
            remove_extra_tag ("cal-uid");
        }

        public int previous_pm_or_default (int fallback = 1)
        {
            foreach (var tag in this.extra_tags) {
                if (tag.has_prefix ("pm-prev:")) {
                    return int.max (1, parse_int_safe (tag.substring (8), fallback));
                }
            }
            return int.max (1, fallback);
        }

        public void remember_pm_before_completion (int value)
        {
            if (value > 0) {
                set_extra_tag ("pm-prev", "%d".printf (value));
            }
        }

        public void clear_previous_pm ()
        {
            remove_extra_tag ("pm-prev");
        }

        public void complete_with_zero_pm ()
        {
            remember_pm_before_completion (this.pm);
            this.pm = 0;
            this.completed = true;
        }

        public void restore_pm_after_completion ()
        {
            var restored = this.pm > 0 ? this.pm : previous_pm_or_default (1);
            this.pm = int.max (1, restored);
            this.completed = false;
            clear_previous_pm ();
        }

        public void finish_pomodoro ()
        {
            this.pm_done += 1;
            if (this.pm > 0) {
                this.pm -= 1;
            }
            if (this.pm == 0) {
                this.completed = true;
            }
        }

        public string to_line ()
        {
            string[] pieces = {};
            if (this.pm == 0) {
                pieces += "x";
            }
            if (this.priority != "") {
                pieces += "(%s)".printf (this.priority);
            }
            pieces += normalize_body_text (this.body);
            if (this.project != "") {
                pieces += "+%s".printf (normalize_project (this.project, "Inbox"));
            }
            if (this.due != "") {
                pieces += "due:%s".printf (this.due);
            }
            pieces += "pm:%d".printf (int.max (0, this.pm));
            pieces += "pm-done:%d".printf (int.max (0, this.pm_done));
            if (this.id != "") {
                pieces += "id:%s".printf (this.id);
            }
            if (this.dependency_id != "") {
                pieces += "dep:%s".printf (this.dependency_id);
            }
            if (this.recurrence_parent_id != "") {
                pieces += "recur-parent:%s".printf (this.recurrence_parent_id);
            }
            if (is_recurrence (this.recurrence)) {
                pieces += "recur:%s".printf (this.recurrence);
            }
            if (this.recurrence == RECURRENCE_MONTHLY && this.recurrence_anchor_day >= 1 && this.recurrence_anchor_day <= 31) {
                pieces += "recur-day:%d".printf (this.recurrence_anchor_day);
            }
            if (this.recurrence == RECURRENCE_WEEKLY && this.recurrence_weekdays != "") {
                pieces += "recur-days:%s".printf (this.recurrence_weekdays);
            }
            if (this.recurring && this.recurrence_latest_due != "") {
                pieces += "recur-latest:%s".printf (this.recurrence_latest_due);
            }
            foreach (var tag in this.extra_tags) {
                if (!is_known_tag (tag)) {
                    pieces += tag;
                }
            }
            return string.joinv (" ", pieces);
        }

        public bool same_identity (Todo other)
        {
            return compact_text (this.body).down () == compact_text (other.body).down ()
                && this.priority == other.priority
                && this.due == other.due
                && this.project == other.project
                && this.pm == other.pm
                && this.recurrence == other.recurrence
                && this.recurrence_anchor_day == other.recurrence_anchor_day
                && this.recurrence_weekdays == other.recurrence_weekdays
                && this.recurrence_parent_id == other.recurrence_parent_id
                && this.recurrence_latest_due == other.recurrence_latest_due;
        }

        public bool same_id (Todo other)
        {
            return this.id != "" && this.id == other.id;
        }

        private void set_extra_tag (string key, string value)
        {
            remove_extra_tag (key);
            this.extra_tags += "%s:%s".printf (key, value);
        }

        private void remove_extra_tag (string key)
        {
            string[] next = {};
            var prefix = "%s:".printf (key);
            foreach (var tag in this.extra_tags) {
                if (!tag.has_prefix (prefix)) {
                    next += tag;
                }
            }
            this.extra_tags = next;
        }
    }

    public Todo? parse_todo (string line, string default_project = "Inbox")
    {
        var raw = line.strip ();
        if (raw == "") {
            return null;
        }

        var todo = new Todo ();
        todo.project = sanitize_todo_project (default_project, "Inbox");

        if (raw.has_prefix ("x ")) {
            todo.completed = true;
            raw = raw.substring (2).strip ();
        }

        if (raw.length >= 4 && raw[0] == '(' && raw[2] == ')' && raw[3] == ' ') {
            var value = raw.substring (1, 1).up ();
            if (is_priority (value)) {
                todo.priority = value;
                raw = raw.substring (4).strip ();
            }
        }

        string[] body_parts = {};
        foreach (var token in raw.split (" ")) {
            var part = token.strip ();
            if (part == "") {
                continue;
            }
            if (part.has_prefix ("+") && part.length > 1) {
                todo.project = sanitize_todo_project (part.substring (1), default_project);
                continue;
            }
            if (part.index_of (":") > 0 && is_tag_token (part)) {
                var separator = part.index_of (":");
                var key = part.substring (0, separator);
                var value = part.substring (separator + 1);
                switch (key)
                {
                    case "due":
                        todo.due = is_valid_date (value) ? value : "";
                        break;

                    case "pm":
                        todo.pm = int.max (0, parse_int_safe (value, 0));
                        break;

                    case "pm-done":
                        todo.pm_done = int.max (0, parse_int_safe (value, 0));
                        break;

                    case "id":
                        todo.id = is_valid_todo_id (value) ? value.down () : "";
                        break;

                    case "dep":
                        todo.dependency_id = is_valid_todo_id (value) ? value.down () : "";
                        break;

                    case "recur-parent":
                        todo.recurrence_parent_id = is_valid_todo_id (value) ? value.down () : "";
                        break;

                    case "recur":
                        todo.recurrence = recurrence_kind (value);
                        break;

                    case "recur-day":
                        todo.recurrence_anchor_day = int.max (0, parse_int_safe (value, 0));
                        break;

                    case "recur-days":
                        todo.recurrence_weekdays = sanitize_recurrence_weekdays (value);
                        break;

                    case "recur-latest":
                        todo.recurrence_latest_due = is_valid_date (value) ? value : "";
                        break;

                    default:
                        todo.add_extra_tag (part);
                        break;
                }
                continue;
            }
            body_parts += part;
        }

        todo.completed = todo.pm == 0;
        todo.body = normalize_body_text (string.joinv (" ", body_parts));
        return todo.body == "" ? null : todo;
    }

    public string new_todo_id ()
    {
        return GLib.Uuid.string_random ();
    }

    public bool is_valid_todo_id (string value)
    {
        var clean = value.strip ();
        if (clean.length < 8 || clean.length > 64) {
            return false;
        }
        for (int index = 0; index < clean.length; index++) {
            var ch = clean[index];
            var valid = (ch >= 'A' && ch <= 'Z')
                || (ch >= 'a' && ch <= 'z')
                || (ch >= '0' && ch <= '9')
                || ch == '-'
                || ch == '_';
            if (!valid) {
                return false;
            }
        }
        return true;
    }

    public bool todo_has_dependency (Todo todo)
    {
        return todo.dependency_id != "" && is_valid_todo_id (todo.dependency_id);
    }

    public bool is_priority (string value)
    {
        foreach (var priority in PRIORITY_OPTIONS) {
            if (priority == value) {
                return true;
            }
        }
        return false;
    }

    public int priority_rank (string priority)
    {
        if (priority == "" || priority == "0") {
            return 99;
        }
        return int.max (0, priority[0] - 'A');
    }

    public string highest_priority (Todo[] todos)
    {
        var best = "0";
        foreach (var todo in todos) {
            if (todo.completed) {
                continue;
            }
            if (best == "0" || priority_rank (todo.priority) < priority_rank (best)) {
                best = todo.priority;
            }
        }
        return best;
    }

    public string priority_color (string priority)
    {
        switch (priority)
        {
            case "A": return "#a51d2d";
            case "B": return "#c01c28";
            case "C": return "#ff7800";
            case "D": return "#f6d32d";
            case "E": return "#33d17a";
            case "F": return "#3584e4";
            case "G": return "#9141ac";
            case "H": return "#9a9996";
            default: return "#9a9996";
        }
    }

    public string compact_text (string text)
    {
        string[] pieces = {};
        foreach (var part in text.strip ().split (" ")) {
            if (part.strip () != "") {
                pieces += part.strip ();
            }
        }
        return string.joinv (" ", pieces);
    }

    public string trim_text_to_word (string text, int limit)
    {
        var clean = compact_text (text);
        if (clean.length <= limit) {
            return clean;
        }

        var target = int.max (0, limit);
        var word_end = -1;
        for (int index = 0; index < target && index < clean.length; index++) {
            var ch = clean[index];
            if (ch == ' ' || ch == '\t') {
                word_end = index;
            }
        }
        if (word_end > 0) {
            target = word_end;
        }
        return clean.substring (0, target).strip ();
    }

    public bool has_explicit_todo_summary (string body)
    {
        return compact_text (body).index_of (". ") >= 0;
    }

    public string todo_body_summary (string body)
    {
        var clean = compact_text (body);
        var phrase_end = clean.index_of (". ");
        if (phrase_end < 0) {
            return clean;
        }
        return clean.substring (0, phrase_end + 1).strip ();
    }

    public string todo_display_summary (Todo todo, int limit = TODO_SUMMARY_MAX_CHARS)
    {
        return trim_text_to_word (todo_body_summary (todo.body), limit);
    }

    private bool is_tag_token (string token)
    {
        var separator = token.index_of (":");
        if (separator <= 0 || separator >= token.length - 1) {
            return false;
        }
        var key = token.substring (0, separator);
        for (int index = 0; index < key.length; index++) {
            var ch = key[index];
            var valid = (ch >= 'A' && ch <= 'Z')
                || (ch >= 'a' && ch <= 'z')
                || (ch >= '0' && ch <= '9')
                || ch == '_'
                || ch == '-';
            if (!valid) {
                return false;
            }
        }
        return true;
    }

    public bool is_recurrence (string value)
    {
        return recurrence_kind (value) != RECURRENCE_NONE;
    }

    public string recurrence_kind (string value)
    {
        var clean = value.strip ().down ();
        switch (clean)
        {
            case RECURRENCE_DAILY:
            case RECURRENCE_WEEKLY:
            case RECURRENCE_MONTHLY:
                return clean;
            default:
                return RECURRENCE_NONE;
        }
    }

    public string recurrence_label (string value)
    {
        switch (recurrence_kind (value))
        {
            case RECURRENCE_DAILY:
                return "Daily";
            case RECURRENCE_WEEKLY:
                return "Weekly";
            case RECURRENCE_MONTHLY:
                return "Monthly";
            default:
                return "None";
        }
    }

    public string recurrence_schedule_label (Todo todo)
    {
        switch (recurrence_kind (todo.recurrence))
        {
            case RECURRENCE_DAILY:
                return "Daily";

            case RECURRENCE_WEEKLY:
                return recurring_weekly_schedule_label (todo.recurrence_weekdays);

            case RECURRENCE_MONTHLY:
                return ordinal_day (int.max (1, int.min (31, todo.recurrence_anchor_day)));

            default:
                return "Not recurring";
        }
    }

    public string sanitize_recurrence_weekdays (string value)
    {
        bool[] selected = {false, false, false, false, false, false, false};
        foreach (var part in value.down ().split (",")) {
            var clean = part.strip ();
            for (var index = 0; index < RECURRENCE_WEEKDAY_TOKENS.length; index++) {
                if (clean == RECURRENCE_WEEKDAY_TOKENS[index]) {
                    selected[index] = true;
                }
            }
        }
        string[] result = {};
        for (var index = 0; index < RECURRENCE_WEEKDAY_TOKENS.length; index++) {
            if (selected[index]) {
                result += RECURRENCE_WEEKDAY_TOKENS[index];
            }
        }
        return string.joinv (",", result);
    }

    public string recurrence_weekday_labels (string value)
    {
        var weekdays = sanitize_recurrence_weekdays (value);
        if (weekdays == "") {
            return "";
        }
        string[] labels = {};
        foreach (var token in weekdays.split (",")) {
            for (var index = 0; index < RECURRENCE_WEEKDAY_TOKENS.length; index++) {
                if (token == RECURRENCE_WEEKDAY_TOKENS[index]) {
                    labels += RECURRENCE_WEEKDAY_LABELS[index];
                }
            }
        }
        return string.joinv (", ", labels);
    }

    public string recurring_weekly_schedule_label (string value)
    {
        var weekdays = sanitize_recurrence_weekdays (value);
        if (weekdays == "") {
            return "Weekly";
        }
        string[] full = {};
        string[] short = {};
        foreach (var token in weekdays.split (",")) {
            for (var index = 0; index < RECURRENCE_WEEKDAY_TOKENS.length; index++) {
                if (token == RECURRENCE_WEEKDAY_TOKENS[index]) {
                    full += RECURRENCE_WEEKDAY_PLURAL_LABELS[index];
                    short += RECURRENCE_WEEKDAY_LABELS[index];
                }
            }
        }
        if (full.length == 1) {
            return full[0];
        }
        if (full.length == 2) {
            return "%s and %s".printf (full[0], full[1]);
        }
        return "Every %s".printf (string.joinv (", ", short));
    }

    public bool recurrence_weekday_enabled (string weekdays, int weekday_index)
    {
        if (weekday_index < 0 || weekday_index >= RECURRENCE_WEEKDAY_TOKENS.length) {
            return false;
        }
        foreach (var token in sanitize_recurrence_weekdays (weekdays).split (",")) {
            if (token == RECURRENCE_WEEKDAY_TOKENS[weekday_index]) {
                return true;
            }
        }
        return false;
    }

    public string weekday_token_for_date (DateTime date)
    {
        var index = int.max (1, int.min (7, date.get_day_of_week ())) - 1;
        return RECURRENCE_WEEKDAY_TOKENS[index];
    }

    public string recurring_instance_body (Todo template, string due)
    {
        return normalize_body_text (template.body);
    }

    public string ordinal_day (int day)
    {
        var clean = int.max (1, int.min (31, day));
        var suffix = "th";
        var mod_100 = clean % 100;
        if (mod_100 < 11 || mod_100 > 13) {
            switch (clean % 10)
            {
                case 1:
                    suffix = "st";
                    break;
                case 2:
                    suffix = "nd";
                    break;
                case 3:
                    suffix = "rd";
                    break;
            }
        }
        return "%d%s".printf (clean, suffix);
    }

    private bool is_known_tag (string token)
    {
        return token.has_prefix ("due:")
            || token.has_prefix ("pm:")
            || token.has_prefix ("pm-done:")
            || token.has_prefix ("id:")
            || token.has_prefix ("dep:")
            || token.has_prefix ("recur-parent:")
            || token.has_prefix ("recur:")
            || token.has_prefix ("recur-day:")
            || token.has_prefix ("recur-days:")
            || token.has_prefix ("recur-latest:");
    }
}
