{ pkgs, inputs }:
pkgs.stdenv.mkDerivation {
  name = "hyde-modified";
  src = inputs.hyde;

  nativeBuildInputs = with pkgs; [
    gnutar
  ];

  buildPhase = ''
    # remove assets folder
    rm -rf Source/assets

    # hyde-shell reaches hydectl and hyde-ipc through $PATH, and hydenix installs those from their
    # own flakes. The copies inside Configs/ would shadow them and carry their own nixpkgs.
    rm -rf Configs/.local/bin/hydectl
    rm -rf Configs/.local/bin/hyde-ipc

    # Unused: nothing in start_up.lua starts it, and the command variables.lua points at
    # (resetxdgportal.lua) does not exist in the tree.
    rm -rf Configs/.local/lib/hyde/resetxdgportal.sh

    # Update waybar killall command in all HyDE files
    find . -type f -print0 | xargs -0 sed -i 's/killall waybar/killall .waybar-wrapped/g'

    # update dunst
    find . -type f -print0 | xargs -0 sed -i 's/killall dunst/killall .dunst-wrapped/g'

    # update kitty
    find . -type f -print0 | xargs -0 sed -i 's/killall -SIGUSR1 kitty/killall -SIGUSR1 .kitty-wrapped/g'

    # fix find commands for symlinks
    #
    # The deployment hands HyDE symlinked trees: a home.file recursive entry is a real directory of
    # per-file links, so a walk that does not follow them reports the tree as empty and whatever it
    # was looking for is skipped without a message. `-H` follows only the directory named on the
    # command line, which is the one case that has to work here, and a bare `find` follows nothing.
    # Both become `-L`, which is what HyDE asks for in most of its other calls already.
    #
    # lua.dcol is where this hurts: nothing renders it, lua_state/colors.lua never appears, and the
    # theme switch reports the result only as "colour state is still incomplete", which takes
    # `hyde-shell reload` down with it. The same blind spot empties the theme templates and the
    # theme wallpapers.
    #
    # Executable files and *.sh only: a blanket pass would also rewrite Lua method calls, because
    # `arg:find "="` contains the same text. The loop at the end of this phase checks the result.
    find . -type f -executable -print0 | xargs -0 sed -i -e 's/find "/find -L "/g' -e 's/find -H /find -L /g'
    find . -type f -name "*.sh" -print0 | xargs -0 sed -i -e 's/find "/find -L "/g' -e 's/find -H /find -L /g'

    # HyDE redirects themesDir to the NixOS system profile whenever /run/current-system exists,
    # assuming GTK themes are installed distro-wide there. hydenix installs them into the user
    # profile, so the redirect points at a directory holding none of HyDE's themes and
    # `hyde-shell theme` reports success while changing nothing.
    #
    # The assignment becomes `:` rather than a comment. It is the only statement in that if-block,
    # and a block containing nothing but a comment is empty, which bash rejects with
    # "syntax error near unexpected token `fi'" — a failure that only shows up when the theme
    # switch runs on a real machine. `:` keeps the block non-empty and does nothing.
    #
    # Matched by text rather than by line number: this used to be `sed -i '187,190d'`, and once
    # upstream inserted a line above the block the range landed inside the xsettingsd sed.
    sed -i 's|^\([[:space:]]*\)export themesDir=/run/current-system/sw/share/themes.*|\1: # themesDir is left in the user profile, where hydenix installs the themes.|' \
      Configs/.local/lib/hyde/theme.switch.sh

    # rofilaunch closes any rofi that is already up. HyDE's keybind already does that with
    # `pkill -x rofi ||`, so this one only makes the launcher exit without opening. Matched by
    # content: the line moved from 5 to 2 between releases, and deleting 5 would now take the
    # `else` out of the block below it.
    sed -i '/^pkill rofi && exit 0$/d' Configs/.local/lib/hyde/rofilaunch.sh

    # Every patch above rewrites shell that only runs inside a session, so a syntax error in one of
    # them surfaces as a failed activation on a real machine and nowhere earlier. That happened: a
    # patch that replaced the only statement of an if-block with a comment left the block empty,
    # and bash refused the file with "syntax error near unexpected token `fi'" long after the build
    # had reported success. Parse the shell here instead.
    #
    # The same pass guards the find rewrite: a spelling its substitution does not cover leaves a walk
    # that cannot see into the symlinked trees, and that failure is silent rather than fatal, so it
    # has to fail here or nowhere.
    while IFS= read -r script; do
      # Only real shell scripts: a shebang whose interpreter is bash. Matching on the word "bash"
      # anywhere in the first line also catches .dcol files, which are SVG documents.
      head -n 1 "$script" | grep -qE '^#!.*[/ ]bash' || continue
      if ! bash -n "$script"; then
        echo "hydenix: $script does not parse after patching" >&2
        exit 1
      fi
      if grep -nE 'find -H|find "' "$script"; then
        echo "hydenix: $script still has a find that does not follow symlinks" >&2
        exit 1
      fi
    done < <(find Configs/.local -type f)

    # BUILD GRUB THEMES
    mkdir -p $out/share/grub/themes
    tar xzf ./Source/arcs/Grub_Retroboot.tar.gz -C $out/share/grub/themes
    tar xzf ./Source/arcs/Grub_Pochita.tar.gz -C $out/share/grub/themes

    # BUILD ICONS
    mkdir -p $out/share/icons
    tar xzf ./Source/arcs/Icon_Wallbash.tar.gz -C $out/share/icons

    # BUILD GTK THEME
    mkdir -p $out/share/themes
    tar xzf ./Source/arcs/Gtk_Wallbash.tar.gz -C $out/share/themes
  '';

  installPhase = ''
    mkdir -p $out
    cp -r . $out

    # grimblast is not part of HyDE's Configs/: Scripts/dots/hyde.toml downloads it into
    # ~/.local/lib/hyde/screenshot at install time, and HyDE then calls it by that absolute path
    # ("$LIB_DIR/hyde/screenshot/grimblast" in screenshot.sh and screenrecord.sh). A copy on PATH
    # would not be found, so the file has to sit inside the tree this derivation installs.
    mkdir -p $out/Configs/.local/lib/hyde/screenshot
    ln -s ${pkgs.grimblast}/bin/grimblast $out/Configs/.local/lib/hyde/screenshot/grimblast
  '';
}
