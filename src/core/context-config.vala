namespace Tomodoro
{
    public class ContextConfig : GLib.Object
    {
        public string slug { get; set; default = "work"; }
        public string name { get; set; default = "Work"; }
        public string icon { get; set; default = "folder-symbolic"; }
        public string default_project { get; set; default = "Inbox"; }

        public GLib.HashTable<string, string> project_icons { get; private set; }

        public ContextConfig ()
        {
            this.project_icons = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
        }

        public string icon_for_project (string project)
        {
            var value = this.project_icons.lookup (normalize_project (project, "Inbox"));
            return value != null ? value : "folder-symbolic";
        }

        public void set_project_icon (string project, string icon_name)
        {
            this.project_icons.replace (normalize_project (project, "Inbox"), icon_name.strip () == "" ? "folder-symbolic" : icon_name.strip ());
        }
    }
}
