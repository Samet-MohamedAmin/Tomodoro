using GLib;

public int main (string[] args)
{
    GLib.Intl.setlocale (GLib.LocaleCategory.ALL, "");
    GLib.Environment.set_application_name (Config.APPLICATION_NAME);
    GLib.Environment.set_prgname (Config.APPLICATION_ID);

    var application = new Tomodoro.Application ();
    return application.run (args);
}
