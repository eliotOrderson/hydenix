#!/usr/bin/env bash
#
# Nested Hyprland test for hydenix.
#
# Opens a throwaway Hyprland instance inside the running Wayland session and points it at the
# configuration the flake currently builds. Nothing is installed and the live session is not
# touched, so this is the fast way to eyeball decoration, animations, shaders and keybinds
# before running `nixos-rebuild`.
#
# The config is assembled rather than used as-is, because startup.conf runs
#     dbus-update-activation-environment --systemd --all
#     systemctl --user import-environment
# which would import this nested session's environment into the user's real systemd/dbus session
# and can break the desktop that is already running. startup.conf is therefore left out, so the
# session daemons (waybar, dunst, swww, hypridle, ...) are deliberately not started.
#
# What it does cover: the flake's pinned Hyprland parsing the flake's generated HyDE config, read
# straight out of the home-manager generation, plus the hydenix generated includes
# (keybindings, monitors, userprefs, windowrules, workflows).
#
# usage:
#   lib/tests/nested-hyprland.sh                 # parse the config, then open a nested window
#   lib/tests/nested-hyprland.sh --verify-only   # parse only, no window (no GPU needed)
#   lib/tests/nested-hyprland.sh --quick         # also launch the preview clients (see below)
#   lib/tests/nested-hyprland.sh --exec kitty    # also launch something specific, repeatable
#   lib/tests/nested-hyprland.sh --quick --new-generation
#
# --quick starts the desktop preview listed in quick_mode_clients below: wallpaper daemon,
# wallpaper, bar and a terminal, so the window shows the actual desktop instead of an empty one.
# startup.conf is skipped, so without --quick or --exec a nested session is just Hyprland's default
# background colour and reads as black.
#
# --new-generation runs the session with the flake's freshly built generation ahead of the running
# system on PATH and XDG_DATA_DIRS, so the bar, launcher, terminal and wallpaper come from the build
# under test rather than from the installed one. Without it a bumped config is exercised against
# the old desktop components, which gives misleading results. It cannot bring the GL driver or the
# system services forward: those still come from the running system, so driver changes and
# multi-monitor/scale behaviour remain untestable here and need `nixos-rebuild` + reboot.
#
# wrap it in gamescope to check another resolution or refresh rate:
#   gamescope -W 2560 -H 1440 -r 144 -- lib/tests/nested-hyprland.sh --quick
#
# environment overrides:
#   HYDENIX_USER      home-manager user to read the generated config from (default: hydenix)
#   HYDENIX_FLAKE     flake reference to build (default: this repository)
#
set -euo pipefail

REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)
FLAKE=${HYDENIX_FLAKE:-"$REPO"}
USER_NAME=${HYDENIX_USER:-hydenix}
CONF_ATTR="nixosConfigurations.default"

die() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    # print the header comment, up to the first line of code
    sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'
}

