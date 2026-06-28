project(
  'tomodoro',
  ['vala', 'c'],
  version: '0.1.33',
  meson_version: '>=0.59.0',
  default_options: [
    'warning_level=2',
  ],
)

gnome = import('gnome')

glib_dep = dependency('glib-2.0', version: '>=2.76')
gobject_dep = dependency('gobject-2.0', version: '>=2.76')
gio_dep = dependency('gio-2.0', version: '>=2.76')
gtk_dep = dependency('gtk4', version: '>=4.18')
libadwaita_dep = dependency('libadwaita-1', version: '>=1.8.0')
json_dep = dependency('json-glib-1.0', version: '>=1.6.2')
libecal_dep = dependency('libecal-2.0', version: '>=3.50')
libedataserver_dep = dependency('libedataserver-1.2', version: '>=3.50')

cc = meson.get_compiler('c')
valac = meson.get_compiler('vala')
posix_dep = valac.find_library('posix')

application_id = 'io.github.samet_mohamedamin.Tomodoro'
application_name = 'Tomodoro'
package_name = meson.project_name()
package_version = meson.project_version()
package_website = 'https://github.com/Samet-MohamedAmin/Tomodoro'
package_datadir = get_option('prefix') / get_option('datadir') / meson.project_name()
package_localedir = get_option('prefix') / get_option('datadir') / 'locale'
gschema_dir = get_option('prefix') / get_option('datadir') / 'glib-2.0' / 'schemas'
gettext_package = package_name

add_project_arguments(
  [
    '-DGETTEXT_PACKAGE="' + gettext_package + '"',
    '-DG_LOG_DOMAIN="' + package_name + '"',
  ],
  language: 'c',
)

add_project_arguments(
  [
    '-DVALA_STRICT_C',
    '-Wno-error',
    '-Wno-discarded-qualifiers',
    '-Wno-incompatible-pointer-types',
    '-Wno-cast-function-type',
    '-Wno-unused-parameter',
    '-Wno-unused-variable',
    '-Wno-unused-function',
  ],
  language: 'c',
)

add_project_arguments(
  [
    '--vapidir', meson.current_source_dir(),
    '--pkg', 'config',
  ],
  language: 'vala',
)

conf = configuration_data()
conf.set_quoted('APPLICATION_ID', application_id)
conf.set_quoted('APPLICATION_NAME', application_name)
conf.set_quoted('PACKAGE_NAME', package_name)
conf.set_quoted('PACKAGE_VERSION', package_version)
conf.set_quoted('PACKAGE_WEBSITE', package_website)
conf.set_quoted('PACKAGE_DATA_DIR', package_datadir)
conf.set_quoted('PACKAGE_LOCALE_DIR', package_localedir)
conf.set_quoted('GETTEXT_PACKAGE', gettext_package)
conf.set_quoted('GSETTINGS_SCHEMA_DIR', gschema_dir)

configure_file(
  output: 'config.h',
  configuration: conf,
)

config_h_dir = include_directories('.')

subdir('data')
subdir('src')
subdir('tests')

summary(
  {
    'application_id': application_id,
    'gtk': gtk_dep.version(),
    'libadwaita': libadwaita_dep.version(),
  },
  section: 'Tomodoro',
)
