{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.hyde;

  inherit (pkgs) hyde;

  # HyDE builds its rock tree with luarocks on first run, which needs the network and a compiler.
  # nixpkgs carries every rock lua_env.json pins at the same version, so the search paths point at
  # them and the runtime tree is never built.
  #
  # lgi is absent and cannot be supplied here. nixpkgs marks it broken for lua 5.4 and 5.5 because lgi
  # 0.9.2 resumes coroutines with the three-argument lua_resume; patching that one call site makes it
  # compile, but not load, because the build installs lgi/corelgilua51.so while lgi's own init.lua
  # requires lgi.core. It is not optional in practice even though lua_env.json lists it as such:
  # lib/hyde/open.lua requires it before anything else, so `hyde-shell open` -- and the browser,
  # editor and explorer binds HyDE points at it -- aborts. Setting hyde.config.app.* to plain commands
  # avoids open.lua entirely; that is a per-machine choice, so it lives in the user's config.
  luaRocks = with pkgs.lua5_4.pkgs; [
    luasec
    argparse
    dkjson
    luasocket
    luafilesystem
  ];

  luaPath = lib.concatMapStringsSep ";" (
    p: "${p}/share/lua/5.4/?.lua;${p}/share/lua/5.4/?/init.lua"
  ) luaRocks;

  luaCPath = lib.concatMapStringsSep ";" (p: "${p}/lib/lua/5.4/?.so") luaRocks;

  # The paths home.file symlinks below. Kept as one list because hydeSeed has to exclude exactly
  # these: rsync would otherwise descend through a symlink into the store and try to write there.
  #
  # HyDE walks several of these trees with find, and a recursive home.file entry is a real directory
  # holding one symlink per file, which a plain find does not look through. sources/hyde.nix rewrites
  # those calls to `find -L` for that reason, so a tree that moves into this list has to be covered by
  # that patch: outside it, find reports an empty directory and HyDE skips the contents silently.
  managedPaths = [
    ".local/lib/hyde"
    ".local/share/hyde"
    ".local/share/hypr"
    ".local/share/wallbash"
    ".local/share/waybar"
    ".local/share/fastfetch/presets/hyde"
    ".local/share/kio/servicemenus/hydewallpaper.desktop"
    ".local/share/kxmlgui5/dolphin"
    ".local/share/dolphin"
    ".local/bin/hyde-shell"
    ".config/hyde/wallbash"
    ".config/uwsm"
  ];

  # Shaders are handled one file at a time rather than as one of the trees above. That directory is
  # mixed by design: the shader selector lists whatever is in it, a machine drops its own .frag
  # beside HyDE's, and HyDE writes its compiled cache there. A directory symlink would put the cache
  # and the user's own shader inside the store, where neither can be written. Linking each shipped
  # shader still lets them track upstream.
  #
  # The dot-files are left out for the same reason the directory is: .compiled.cache.glsl is a cache
  # HyDE rewrites. Leaving them out of this list also keeps them out of the seed's exclusions, so
  # hydeSeed deploys them as ordinary writable files.
  shaderPaths = map (name: ".config/hypr/shaders/${name}") (
    builtins.filter (name: builtins.substring 0 1 name != ".") (
      builtins.attrNames (builtins.readDir "${hyde}/Configs/.config/hypr/shaders")
    )
  );

  # rsync matches these against the transfer root, which is Configs/.config or Configs/.local, so
  # the ~/.config and ~/.local prefixes come off and the rest is anchored with a leading slash.
  #
  # config.home.file is part of the list because a path home-manager manages must not also be
  # seeded. checkLinkTargets runs before every switch and refuses to take over a real file it did
  # not create, so a collision fails the switch on the run after the seed happened to win the race
  # against linkGeneration. Deriving the two lists from the same options keeps them in step.
  #
  # Kept as a list and fed to rsync through --exclude-from rather than as --exclude arguments: the
  # theme entries under ~/.config/hyde/themes carry names with spaces in them ("Catppuccin Mocha"),
  # and an unquoted expansion of those splits into words that rsync then reads as source paths.
  seedExcludePatterns = map (p: "/${lib.removePrefix ".config/" (lib.removePrefix ".local/" p)}") (
    managedPaths ++ shaderPaths ++ builtins.attrNames config.home.file
  );

  # Seed HyDE's configuration as real, writable files, once.
  #
  # HyDE's own installer distinguishes per file between "sync" (its copy wins) and "preserve"
  # (only write when nothing is there). This makes a coarser split on purpose: the trees in
  # `managedPaths` are the parts HyDE only reads and they keep tracking upstream, and everything
  # else is HyDE's and the user's to write afterwards. Re-imposing a declarative copy of files that
  # a theme switch rewrites is what the previous design did, and it is why changing a keybinding
  # took a full `nixos-rebuild`.
  #
  # The trade-off: a file seeded here does not pick up a new upstream default on its own. Delete it
  # and switch again to get HyDE's current version back.
  #
  # A script rather than an inline activation body so it can be run on its own: lib/tests/
  # nested-hyprland.sh deploys into a throwaway HOME with this exact script, which is what makes
  # that test evidence about the real deployment instead of a reimplementation of it.
  seed = pkgs.writeShellScript "hydenix-hyde-seed" ''
        set -euo pipefail

        run=${pkgs.rsync}/bin/rsync
        # --ignore-existing is the "preserve" rule for the whole tree; the chmod exists because the
        # source lives in the store, where files are read-only, and a copy the user cannot edit is no
        # better than the symlink this avoids.
        #
        # The two trees, plus the dot-files that sit at the root of Configs/ rather than inside one of
        # them: .gtkrc-2.0 is GTK2's theme file and the directory passes would never reach it.
        excludes=$(mktemp)
        trap 'rm -f "$excludes"' EXIT
        cat >"$excludes" <<'HYDENIX_SEED_EXCLUDES'
    ${lib.concatStringsSep "\n" seedExcludePatterns}
    HYDENIX_SEED_EXCLUDES

        for pair in "${hyde}/Configs/.config:$HOME/.config" \
          "${hyde}/Configs/.local:$HOME/.local" \
          "${hyde}/Configs/.gtkrc-2.0:$HOME/.gtkrc-2.0" \
          "${hyde}/Configs/.zshenv:$HOME/.zshenv"; do
          src=''${pair%%:*}
          dst=''${pair##*:}
          if [ -d "$src" ]; then
            $run --archive --ignore-existing --no-owner --no-group \
              --chmod=Du+rwx,Fu+rw --exclude-from="$excludes" "$src/" "$dst/"
          elif [ -f "$src" ] && [ ! -e "$dst" ]; then
            cp "$src" "$dst"
            chmod u+rw "$dst"
          fi
        done

        # Directories HyDE writes into that nothing in Configs/ creates.
        mkdir -p "$HOME/.local/state/hyde/lua_state"
        mkdir -p "$HOME/.cache/hyde"

        # hyde-shell refuses to run any of HyDE's *.lua subcommands unless this tree exists, and posts a
        # "Lua environment not found! Please run 'hyde-shell luainit'" notification whenever it does
        # not, which is what HyDE's own startup hits. `luainit` cannot build the tree here: it drives
        # the system luarocks, built for lua 5.2, and expects openssl headers under /usr/include. The
        # existence of the directory is the whole check, and the rocks those scripts load come from
        # nixpkgs through LUA_PATH/LUA_CPATH, so creating it is enough.
        for ver in 5.4 5.5; do
          mkdir -p "$HOME/.local/state/hyde/lua_env/share/lua/$ver" \
            "$HOME/.local/state/hyde/lua_env/lib/lua/$ver"
        done

        # The icon and GTK themes are extracted from Source/arcs into the package's own share/, not into
        # Configs/, so the tree-wide pass above never reaches them. HyDE's scripts and dunst's icon paths
        # refer to them by their $HOME/.local/share location, and wallbash recolours both in place, so
        # they have to be writable copies rather than symlinks to the store.
        for pair in "${hyde}/share/icons/Wallbash-Icon:$HOME/.local/share/icons/Wallbash-Icon" \
          "${hyde}/share/themes/Wallbash-Gtk:$HOME/.local/share/themes/Wallbash-Gtk"; do
          src=''${pair%%:*}
          dst=''${pair##*:}
          [ -d "$src" ] || continue
          [ -e "$dst" ] && continue
          mkdir -p "$(dirname "$dst")"
          cp -r "$src" "$dst"
          chmod -R u+rwX "$dst"
        done

        # Waybar's shipped style.css and includes/includes.json carry the HyDE maintainer's home
        # directory as an absolute path (89 entries under /home/khing in v26.08.21), so the bar imports
        # a stylesheet that is not there and never draws. waybar.py rewrites both against the real HOME,
        # and -u also derives the icon sizes, the border radius and global.css from the current theme.
        # It touches nothing that needs a running session.
        #
        # Failure is reported and not fatal: a switch that cannot fix a stylesheet should still
        # complete, and the message says what the bar will look like until it is fixed.
        waybar_py="$HOME/.local/lib/hyde/waybar.py"
        if [ -f "$waybar_py" ] && [ -e "$HOME/.config/waybar/config.jsonc" ]; then
          ${pkgs.python3}/bin/python3 "$waybar_py" -u ||
            echo "hydenix: waybar.py -u failed; the bar keeps the placeholder paths HyDE ships" >&2
        fi
  '';
in
{
  options.hydenix.hm.hyde = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable hyde module";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      with pkgs;
      [
        hyde
        Bibata-Modern-Ice
        Tela-circle-dracula
        hyprquery
        hydectl
        hyde-ipc
        hyde-config
        python-pyamdgpuinfo
        wf-recorder
        rsync

        # HyDE's core dependency list (Scripts/pkg_core.lst). These are the programs its scripts
        # call by name, so the list has to move whenever that file does: the names a config uses
        # are the contract between HyDE and this layer. Anything not already installed by another
        # module belongs here.
        awww
        hyprpolkitagent
        # HyDE starts this one as its blue light filter
        # (hyde.config.start.blue_light_filter_daemon in Scripts/.../variables.lua), and app2unit
        # reports a missing command as a desktop notification, so leaving it out puts an error card
        # on screen at every login.
        hyprsunset
        cliphist
        wl-clipboard
        wl-clip-persist
        grim
        slurp
        satty
        playerctl
        brightnessctl
        udiskie
        networkmanagerapplet
        blueman
        pamixer
        xdg-user-dirs
        libnotify
        parallel
        jq
        imagemagick
        unzip
        # HyDE ships a swaync configuration and Scripts/dots/swaync.toml declares the package for
        # it, so the dot is inert without this. dunst stays the daemon HyDE starts by default.
        swaynotificationcenter
        # Monitor management, and the tool HyDE's own documentation points at for monitor.conf.
        nwg-displays

        # HyDE downloads these two at install time as well (Scripts/dots/hyde.toml). Both are called
        # by bare name, so a package on PATH is enough.
        #
        # app2unit is the one that matters: `hyde-shell app` execs it to put a command into a
        # systemd unit, and HyDE starts the bar, the wallpaper, notifications and every other daemon
        # through that call. Missing it, the session comes up with the configuration loaded, no
        # error anywhere, and an empty desktop.
        app2unit
        # The terminal launcher the xdg-terminal-exec protocol resolves through PATH.
        xdg-terminal-exec

        # Hyprland's own helpers, which the deleted hyprland module used to declare.
        hyprpicker
        hyprcursor
        hyprutils

        # The Lua runtime HyDE's configuration needs. Hyprland embeds its own interpreter, but
        # `hyde-shell reload lua` and the config's optional modules look for these.
        lua5_4

        # Fonts HyDE's defaults name (Scripts/dots/archives.toml). MapleMono is in that manifest
        # too but nixpkgs does not carry it, and no HyDE default selects it.
        cantarell-fonts
        nerd-fonts.jetbrains-mono
        nerd-fonts.caskaydia-cove
        nerd-fonts.mononoki
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
      ]
      ++ luaRocks;

    # HyDE starts the session against the Lua entry point. It loads HyDE's own modules first and
    # ~/.config/hypr/hyprland.lua last, so that file is where user settings belong.
    home.sessionVariables = {
      HYPRLAND_CONFIG = "${config.xdg.configHome}/hypr/hyprland.lua";
      LUA_PATH = "${luaPath};;";
      LUA_CPATH = "${luaCPath};;";
    };

    fonts.fontconfig.enable = true;

    # HyDE's own code and shipped data. HyDE only ever reads these, so a store symlink is correct
    # and they follow `nixos-rebuild`.
    #
    # Anything HyDE or its theme system writes is deliberately absent here and is seeded as a real
    # file by hydeSeed below. A store symlink cannot be written, which is exactly what the previous
    # design fought: it had to force-replace read-only links and reimplement HyDE's settings in Nix
    # to get anything changed.
    home.file = {
      ".local/lib/hyde" = {
        source = "${hyde}/Configs/.local/lib/hyde";
        recursive = true;
        force = true;
      };
      ".local/share/hyde" = {
        source = "${hyde}/Configs/.local/share/hyde";
        recursive = true;
        force = true;
      };
      # The Hyprland Lua configuration: hyde.lua, its modules, the Lua schema hyq dumps themes
      # against, and the shipped hyprlock layouts.
      ".local/share/hypr" = {
        source = "${hyde}/Configs/.local/share/hypr";
        recursive = true;
        force = true;
      };
      ".local/share/wallbash" = {
        source = "${hyde}/Configs/.local/share/wallbash";
        recursive = true;
        force = true;
      };
      ".local/share/waybar" = {
        source = "${hyde}/Configs/.local/share/waybar";
        recursive = true;
        force = true;
      };
      ".local/share/fastfetch/presets/hyde" = {
        source = "${hyde}/Configs/.local/share/fastfetch/presets/hyde";
        recursive = true;
      };
      ".local/share/kio/servicemenus/hydewallpaper.desktop" = {
        source = "${hyde}/Configs/.local/share/kio/servicemenus/hydewallpaper.desktop";
      };
      ".local/share/kxmlgui5/dolphin" = {
        source = "${hyde}/Configs/.local/share/kxmlgui5/dolphin";
        recursive = true;
      };
      ".local/share/dolphin" = {
        source = "${hyde}/Configs/.local/share/dolphin";
        recursive = true;
      };
      ".config/hyde/wallbash" = {
        source = "${hyde}/Configs/.config/hyde/wallbash";
        recursive = true;
        force = true;
      };
      # The shader selector lists this directory and offers nothing when it is absent. Each shipped
      # shader is linked on its own so the directory itself stays real; see shaderPaths above.
      ".config/uwsm" = {
        source = "${hyde}/Configs/.config/uwsm";
        recursive = true;
        force = true;
      };

      # hyde-shell resolves $LIB_DIR relative to itself, so the entry point is a wrapper that adds
      # the one Python module HyDE imports but nixpkgs keeps outside the interpreter's path.
      ".local/bin/hyde-shell" = {
        source = pkgs.writeShellScript "hyde-shell" ''
          export PYTHONPATH="${pkgs.python-pyamdgpuinfo}/${pkgs.python3.sitePackages}:$PYTHONPATH"
          exec ${pkgs.bashInteractive}/bin/bash "${hyde}/Configs/.local/bin/hyde-shell" "$@"
        '';
        executable = true;
      };
    }
    // lib.genAttrs shaderPaths (path: {
      source = "${hyde}/Configs/${path}";
      force = true;
    });

    home.activation.hydeSeed = lib.hm.dag.entryAfter [ "linkGeneration" ] "${seed}";

    # fixes cava from not initializing on boot
    home.activation.createCavaConfig = lib.hm.dag.entryAfter [ "hydeSeed" ] ''
      mkdir -p "$HOME/.config/cava"
      touch "$HOME/.config/cava/config"
      chmod 644 "$HOME/.config/cava/config"
    '';
  };
}
