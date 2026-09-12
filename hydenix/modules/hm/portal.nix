{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.portal;
in
{
  options.hydenix.hm.portal = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable XDG desktop portal backend configuration";
    };
  };

  config = lib.mkIf cfg.enable {

    # Kept separate from hydenix.hm.xdg: xdg.portal.xdgOpenUsePortal switches
    # xdg-open to org.freedesktop.portal.OpenURI, which never reads
    # mimeapps.list and cannot resolve custom x-scheme-handler entries. Tying
    # that to the XDG base directory option made it impossible to disable one
    # without disabling the other. Every value is mkDefault so a downstream
    # configuration can override or turn any of it off.
    xdg.portal = {
      enable = lib.mkDefault true;
      xdgOpenUsePortal = lib.mkDefault true;
      extraPortals = lib.mkDefault (with pkgs; [
        pkgs.xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        xdg-desktop-portal
      ]);
      configPackages = lib.mkDefault (with pkgs; [
        pkgs.xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        xdg-desktop-portal
      ]);
    };
  };
}
