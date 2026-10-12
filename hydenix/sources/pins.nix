# Packages HyDE ships configuration for.
#
# HyDE's config files (Configs/.config/*) and its wallbash templates (.dcol) are written against
# the desktop stack that was current at the pinned `hyde` revision. They are therefore frozen to
# the `nixpkgs-hyde` input and bumped together with `hyde`: a config written for one stack is
# wrong for another, and "themed colour silently stops applying" looks like a broken configuration
# to the user, which is worse than the extra closure.
#
# Only programs are listed. Library and framework attributes (gtk3, glib, hyprutils,
# gsettings-desktop-schemas, qt6, kdePackages) are deliberately left alone, for two reasons:
#
#   - base packages depend on them, so replacing them would invalidate the binary cache for
#     everything downstream;
#   - nixpkgs refuses to build a wrapper that mixes two Qt versions. The NixOS sddm module
#     appends `pkgs.qt6.qtwayland` from the base nixpkgs whenever wayland is enabled, so pinning
#     kdePackages puts Qt 6.10 and Qt 6.11 into the same sddm wrapper and fails the build with
#     "detected mismatched Qt dependencies". The Qt/KDE stack is therefore all-or-nothing.
#
# The pinned programs carry their own pinned copies of those libraries in their closures, so the
# versions HyDE's configs actually meet are unchanged.
{ inputs }:

let
  pinned = import inputs.nixpkgs-hyde {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };

  # Single source of truth: the overlay is built from this list and the assertion in
  # modules/system/nix.nix reads it back, so the two cannot drift apart.
  names = [
    # Window manager, session and the compositor ecosystem HyDE scripts drive through hyprctl
    "hyprland"
    "hyprlock"
    "hypridle"
    "hyprpicker"
    "hyprsunset"
    "hyprcursor"
    "xdg-desktop-portal-hyprland"
    "uwsm"

    # Desktop components HyDE writes configuration for
    "waybar"
    "rofi"
    "dunst"
    "swaylock"
    "wlogout"

    # HyDE drives this through its own backend script: wallpaper.swww.sh calls `swww query`,
    # `swww-daemon` and `swww img`. nixpkgs 26.05 renamed the package and the binaries to awww,
    # which those scripts do not call, so the old build stays pinned with the rest of the bundle.
    "swww"

    # Applications in HyDE's config surface
    "kitty"
    "vim"
    "fish"
    "zsh"
    "starship"
    "fastfetch"
    "lsd"
    "satty"
    "mangohud"
    "cava"
    "vscode"
    "discord"
    "vesktop"
    "spotify"
    "nwg-look"
    "xsettingsd"
    "libinput-gestures"
  ];
in
{
  inherit names pinned;

  overlay =
    final: prev:
    builtins.listToAttrs (
      map (name: {
        inherit name;
        value = pinned.${name};
      }) names
    );
}
