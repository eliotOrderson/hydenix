{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.nix;

  # `inputs` is hydenix's own input set when building this repo, and the user's when hydenix is a
  # flake input, so the bundle base has to be looked up through `inputs.hydenix.inputs` there.
  hydeInputs = if inputs ? hydenix then inputs.hydenix.inputs else inputs;
  pins = import ../../sources/pins.nix { inputs = hydeInputs; };
in
{
  options.hydenix.nix = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable nix module";
    };
  };

  config = lib.mkIf cfg.enable {

    nixpkgs.pkgs = lib.mkDefault (
      import inputs.nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
        overlays = [
          (if inputs ? hydenix then inputs.hydenix.overlays.default else inputs.self.overlays.default)
        ];
      }
    );

    # The pin list silently stops applying if the overlay above is ever dropped or applied to a
    # different pkgs, and HyDE's configs would then target an unexpected desktop stack. Compare
    # derivation paths rather than versions so a same-version rebuild is caught too.
    assertions = [
      {
        assertion = lib.all (name: pkgs.${name}.drvPath == pins.pinned.${name}.drvPath) pins.names;
        message = ''
          hydenix: the pinned HyDE package set is not in effect.
          HyDE's configuration is written for the versions of hydenix/sources/pins.nix, so this
          would silently ship a desktop stack those configs were not written for.
          Check that nixpkgs.pkgs is still built with inputs.hydenix.overlays.default.
        '';
      }
    ];

    nix = {
      settings = {
        auto-optimise-store = true;
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        substituters = [
          "https://cache.nixos.org"
          "https://hyprland.cachix.org"
          "https://nix-community.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };
    };
  };
}
