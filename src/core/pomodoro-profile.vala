namespace Tomodoro
{
    public class PomodoroProfile : GLib.Object
    {
        public string slug { get; set; default = "classic"; }
        public string name { get; set; default = "Classic"; }
        public int work_minutes { get; set; default = 25; }
        public int break_minutes { get; set; default = 5; }
        public int work_seconds { get; set; default = 1500; }
        public int break_seconds { get; set; default = 300; }
        public int long_break_seconds { get; set; default = 900; }

        public string summary ()
        {
            return "%s · %s / %s / %s".printf (
                this.name,
                duration_label (work_duration_seconds ()),
                duration_label (short_break_duration_seconds ()),
                duration_label (long_break_duration_seconds ())
            );
        }

        public int work_duration_seconds ()
        {
            return int.max (1, this.work_seconds);
        }

        public int short_break_duration_seconds ()
        {
            return int.max (0, this.break_seconds);
        }

        public int long_break_duration_seconds ()
        {
            return int.max (0, this.long_break_seconds);
        }

        private string duration_label (int seconds)
        {
            if (seconds % 60 == 0) {
                return "%d min".printf (seconds / 60);
            }

            return "%d sec".printf (seconds);
        }
    }

    public class PomodoroHistoryEntry : GLib.Object
    {
        public string completed_at { get; set; default = ""; }
        public string context { get; set; default = ""; }
        public string project { get; set; default = ""; }
        public string profile { get; set; default = ""; }
    }
}
