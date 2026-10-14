{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.qt;
in
{
  options.hydenix.hm.qt = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable qt module";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      kdePackages.qt6ct
      kdePackages.qtbase
      kdePackages.qtwayland
      kdePackages.qtstyleplugin-kvantum
      kdePackages.breeze-icons
      kdePackages.qtimageformats
      kdePackages.qtsvg
      kdePackages.qtwayland
    ];
  };
}