verify_only=0
quick=0
new_generation=0
execs=()
while [ $# -gt 0 ]; do
    case "$1" in
    --verify-only)
        verify_only=1
        shift
        ;;
    --quick)
        quick=1
        shift
        ;;
    --new-generation)
        new_generation=1
        shift
        ;;
    --exec)
        [ $# -ge 2 ] || die "--exec needs a command"
        execs+=("$2")
        shift 2
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        die "unknown argument: $1 (try --help)"
        ;;
    esac
done

command -v nix >/dev/null || die "nix is not on PATH"

if [ "$(id -u)" -eq 0 ]; then
    die "run this as your normal user; Hyprland refuses to start as root"
fi

if [ -z "${WAYLAND_DISPLAY:-}${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    die "no Wayland session detected; a nested Hyprland needs a parent compositor"
fi

# ---------------------------------------------------------------------------
# quick mode (--quick): what gets launched inside the nested session
# ---------------------------------------------------------------------------
# One exec-once line per entry, in this order. The wallpaper daemon has to be running before the
# first `swww img`, hence the sleep. Edit this list to taste, or pass extra clients with --exec.
quick_mode_clients=(
    "swww-daemon"
    "sh -c 'sleep 2; swww img $HOME/.cache/hyde/wallpapers/swww.png'"
    "waybar"
    "git"
    "kitty"
)

if [ "$quick" -eq 1 ]; then
    execs+=("${quick_mode_clients[@]}")
fi

echo "==> resolving the configuration this flake builds"
hyde_dir=$(nix eval --raw "$FLAKE#$CONF_ATTR.pkgs.hyde")
hyprland=$(nix eval --raw "$FLAKE#$CONF_ATTR.pkgs.hyprland")
generation=$(nix build --no-link --print-out-paths \
    "$FLAKE#$CONF_ATTR.config.home-manager.users.$USER_NAME.home.activationPackage")
home_files="$generation/home-files"

[ -x "$hyprland/bin/Hyprland" ] || die "no Hyprland binary at $hyprland/bin/Hyprland"
[ -d "$home_files/.config/hypr" ] || die "no generated hypr config at $home_files/.config/hypr"

# Put the build under test ahead of the installed system, so the clients started by the nested
# session come from it too. Only the programs move: the GL driver (/run/opengl-driver) and the
# system services still belong to the running system.
if [ "$new_generation" -eq 1 ]; then
    toplevel=$(nix build --no-link --print-out-paths "$FLAKE#$CONF_ATTR.config.system.build.toplevel")
    export PATH="$generation/home-path/bin:$toplevel/sw/bin:$PATH"
    export XDG_DATA_DIRS="$generation/home-path/share:$toplevel/sw/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/test.conf" <<EOF
# Generated by lib/tests/nested-hyprland.sh - do not edit.
#
# Sources the visual and behavioural half of the flake's HyDE config. startup.conf is left out
# on purpose, see the header of that script.
source = $home_files/.local/share/hypr/variables.conf
source = $home_files/.local/share/hypr/defaults.conf
source = $home_files/.local/share/hypr/windowrules.conf
source = $home_files/.local/share/hypr/env.conf
source = $home_files/.local/share/hypr/dynamic.conf

# What .config/hypr/hyprland.conf normally sources, spelled out. That file also falls back to
# \$HOME/.local/share/hyde/hyprland.conf, which on an installed system is the *installed* config:
# sourcing it would mix the built and the installed configuration and produce bogus duplicate
# declaration errors ("Gesture will be overshadowed by a previous gesture").
source = $home_files/.config/hypr/keybindings.conf
source = $home_files/.config/hypr/windowrules.conf
source = $home_files/.config/hypr/monitors.conf
source = $home_files/.config/hypr/userprefs.conf
source = $home_files/.config/hypr/workflows.conf

source = $home_files/.local/share/hypr/finale.conf
EOF

if [ ${#execs[@]} -gt 0 ]; then
    {
        echo
        echo "# Clients requested with --quick/--exec, so the nested session is not an empty screen."
        for exec_line in "${execs[@]}"; do
            echo "exec-once = $exec_line"
        done
    } >>"$TMP/test.conf"
fi

echo "    hyprland:   $hyprland/bin/Hyprland"
echo "    hyde:       $hyde_dir"
echo "    generation: $generation"
echo "    clients:    $([ "$new_generation" -eq 1 ] && echo "build under test (--new-generation)" || echo "installed system")"
echo "    test conf:  $TMP/test.conf"
echo

echo "==> Hyprland --verify-config"
echo "    note: HyDE's config always emits a few 'Error parsing gradient' warnings and"
echo "    'source= globbing error' lines. Measured on this repository, the installed and the"
echo "    built config produce exactly the same ones, so the verdict that matters is the"
echo "    'config ok' at the end."
set +e
"$hyprland/bin/Hyprland" --verify-config -c "$TMP/test.conf"
verify_status=$?
set -e
if [ "$verify_status" -ne 0 ]; then
    die "Hyprland rejected the config (exit $verify_status)"
fi

if [ "$verify_only" -eq 1 ]; then
    exit 0
fi

echo
echo "==> starting nested Hyprland (close the window or Ctrl-C to stop)"
if [ ${#execs[@]} -eq 0 ]; then
    echo "    note: startup.conf is skipped, so nothing draws a wallpaper and no daemon starts."
    echo "    An empty Hyprland output is just Hyprland's default background colour, which reads as"
    echo "    black. Pass --quick (preview clients) or --exec <command> to put something in it:"
    echo "        $(basename "${BASH_SOURCE[0]}") --quick"
else
    echo "    launching inside the nested session:"
    for exec_line in "${execs[@]}"; do
        echo "        $exec_line"
    done
fi
echo
"$hyprland/bin/Hyprland" -c "$TMP/test.conf"
