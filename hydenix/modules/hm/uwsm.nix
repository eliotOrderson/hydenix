{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.uwsm;
in
{
  options.hydenix.hm.uwsm = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable uwsm module";
    };
  };

  config = lib.mkIf cfg.enable { };
}
