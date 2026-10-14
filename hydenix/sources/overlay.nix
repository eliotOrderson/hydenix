{ inputs }:

final: prev:
let
  # Helper function to import a package
  callPackage = prev.lib.callPackageWith (prev // packages // inputs);

  # Define all packages
  packages = {
    # Hyde core packages
    hyde-gallery = callPackage ./hyde-gallery.nix { };
    # Additional packages
    pokego = callPackage ./pokego.nix { };
    python-pyamdgpuinfo = callPackage ./python-pyamdgpuinfo.nix { };
    Tela-circle-dracula = callPackage ./Tela-circle-dracula.nix { };
    Bibata-Modern-Ice = callPackage ./Bibata-Modern-Ice.nix { };
    hyde = callPackage ./hyde.nix { inherit inputs; };
    hyprquery = callPackage ./hyprquery.nix { src = inputs.hyprquery; };
    hydenix-themes = callPackage ./themes/default.nix { };
    hydectl = inputs.hydectl.packages.${prev.stdenv.hostPlatform.system}.default;
    hyde-ipc = inputs.hyde-ipc.packages.${prev.stdenv.hostPlatform.system}.default;
    hyde-config = inputs.hyde-config.packages.${prev.stdenv.hostPlatform.system}.default;
  };
in
packages
