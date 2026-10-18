project('mate-wacom', 'vala', version: '0.1.0', default_options: ['warning_level=2'])

gettext_domain = 'mate-wacom'
locale_dir = join_paths(get_option('prefix'), get_option('localedir'))
config = configuration_data()
config.set_quoted('LOCALEDIR', locale_dir)
config_vala = configure_file(input: 'src/config.vala.in', output: 'config.vala', configuration: config)

gtk = dependency('gtk+-3.0', version: '>=3.22')
gio = dependency('gio-2.0')
math = meson.get_compiler('c').find_library('m', required: true)

executable('mate-wacom-properties',
  ['src/main.vala', 'src/wacom-client.vala', config_vala],
  dependencies: [gtk, gio, math],
  c_args: ['-DGETTEXT_PACKAGE="' + gettext_domain + '"'],
  install: true)

install_data('data/mate-wacom-properties.desktop',
  install_dir: join_paths(get_option('datadir'), 'applications'))

subdir('po')
