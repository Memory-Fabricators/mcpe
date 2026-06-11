project('ash', 'rust', default_options: ['rust_std=2021'])

libloading_dep = dependency('libloading-0.8-rs')

ash_lib = static_library(
  'ash',
  'ash/src/lib.rs',
  rust_args: [
    '--cfg', 'feature="loaded"',
    '--cfg', 'feature="debug"',
    '--cfg', 'feature="std"',
  ],
  dependencies: [libloading_dep],
)

ash_dep = declare_dependency(
  link_with: ash_lib,
)
