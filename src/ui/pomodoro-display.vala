namespace Tomodoro
{
    public const string TOMATO_ICON_RESOURCE = "/io/github/samet_mohamedamin/Tomodoro/icons/tomato.svg";

    public Gtk.Widget pomodoro_display_widget (int count, bool repeat_icons, int icon_limit = -1, int icons_per_line = -1)
    {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        box.add_css_class ("pomodoro-count");
        box.valign = Gtk.Align.CENTER;

        if (count == 0) {
            return box;
        }

        var show_icons = repeat_icons && (icon_limit < 0 || count <= icon_limit);
        if (show_icons) {
            var stack = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            stack.add_css_class ("pomodoro-count");
            stack.valign = Gtk.Align.CENTER;
            stack.halign = Gtk.Align.END;

            var per_line = icons_per_line > 0 ? icons_per_line : count;
            if (per_line <= 0) {
                per_line = 1;
            }

            for (int row_start = 0; row_start < count; row_start += per_line) {
                var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                row.halign = Gtk.Align.END;
                var row_end = row_start + per_line < count ? row_start + per_line : count;
                var row_count = row_end - row_start;
                var leading_group_size = row_count % 4;
                if (leading_group_size > 0) {
                    row.append (tomato_group (leading_group_size));
                }
                for (int remaining = row_count - leading_group_size; remaining > 0; remaining -= 4) {
                    row.append (tomato_group (4));
                }

                stack.append (row);
            }

            return stack;
        }

        var label = new Gtk.Label ("%d".printf (count));
        label.add_css_class ("caption");
        box.append (label);
        box.append (tomato_image ());
        return box;
    }

    private Gtk.Image tomato_image ()
    {
        var image = new Gtk.Image.from_resource (TOMATO_ICON_RESOURCE);
        image.pixel_size = 14;
        return image;
    }

    private Gtk.Widget tomato_group (int count)
    {
        var group = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3);
        for (int index = 0; index < count; index++) {
            group.append (tomato_image ());
        }
        return group;
    }
}
