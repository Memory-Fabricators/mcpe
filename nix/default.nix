{
  lib,
  callPackage,
  stdenv,
  pkg-config,
  meson,
  rustc,
  rust-cbindgen,
  ninja,
  nixfmt,
  nixd,
  llvmPackages,
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
  ];
  buildInputs = [
    (callPackage ./angle { })
    libpng
    openal
    sdl3
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    wayland
  ];

  mesonFlags = [
    "-Dunity=on"
  ];

  postInstall = ''
    mkdir -p $out/share/
    cp -r ${./data} $out/share/mcpe
  '';
}
