resources_sources = files(
  'io.github.samet_mohamedamin.Tomodoro.gresource.xml',
)

resources = gnome.compile_resources(
  'io.github.samet_mohamedamin.Tomodoro',
  resources_sources,
  c_name: 'todo_pomodoro_resources',
)

todo_core_sources = files(
  'core/date-utils.vala',
  'core/project-utils.vala',
  'core/todo.vala',
  'core/context-config.vala',
  'core/pomodoro-profile.vala',
  'core/calendar-sync.vala',
  'core/store.vala',
)

libtodo_core = static_library(
  'todo_pomodoro_core',
  todo_core_sources,
  dependencies: [
    glib_dep,
    gobject_dep,
    gio_dep,
    json_dep,
    libecal_dep,
    libedataserver_dep,
  ],
  include_directories: config_h_dir,
)

libtodo_core_dep = declare_dependency(
  link_with: libtodo_core,
  dependencies: [
    glib_dep,
    gobject_dep,
    gio_dep,
    json_dep,
    libecal_dep,
    libedataserver_dep,
  ],
  include_directories: include_directories('.'),
)

todo_ui_sources = files(
  'ui/pomodoro-display.vala',
  'ui/status-indicator.vala',
  'ui/todo-dialog.vala',
  'ui/recurring-dialog.vala',
  'ui/preferences-window.vala',
  'ui/main-window.vala',
  'application.vala',
)

libtodo_ui = static_library(
  'todo_pomodoro_ui',
  todo_ui_sources + resources,
  dependencies: [
    libtodo_core_dep,
    gtk_dep,
    libadwaita_dep,
  ],
  include_directories: config_h_dir,
)

libtodo_ui_dep = declare_dependency(
  link_whole: libtodo_ui,
  dependencies: [
    libtodo_core_dep,
    gtk_dep,
    libadwaita_dep,
  ],
  include_directories: include_directories('.'),
)

executable(
  'tomodoro',
  'main.vala',
  dependencies: [libtodo_ui_dep],
  include_directories: config_h_dir,
  install: true,
)
