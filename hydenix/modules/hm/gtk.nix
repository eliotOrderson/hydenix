{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.gtk;
in
{
  options.hydenix.hm.gtk = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable gtk module";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      gtk3
      gtk4
      glib
      gsettings-desktop-schemas
      gnome-settings-daemon
      gnome-tweaks
      gnomeExtensions.window-gestures
      nwg-look
      adwaita-icon-theme
      emote
    ];
  };
}
