{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.terminals;
in
{
  options.hydenix.hm.terminals = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable terminals module";
    };

    kitty = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable kitty terminal";
      };
      configText = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Kitty config multiline text, use this to extend kitty settings";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      (lib.mkIf cfg.kitty.enable kitty) # terminal
    ];

    home.file = {
      # HyDE ships a kitty.conf and marks it "preserve", but this option is the declarative source
      # for the same file, so it wins: hydeSeed sees the symlink already in place and leaves it
      # alone. configText is the extension point, and editing the generated file by hand was never
      # going to survive a switch.
      ".config/kitty/kitty.conf" = {
        text = ''
          include hyde.conf

          # Add your custom configurations here
          ${cfg.kitty.configText}
        '';
        force = true;
      };
    };
  };
}
