# HyDE's hyprquery, built from source.
#
# The repository carries no flake, so this cannot be a flake input the way hydectl and hyde-config
# are. HyDE's theme and shader tooling needs the 0.6.8 interface in particular:
#
#   hyq --dump <config> --schema <hyprland-lua.json> --export lua
#
# which turns the hyprlang `.theme` files in the theme repositories into the Lua table Hyprland
# 0.55+ reads. The older richen604/hyprquery exported json and env only, so without this the theme
# selector runs and changes nothing.
{
  lib,
  stdenv,
  cmake,
  pkg-config,
  libxkbcommon,
  hyprlang,
  cli11,
  nlohmann_json,
  src,
}:

stdenv.mkDerivation {
  pname = "hyprquery";
  version = "0.6.8";

  inherit src;

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    libxkbcommon
    hyprlang
    cli11
    nlohmann_json
  ];

  # Both switches have to be on. HYPRQUERY_DISTRO_BUILD turns `find_package(CLI11 QUIET)` and the
  # nlohmann_json lookup into REQUIRED, and USE_SYSTEM_HYPRLANG does the same for hyprlang; leave
  # either off and CMake falls through to FetchContent and reaches for the network, which the
  # build sandbox does not have.
  cmakeFlags = [
    "-DHYPRQUERY_DISTRO_BUILD=ON"
    "-DUSE_SYSTEM_HYPRLANG=ON"
  ];

  meta = {
    description = "Query and export values from HyDE's Hyprland configuration files";
    homepage = "https://github.com/HyDE-Project/hyprquery";
    license = lib.licenses.lgpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "hyq";
  };
}
