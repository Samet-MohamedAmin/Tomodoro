# Desktop file
desktop_conf = configuration_data()
desktop_conf.set('APPLICATION_ID', application_id)
desktop_conf.set('APPLICATION_NAME', application_name)

desktop_file = configure_file(
  input: 'io.github.samet_mohamedamin.Tomodoro.desktop.in',
  output: '@0@.desktop'.format(application_id),
  configuration: desktop_conf,
  install: true,
  install_dir: get_option('datadir') / 'applications',
)

desktop_file_validate = find_program('desktop-file-validate', required: false)
if desktop_file_validate.found()
  test(
    'Validate .desktop',
    desktop_file_validate,
    args: [desktop_file],
  )
endif

# App metadata
metainfo_file = configure_file(
  input: 'io.github.samet_mohamedamin.Tomodoro.metainfo.xml.in',
  output: '@0@.metainfo.xml'.format(application_id),
  configuration: desktop_conf,
  install: true,
  install_dir: get_option('datadir') / 'metainfo',
)

appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test(
    'Validate .metainfo.xml',
    appstreamcli,
    args: ['validate', '--no-net', '--explain', metainfo_file],
  )
endif

# App icon
install_data(
  files('../src/ui/icons/tomato.svg'),
  rename: '@0@.svg'.format(application_id),
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
)

install_data(
  files('icons/tomodoro-symbolic.svg'),
  rename: '@0@-symbolic.svg'.format(application_id),
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'symbolic' / 'apps',
)

# GSettings schema
install_data(
  'io.github.samet_mohamedamin.Tomodoro.gschema.xml',
  install_dir: gschema_dir,
)

compile_schemas = find_program('glib-compile-schemas', required: false)
if compile_schemas.found()
  test(
    'Validate schema file',
    compile_schemas,
    args: ['--strict', '--dry-run', meson.current_source_dir()],
  )
endif

compiled_schemas = gnome.compile_schemas(
  depend_files: 'io.github.samet_mohamedamin.Tomodoro.gschema.xml',
)

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
