{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.rofi;
in
{
  options.hydenix.hm.rofi = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable rofi module";
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = with pkgs; [
        rofi # application launcher
      ];

      activation.hydeRofiThemes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p "$HOME/.local/share/rofi/themes"
        $DRY_RUN_CMD find "$HOME/.local/share/hyde/rofi/themes" -type f -o -type l -exec ln -snf {} "$HOME/.local/share/rofi/themes/" \; 2>/dev/null || true
      '';
    };
  };
}
