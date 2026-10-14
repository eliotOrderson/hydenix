{
  description = "Nix & home-manager configuration for HyDE, an Arch Linux based Hyprland desktop";

  inputs = {
    # The single nixpkgs for the whole system. The desktop stack HyDE's scripts call is no longer
    # pinned separately: base carries all of it, and a second nixpkgs only ever bought a "bundle"
    # that then had to be kept in step with `hyde` by hand at every upstream release.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    home-manager = {
      # Must stay on the same release as nixpkgs, home-manager is version-coupled to it.
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:nixos/nixos-hardware/master";

    # Nix-index-database - for comma and command-not-found
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # HyDE v26.08.21 moved the Hyprland configuration to Lua, which Hyprland 0.55 or newer reads.
    hyde = {
      url = "github:HyDE-Project/HyDE/7c7b832d479620133fb0a2bdec0fe20cf2e7c90a";
      flake = false;
    };
    # hyprquery as HyDE ships it. HyDE's theme and shader tooling calls
    #   hyq --dump <config> --schema <hyprland-lua.json> --export lua
    # and the richen604/hyprquery this flake used before stopped short of that: its last release
    # (0.6.7, 2026-01-01) exports json and env only and has no --dump. HyDE took the project over
    # and 0.6.8 added both, so configs in the Lua layout cannot be themed without it.
    # The repository ships no flake, hence hydenix/sources/hyprquery.nix builds it from source.
    hyprquery = {
      url = "github:HyDE-Project/hyprquery/002af783eeb8c487a4bf90d75e5a804340557967";
      flake = false;
    };
    # HyDE related binaries
    hydectl = {
      url = "github:richen604/hydectl";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyde-ipc = {
      url = "github:richen604/hyde-ipc";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyde-config = {
      url = "github:richen604/hyde-config";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    inputs:
    let
      system = "x86_64-linux";

      defaultConfig = import ./lib/config {
        inherit inputs;
      };

      # Create VM variant of the NixOS configuration
      vmConfig = import ./lib/vms/nixos-vm.nix {
        inherit inputs;
        nixosConfiguration = defaultConfig;
      };

      demoVmConfig = import ./lib/vms/demo-vm.nix {
        inherit inputs;
      };

      # nixpkgs with the overlay the NixOS configuration uses, so `nix build .#hyprquery` builds
      # the same derivation the system installs rather than a second copy from plain nixpkgs.
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ (import ./hydenix/sources/overlay.nix { inherit inputs; }) ];
      };

    in
    {

      lib.vmConfig = import ./lib/vms/nixos-vm.nix;

      # Direct module access
      homeModules.default = import ./hydenix/modules/hm;
      nixosModules.default = import ./hydenix/modules/system;

      overlays.default = import ./hydenix/sources/overlay.nix { inherit inputs; };

      templates.default = {
        path = ./template;
        description = "Template for hydenix configuration";
      };

      nixosConfigurations.default = defaultConfig;

      packages.${system} = {
        # Use the VM configuration as default
        default = vmConfig.config.system.build.vm;

        # WIP: For a future demo installation & usage video
        demo-vm = demoVmConfig.config.system.build.vm;

        # Helper to manage hyde updates
        hyde-update = import ./lib/hyde-update { inherit inputs; };

        # HyDE's own binaries, exposed so they can be built and inspected on their own.
        inherit (pkgs) hyprquery hydectl;
        inherit (pkgs) hyde-config;
        # hyde-ipc = pkgs.hyde-ipc;
      };

      checks.${system} = {
        inherit (inputs.self.packages.${system}) hyprquery;
        inherit (inputs.self.packages.${system}) hydectl;
        inherit (inputs.self.packages.${system}) hyde-config;
        #FIXME: hyde-ipc has 2gb of build dependencies, so disable for now to prevent gh actions timeouts
        # hyde-ipc = inputs.self.packages.${system}.hyde-ipc;
      };

      devShells.${system}.default = import ./lib/dev-shell.nix { inherit inputs; };
    };
}
