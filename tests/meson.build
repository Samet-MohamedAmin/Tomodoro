test_env = environment()
test_env.set('LANGUAGE', '')
test_env.set('LANG', 'C')
test_env.set('G_DEBUG', 'gc-friendly')
test_env.set('GSETTINGS_BACKEND', 'memory')
test_env.set('TOMODORO_DISABLE_CALENDAR_SYNC', '1')

test(
  'todo-core',
  executable(
    'test-todo-core',
    'test-todo-core.vala',
    dependencies: libtodo_core_dep,
    c_args: ['-UG_DISABLE_ASSERT'],
  ),
  env: test_env,
  suite: 'tests',
)
