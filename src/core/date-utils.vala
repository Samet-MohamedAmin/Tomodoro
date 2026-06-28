namespace Tomodoro
{
    public const int64 SECONDS_PER_DAY = 24 * 60 * 60;

    public DateTime today_local ()
    {
        var now = new DateTime.now_local ();
        return new DateTime.local (now.get_year (), now.get_month (), now.get_day_of_month (), 0, 0, 0);
    }

    public DateTime? parse_date (string value)
    {
        var text = value.strip ();
        int year;
        int month;
        int day;
        if (!parse_date_parts (text, out year, out month, out day)) {
            return null;
        }

        return new DateTime.local (year, month, day, 0, 0, 0);
    }

    public bool is_valid_date (string value)
    {
        return parse_date (value) != null;
    }

    public string due_input_to_iso (string value)
    {
        var text = value.strip ();
        if (text == "") {
            return "";
        }
        if (is_valid_date (text)) {
            return text;
        }

        var normalized = compact_due_input_text (text);
        var today = today_local ();
        switch (normalized)
        {
            case "yesterday":
                return today.add_days (-1).format ("%F");
            case "today":
                return today.format ("%F");
            case "tomorrow":
                return today.add_days (1).format ("%F");
            case "in 2 days":
                return today.add_days (2).format ("%F");
            case "in 3 days":
                return today.add_days (3).format ("%F");
            default:
                return "";
        }
    }

    public bool due_input_is_valid (string value)
    {
        return value.strip () == "" || due_input_to_iso (value) != "";
    }

    public bool date_is_before_today (string value)
    {
        var iso = due_input_to_iso (value);
        return iso != "" && date_delta_days (iso) < 0;
    }

    public string due_input_display_text (string value)
    {
        var iso = due_input_to_iso (value);
        if (iso == "") {
            return value.strip ();
        }

        switch (date_delta_days (iso))
        {
            case -1:
                return "Yesterday";
            case 0:
                return "Today";
            case 1:
                return "Tomorrow";
            case 2:
                return "In 2 days";
            case 3:
                return "In 3 days";
            default:
                return iso;
        }
    }

    public int date_day_of_month (string value)
    {
        int year;
        int month;
        int day;
        if (!parse_date_parts (value, out year, out month, out day)) {
            return 0;
        }
        return day;
    }

    public string date_add_days_iso (string value, int days)
    {
        var parsed = parse_date (value);
        if (parsed == null) {
            return "";
        }
        return parsed.add_days (days).format ("%F");
    }

    public string next_recurring_due (string due, string recurrence, int monthly_anchor_day = 0)
    {
        int year;
        int month;
        int day;
        if (!parse_date_parts (due, out year, out month, out day)) {
            return "";
        }

        switch (recurrence.strip ().down ())
        {
            case "daily":
                return date_add_days_iso (due, 1);

            case "weekly":
                return date_add_days_iso (due, 7);

            case "monthly":
                month++;
                if (month > 12) {
                    month = 1;
                    year++;
                }
                var anchor_day = monthly_anchor_day >= 1 && monthly_anchor_day <= 31
                    ? monthly_anchor_day
                    : day;
                var clamped_day = int.min (anchor_day, days_in_month (year, month));
                return "%04d-%02d-%02d".printf (year, month, clamped_day);

            default:
                return "";
        }
    }

    public bool daily_recurrence_missed_after_grace (string due)
    {
        var parsed = parse_date (due);
        if (parsed == null) {
            return false;
        }

        var cutoff = new DateTime.local (
            parsed.get_year (),
            parsed.get_month (),
            parsed.get_day_of_month (),
            12,
            0,
            0
        ).add_days (1);
        var now = new DateTime.now_local ();
        return now.to_unix () >= cutoff.to_unix ();
    }

    public int date_delta_days (string due)
    {
        int year;
        int month;
        int day;
        if (!parse_date_parts (due, out year, out month, out day)) {
            return 0;
        }

        var today = today_local ();
        return days_from_civil (year, month, day)
            - days_from_civil (today.get_year (), today.get_month (), today.get_day_of_month ());
    }

    public string due_label (string due)
    {
        if (due.strip () == "") {
            return "no due";
        }

        var delta = date_delta_days (due);
        if (delta == 0) {
            return "today";
        }
        if (delta == 1) {
            return "tomorrow";
        }
        if (delta == -1) {
            return "yesterday";
        }
        if (delta < -1) {
            return "%dd overdue".printf (-delta);
        }
        if (delta < 7) {
            return "%dd".printf (delta);
        }
        if (delta < 31) {
            return "%dw".printf ((delta + 3) / 7);
        }

        return "%dm".printf ((delta + 15) / 30);
    }

    public string due_group_label (string due)
    {
        if (due.strip () == "") {
            return "no due";
        }

        var delta = date_delta_days (due);
        if (delta == 0) {
            return "today";
        }
        if (delta == 1) {
            return "tomorrow";
        }
        if (delta == -1) {
            return "yesterday";
        }
        if (delta < -1) {
            return "%d days overdue".printf (-delta);
        }
        if (delta < 7) {
            return "%d days".printf (delta);
        }
        if (delta < 31) {
            var weeks = (delta + 3) / 7;
            return "%d %s".printf (weeks, weeks == 1 ? "week" : "weeks");
        }

        var months = (delta + 15) / 30;
        return "%d %s".printf (months, months == 1 ? "month" : "months");
    }

    public string due_short_label (string due)
    {
        var parsed = parse_date (due);
        if (parsed == null) {
            return "No due date";
        }

        return parsed.format ("%d/%m");
    }

    public string due_color (string due)
    {
        if (due.strip () == "") {
            return "#9a9996";
        }

        var days = date_delta_days (due);
        if (days < 0) {
            return "#a51d2d";
        }
        if (days == 0) {
            return "#e01b24";
        }
        if (days == 1) {
            return "#e66100";
        }
        if (days == 2) {
            return "#ff7800";
        }
        if (days == 3) {
            return "#ffa348";
        }
        if (days == 4) {
            return "#f5c211";
        }
        if (days == 5) {
            return "#f6d32d";
        }
        if (days == 6) {
            return "#ffea00";
        }
        if (days <= 14) {
            return "#33d17a";
        }
        if (days <= 31) {
            return "#26a269";
        }
        if (days <= 93) {
            return "#3584e4";
        }
        if (days <= 180) {
            return "#9141ac";
        }
        return "#77767b";
    }

    public int parse_int_safe (string? value, int fallback)
    {
        if (value == null) {
            return fallback;
        }

        var text = value.strip ();
        if (text == "") {
            return fallback;
        }

        var negative = false;
        var start = 0;
        if (text[0] == '-' || text[0] == '+') {
            negative = text[0] == '-';
            start = 1;
        }
        if (start >= text.length) {
            return fallback;
        }

        int64 result = 0;
        for (int index = start; index < text.length; index++) {
            var ch = text[index];
            if (ch < '0' || ch > '9') {
                return fallback;
            }
            result = result * 10 + (ch - '0');
            if (result > int.MAX) {
                return fallback;
            }
        }

        return negative ? (int) (-result) : (int) result;
    }

    private string compact_due_input_text (string value)
    {
        string[] pieces = {};
        foreach (var part in value.down ().strip ().split (" ")) {
            if (part.strip () != "") {
                pieces += part.strip ();
            }
        }
        return string.joinv (" ", pieces);
    }

    private bool parse_date_parts (string value, out int year, out int month, out int day)
    {
        year = -1;
        month = -1;
        day = -1;
        var text = value.strip ();
        if (text.length != 10 || text[4] != '-' || text[7] != '-') {
            return false;
        }

        year = parse_int_safe (text.substring (0, 4), -1);
        month = parse_int_safe (text.substring (5, 2), -1);
        day = parse_int_safe (text.substring (8, 2), -1);
        return valid_year_month_day (year, month, day);
    }

    private bool valid_year_month_day (int year, int month, int day)
    {
        return year >= 1
            && month >= 1
            && month <= 12
            && day >= 1
            && day <= days_in_month (year, month);
    }

    public int days_in_month (int year, int month)
    {
        switch (month) {
            case 2:
                return is_leap_year (year) ? 29 : 28;
            case 4:
            case 6:
            case 9:
            case 11:
                return 30;
            default:
                return 31;
        }
    }

    private bool is_leap_year (int year)
    {
        return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    }

    private int days_from_civil (int year, int month, int day)
    {
        var adjusted_year = year - (month <= 2 ? 1 : 0);
        var era = (adjusted_year >= 0 ? adjusted_year : adjusted_year - 399) / 400;
        var year_of_era = adjusted_year - era * 400;
        var month_prime = month + (month > 2 ? -3 : 9);
        var day_of_year = (153 * month_prime + 2) / 5 + day - 1;
        var day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
        return era * 146097 + day_of_era;
    }
}
