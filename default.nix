{
  lib,
  stdenv,
  pkg-config,
  meson,
  rustc,
  rust-cbindgen,
  rust-bindgen,
  shaderc,
  ninja,
  nixfmt,
  nixd,
  llvmPackages,
  vulkan-loader,
  vulkan-headers,
  libpng,
  openal,
  sdl3,
  wayland,
}:

stdenv.mkDerivation {
  name = "mcpe";
  version = "0.6.1+dev.1";
  src = ./.;

  nativeBuildInputs = [
    pkg-config
    meson
    ninja
    nixfmt
    nixd
    llvmPackages.clang-tools
    rustc
    rust-cbindgen
    rust-bindgen
    shaderc
  ];
  buildInputs = [
    vulkan-loader
    vulkan-headers
    libpng
    openal
    sdl3
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    wayland
  ];

  mesonFlags  = [
  ];

  postInstall = ''
    mkdir -p $out/share/
    cp -r ${./data} $out/share/mcpe
  '';
}
