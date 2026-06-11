{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      eachSystem = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "riscv64-linux"
        "aarch64-darwin"
      ];
    in
    {
      packages = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        with pkgs;
        {
          default = rustPlatform.buildRustPackage {
            pname = "mcpe";
            version = "0.1.0";
            src = ./.;

            cargoLock.lockFile = ./Cargo.lock;

            nativeBuildInputs = [
              pkg-config
              rust-cbindgen
              vulkan-headers
              vulkan-loader
              libxkbcommon
              wayland
              wayland-scanner
            ];

            buildInputs = [
              sdl3
              libpng
              openal
              lua5_5
              angle
              vulkan-loader
              libxkbcommon
              wayland
              libx11
              libxcursor
              libxi
              libxrandr
            ];

            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
              sdl3
              libpng
              openal
              lua5_5
              vulkan-loader
              wayland
              libxkbcommon
              libx11
              libxcursor
              libxi
              libxrandr
            ];
          };
        }
      );

      devShells = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        with pkgs;
        {
          default =
            mkShell.override
              {
                stdenv = if stdenv.hostPlatform.isLinux then useWildLinker stdenv else stdenv;
              }
              rec {
                nativeBuildInputs = [
                  pkg-config
                  meson
                  ninja
                  nixfmt
                  nixd
                  rustc
                  cargo
                  rust-cbindgen
                  rustfmt
                  clippy
                  rust-analyzer
                  vulkan-headers
                  vulkan-loader
                  libxkbcommon
                  wayland
                  wayland-scanner
                ];

                buildInputs = [
                  angle
                  libpng
                  openal
                  sdl3
                  lua5_5
                  vulkan-loader
                  libxkbcommon
                  wayland
                  libx11
                  libxcursor
                  libxi
                  libxrandr
                ];

                LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;
                DYLD_LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;
                RUST_SRC_PATH = rustPlatform.rustLibSrc;
              };
        }
      );
    };
}
