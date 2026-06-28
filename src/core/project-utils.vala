namespace Tomodoro
{
    public const int MIN_TODO_TEXT_LETTERS = 3;
    public const int PROJECT_PART_MAX_LENGTH = 32;
    public const int CONTEXT_NAME_MAX_LENGTH = 32;

    public string slugify (string name)
    {
        var source = name.strip ().down ();
        var builder = new GLib.StringBuilder ();
        var previous_dash = false;

        for (int index = 0; index < source.length; index++) {
            var ch = source[index];
            var valid = (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9');
            if (valid) {
                builder.append_c (ch);
                previous_dash = false;
            }
            else if (!previous_dash) {
                builder.append_c ('-');
                previous_dash = true;
            }
        }

        var result = trim_chars (builder.str, "-");
        return result == "" ? "context" : result;
    }

    public string normalize_project (string value, string fallback)
    {
        var source = value.strip ().down ();
        if (source.has_prefix ("+")) {
            source = source.substring (1);
        }

        source = source.replace (" ", "-").replace ("/", ".");
        var builder = new GLib.StringBuilder ();

        for (int index = 0; index < source.length; index++) {
            var ch = source[index];
            var valid = (ch >= 'a' && ch <= 'z')
                || (ch >= '0' && ch <= '9')
                || ch == '.'
                || ch == '-'
                || ch == '_';
            if (valid) {
                builder.append_c (ch);
            }
        }

        string[] parts = {};
        foreach (var part in builder.str.split (".")) {
            if (part.strip () != "") {
                parts += normalize_project_part (part.strip ());
            }
            if (parts.length == 2) {
                break;
            }
        }

        if (parts.length == 0) {
            return fallback;
        }
        if (parts.length == 1) {
            return parts[0];
        }
        return "%s.%s".printf (parts[0], parts[1]);
    }

    public string sanitize_todo_project (string value, string fallback)
    {
        var clean_fallback = normalize_project (fallback, "Inbox");
        var clean = normalize_project (value, clean_fallback);
        var root = project_root (clean);
        if (!valid_project_part_text (root)) {
            root = project_root (clean_fallback);
            if (!valid_project_part_text (root)) {
                root = "Inbox";
            }
        }

        var child = project_child (clean);
        if (child == "") {
            return root;
        }
        if (!valid_project_part_text (child)) {
            child = "Default";
        }
        return "%s.%s".printf (root, child);
    }

    public string normalize_body_text (string value)
    {
        return uppercase_first_letter (compact_text (value));
    }

    public string uppercase_first_letter (string value)
    {
        var text = value;
        for (int index = 0; index < text.length; index++) {
            var ch = text[index];
            if (ch >= 'a' && ch <= 'z') {
                return "%s%c%s".printf (text.substring (0, index), ch - 32, text.substring (index + 1));
            }
            if (ch >= 'A' && ch <= 'Z') {
                return text;
            }
        }
        return text;
    }

    public bool has_minimum_letters (string value, int minimum = MIN_TODO_TEXT_LETTERS)
    {
        var letters = 0;
        for (int index = 0; index < value.length; index++) {
            var ch = value[index];
            if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
                letters++;
            }
        }
        return letters >= minimum;
    }

    public bool valid_project_part_text (string value)
    {
        var clean = project_root (normalize_project (value, ""));
        return clean != ""
            && clean.length <= PROJECT_PART_MAX_LENGTH
            && has_minimum_letters (clean);
    }

    public bool valid_context_name_text (string value)
    {
        var clean = value.strip ();
        return clean != ""
            && clean.length <= CONTEXT_NAME_MAX_LENGTH
            && has_minimum_letters (clean);
    }

    public string sanitize_structure_name_input (string value, int max_length = PROJECT_PART_MAX_LENGTH)
    {
        var builder = new GLib.StringBuilder ();
        for (int index = 0; index < value.length && builder.len < (size_t) max_length; index++) {
            var ch = value[index];
            var valid = (ch >= 'A' && ch <= 'Z')
                || (ch >= 'a' && ch <= 'z')
                || (ch >= '0' && ch <= '9')
                || ch == '-'
                || ch == '_';
            if (valid) {
                builder.append_c (ch);
            }
        }
        return uppercase_first_letter (builder.str);
    }

    public string project_root (string project)
    {
        var index = project.index_of (".");
        return index < 0 ? project : project.substring (0, index);
    }

    public string project_child (string project)
    {
        var index = project.index_of (".");
        return index < 0 ? "" : project.substring (index + 1);
    }

    public int project_depth (string project)
    {
        var depth = 0;
        for (int index = 0; index < project.length; index++) {
            if (project[index] == '.') {
                depth++;
            }
        }
        return depth;
    }

    public string join_project (string root, string child)
    {
        var clean_root = normalize_project (root, "Inbox");
        var clean_child = normalize_project (child, "Default");
        clean_child = project_root (clean_child);
        return "%s.%s".printf (clean_root, clean_child == "" ? "Default" : clean_child);
    }

    public string format_project_label (string project)
    {
        var child = project_child (project);
        return child == "" ? project : "%s / %s".printf (project_root (project), child);
    }

    public string[] project_roots_from_projects (string[] projects)
    {
        string[] roots = {};
        foreach (var project in projects) {
            var root = project_root (normalize_project (project, ""));
            if (root == "" || project_root_list_contains (roots, root)) {
                continue;
            }
            roots += root;
        }
        return roots;
    }

    public string[] remaining_project_roots_after_delete (string[] projects, string deleted_project)
    {
        var deleted_root = project_root (normalize_project (deleted_project, ""));
        string[] roots = {};
        foreach (var root in project_roots_from_projects (projects)) {
            if (root != deleted_root) {
                roots += root;
            }
        }
        return roots;
    }

    public string normalize_project_filter (string value)
    {
        return trim_chars (normalize_project (value.replace (" ", ".").replace ("/", "."), ""), ".");
    }

    private string trim_chars (string value, string chars)
    {
        var start = 0;
        var end = value.length;
        while (start < end && chars.contains (value.substring (start, 1))) {
            start++;
        }
        while (end > start && chars.contains (value.substring (end - 1, 1))) {
            end--;
        }
        return value.substring (start, end - start);
    }

    private string normalize_project_part (string value)
    {
        var clean = value.strip ();
        if (clean.length > PROJECT_PART_MAX_LENGTH) {
            clean = clean.substring (0, PROJECT_PART_MAX_LENGTH);
        }
        return uppercase_first_letter (clean);
    }

    private bool project_root_list_contains (string[] roots, string root)
    {
        foreach (var item in roots) {
            if (item == root) {
                return true;
            }
        }
        return false;
    }
}
