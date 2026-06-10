{
  lib,
  stdenv,
  pkg-config,
  zig,
  ninja,
  nixfmt,
  nixd,
  llvmPackages,
  libpng,
  openal,
  sdl3,
  shaderc,
}:

stdenv.mkDerivation {
  name = "mcpe";
  version = "0.6.1+dev.1";
  src = ./.;

  nativeBuildInputs = [
    pkg-config
    zig
  ];
  buildInputs = [
    libpng
    openal
    sdl3
    shaderc
  ];

  zigBuildFlags = [];

  postInstall = ''
    mkdir -p $out/share/
    cp -r ${./data} $out/share/mcpe
  '';
}
