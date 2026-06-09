# subprojects/packagefiles/ash/meson.build
# Custom meson build for ash crate (without "loaded" feature).

project('ash', 'rust',
  version: '0.38.0',
  default_options: ['rust_std=2021'],
)

rust = import('rust')

feature_args = [
]

ash_lib = static_library(
  'ash',
  sources: files('ash/src/lib.rs'),
  rust_abi: 'rust',
  rust_args: feature_args,
  install: false,
)

ash_dep = declare_dependency(link_with: ash_lib)
meson.override_dependency('ash-0-rs', ash_dep)
