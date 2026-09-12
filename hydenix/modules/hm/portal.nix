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

    # Kept separate from hydenix.hm.xdg: xdg.portal.xdgOpenUsePortal only
    # affects the host xdg-open command, which forwards to
    # org.freedesktop.portal.OpenURI instead of resolving a handler itself. The
    # portal frontend still resolves standard mime types through mimeapps.list,
    # but it rejects custom x-scheme-handler entries and xdg-open reports
    # success regardless, so a downstream configuration may want the portal
    # backends without inheriting that dispatch change. Bundling it with the XDG
    # base directory option made the two impossible to configure independently.
    # Every value is mkDefault so a downstream configuration can override or
    # turn any of it off.
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
