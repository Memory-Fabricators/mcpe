# subprojects/packagefiles/glam-0.33.1/meson.build — overlays glam static.crates.io

project('glam', 'rust', default_options: ['rust_std=2021'])

add_project_arguments(
  '--cfg', 'feature="std"',
  '--cfg', 'feature="scalar-math"',
  language: 'rust',
)

glam_lib = static_library(
  'glam',
  'src/lib.rs',
)

glam_dep = declare_dependency(
  link_with: glam_lib,
)
