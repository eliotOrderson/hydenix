{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.wlogout;
in
{
  options.hydenix.hm.wlogout = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable logout module";
    };

    wlogout = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable wlogout";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [

      # wlogout
      (lib.mkIf cfg.wlogout.enable wlogout) # logout menu
    ];
  };
}
