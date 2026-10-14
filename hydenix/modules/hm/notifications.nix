{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.notifications;
in
{
  options.hydenix.hm.notifications = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable notifications module";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      dunst # notification daemon
    ];
  };
}
