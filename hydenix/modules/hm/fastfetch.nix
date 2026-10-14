{
  config,
  lib,
  ...
}:

let
  cfg = config.hydenix.hm.fastfetch;
in
{
  options.hydenix.hm.fastfetch = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable fastfetch configuration";
    };
  };

  # The configuration and the HyDE logo set are seeded by the hyde module, which deploys everything
  # under HyDE's Configs/.config. Only the option remains, so a user configuration can still switch
  # fastfetch off.
  config = lib.mkIf cfg.enable { };
}
