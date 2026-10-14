{
  lib,
  ...
}:
{
  imports = [
    ./comma.nix
    ./dolphin.nix
    ./editors.nix
    ./fastfetch.nix
    ./firefox.nix
    ./gtk.nix
    ./git.nix
    ./hyde.nix
    ./lockscreen.nix
    ./notifications.nix
    ./portal.nix
    ./qt.nix
    ./rofi.nix
    ./screenshots.nix
    ./shell.nix
    ./social.nix
    ./spotify.nix
    ./terminals.nix
    ./theme.nix
    ./uwsm.nix
    ./waybar.nix
    ./wlogout.nix
    ./xdg.nix
  ];

  options.hydenix.hm = {
    enable = lib.mkEnableOption "Enable Hydenix home-manager modules globally";
  };

  config = {
    hydenix.hm.enable = lib.mkDefault false;

    # A default, not a fixed value. home.stateVersion is the anchor home-manager uses to decide
    # which option defaults a configuration keeps, so it is the user's decision: pinning it here
    # means nobody can ever adopt a newer release's defaults without patching hydenix. It stays at
    # the release hydenix was last migrated to, so an untouched configuration keeps today's
    # behaviour and only a deliberate bump moves it.
    home.stateVersion = lib.mkDefault "25.05";

    # let home-manager control itself
    programs.home-manager.enable = true;
  };

}
