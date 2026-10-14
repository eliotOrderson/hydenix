{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.waybar;
in
{
  options.hydenix.hm.waybar = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable bar module";
    };

    waybar = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable waybar";
      };
    };

    userStyle = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        /* Custom waybar styles */
        window#waybar {
          background-color: rgba(0, 0, 0, 0.8);
        }
      '';
      description = "Custom CSS styles for waybar user-style.css";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      with pkgs;
      lib.optionals cfg.waybar.enable [
        waybar # system bar
        playerctl # media player cli
        gobject-introspection # for python packages
        (python3.withPackages (ps: with ps; [ pygobject3 ])) # python with pygobject3
        python-pyamdgpuinfo # AMD GPU information library
        lm_sensors # sensors information library
        power-profiles-daemon # power profiles daemon
      ];

    # Everything else under ~/.config/waybar is seeded by hydeSeed. This one stays declared because
    # waybar.py only writes it when it is missing, so a link here keeps the option authoritative.
    home.file.".config/waybar/user-style.css" = {
      text = cfg.userStyle;
      force = true;
    };
  };
}
