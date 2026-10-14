{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.editors;
in
{
  options.hydenix.hm.editors = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable text editors module";
    };

    vscode = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable vscode";
      };

      # Kept so configurations that set it still evaluate. HyDE v26.08.21 dropped
      # Source/arcs/Code_Wallbash.vsix, so the package no longer carries an extension to deploy
      # and this now selects nothing.
      wallbash = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Deprecated: HyDE no longer ships the wallbash extension for vscode";
      };
    };

    neovim = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable neovim";
    };

    vim = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable vim";
    };

    default = lib.mkOption {
      type = lib.types.str;
      default = "code";
      description = "Default text editor";
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = with pkgs; [
        (lib.mkIf cfg.vim vim) # terminal text editor
        (lib.mkIf cfg.neovim neovim) # terminal text editor
      ];

      sessionVariables = {
        EDITOR = cfg.default;
        VISUAL = cfg.default;
      };
    };

    programs.vscode = lib.mkIf cfg.vscode.enable {
      enable = true;
      package = pkgs.vscode.fhs;
      mutableExtensionsDir = true;
    };

    xdg.mimeApps = {
      defaultApplications = {
        "text/plain" = [ "${cfg.default}.desktop" ];
        "application/x-shellscript" = [ "${cfg.default}.desktop" ];
        "text/css" = [ "${cfg.default}.desktop" ];
        "application/javascript" = [ "${cfg.default}.desktop" ];
        "application/json" = [ "${cfg.default}.desktop" ];
        "application/xml" = [ "${cfg.default}.desktop" ];
        "text/x-python" = [ "${cfg.default}.desktop" ];
        "text/x-java-source" = [ "${cfg.default}.desktop" ];
        "text/x-c++src" = [ "${cfg.default}.desktop" ];
        "text/x-csrc" = [ "${cfg.default}.desktop" ];
        "text/x-go" = [ "${cfg.default}.desktop" ];
        "text/x-typescript" = [ "${cfg.default}.desktop" ];
        "text/markdown" = [ "${cfg.default}.desktop" ];
      };
    };
  };
}
