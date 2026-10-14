{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.lockscreen;
in
{
  options.hydenix.hm.lockscreen = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable lockscreen module";
    };

    hyprlock = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable hyprlock lockscreen";
    };

    swaylock = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable swaylock lockscreen";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      (lib.mkIf cfg.hyprlock hyprlock)
      (lib.mkIf cfg.swaylock swaylock)
    ];
  };
}
