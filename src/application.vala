namespace Tomodoro
{
    private delegate void AppActionCallback ();

    public class Application : Adw.Application
    {
        private StatusIndicator? status_indicator = null;

        public Application ()
        {
            Object (
                application_id: Config.APPLICATION_ID,
                flags: GLib.ApplicationFlags.DEFAULT_FLAGS
            );
        }

        protected override void startup ()
        {
            base.startup ();

            install_actions ();
            this.status_indicator = new StatusIndicator (this);

            this.set_accels_for_action ("win.new-todo", {"<primary>n"});
            this.set_accels_for_action ("win.focus-filter", {"<primary>f"});
            this.set_accels_for_action ("win.tab-pomodoro", {"<primary>1"});
            this.set_accels_for_action ("win.tab-todos", {"<primary>2"});
            this.set_accels_for_action ("win.show-shortcuts", {"<primary>question"});

            var provider = new Gtk.CssProvider ();
            provider.load_from_resource ("/io/github/samet_mohamedamin/Tomodoro/style.css");
            Gtk.StyleContext.add_provider_for_display (
                Gdk.Display.get_default (),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }

        private void install_actions ()
        {
            add_simple_action ("timer-toggle", () => {
                var window = ensure_main_window ();
                window.notification_toggle_timer ();
            });
            add_simple_action ("timer-done", () => {
                var window = ensure_main_window ();
                window.notification_finish_timer_session ();
            });
            add_simple_action ("indicator-open", () => {
                var window = ensure_main_window ();
                window.present ();
            });
            add_simple_action ("indicator-new", () => {
                var window = ensure_main_window ();
                window.activate_action ("new-todo", null);
            });
            add_simple_action ("indicator-quit", () => {
                this.quit ();
            });
        }

        private void add_simple_action (string name, owned AppActionCallback callback)
        {
            var action = new GLib.SimpleAction (name, null);
            action.activate.connect (() => callback ());
            this.add_action (action);
        }

        private MainWindow ensure_main_window ()
        {
            var window = this.active_window as MainWindow;
            if (window == null) {
                window = new MainWindow (this);
            }
            window.present ();
            return window;
        }

        protected override void activate ()
        {
            var window = ensure_main_window ();
            this.status_indicator?.start ();
            window.present ();
        }

        protected override void shutdown ()
        {
            this.status_indicator?.stop ();
            this.status_indicator = null;
            base.shutdown ();
        }
    }
}
