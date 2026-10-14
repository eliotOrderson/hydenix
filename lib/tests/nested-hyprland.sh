#!/usr/bin/env bash
#
# Nested Hyprland test for hydenix.
#
# Deploys the configuration this flake builds into a throwaway HOME and starts a nested Hyprland
# against it inside the running Wayland session. Nothing is installed and the live session is not
# touched, so this is the fast way to see whether a change to the deployment actually produces a
# working desktop before running `nixos-rebuild`.
#
# The deployment is not reimplemented here: it runs the same `hydenix-hyde-seed` script that
# `home.activation.hydeSeed` runs, read out of the flake. A test that reproduced the copy logic
# could pass while the real activation was broken, which is the failure mode this is meant to catch.
#
# What it covers: the seeded config tree, the Lua entry point, the bar, the launcher, the wallpaper
# daemon and the theme state, all against the Hyprland this flake pins.
#
# What it cannot cover: the GL driver and the system services still come from the running system,
# so driver changes and multi-monitor/scale behaviour need `nixos-rebuild` and a reboot. SDDM, real
# input devices and direct scanout are likewise out of reach here.
#
# usage:
#   lib/tests/nested-hyprland.sh                 # deploy, verify the config, open a nested window
#   lib/tests/nested-hyprland.sh --verify-only   # deploy and parse only, no window
#   lib/tests/nested-hyprland.sh --exec kitty    # also launch something specific, repeatable
#   lib/tests/nested-hyprland.sh --keep          # keep the deployed HOME and print its path
#
# environment overrides:
#   HYDENIX_USER      home-manager user to deploy for (default: hydenix)
#   HYDENIX_FLAKE     flake reference to build (default: this repository)
#
set -euo pipefail

REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)
FLAKE=${HYDENIX_FLAKE:-"$REPO"}
USER_NAME=${HYDENIX_USER:-hydenix}
CONF_ATTR="nixosConfigurations.default"
HM_ATTR="$CONF_ATTR.config.home-manager.users.$USER_NAME.home"

die() {
    echo "error: $*" >&2
    exit 1
}

usage() {
    sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'
}

verify_only=0
keep=0
execs=()
while [ $# -gt 0 ]; do
    case "$1" in
    --verify-only)
        verify_only=1
        shift
        ;;
    --keep)
        keep=1
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
[ "$(id -u)" -eq 0 ] && die "run this as your normal user; Hyprland refuses to start as root"
[ -n "${WAYLAND_DISPLAY:-}${HYPRLAND_INSTANCE_SIGNATURE:-}" ] ||
    die "no Wayland session detected; a nested Hyprland needs a parent compositor"

NIX=(nix --extra-experimental-features dynamic-derivations)

echo "==> resolving the build under test"
hyprland=$("${NIX[@]}" eval --raw "$FLAKE#$CONF_ATTR.pkgs.hyprland")
hyde=$("${NIX[@]}" eval --raw "$FLAKE#$CONF_ATTR.pkgs.hyde")
seed=$("${NIX[@]}" eval --raw "$FLAKE#$HM_ATTR.activation.hydeSeed.data")
generation=$("${NIX[@]}" build --no-link --print-out-paths "$FLAKE#$HM_ATTR.activationPackage")

[ -x "$hyprland/bin/Hyprland" ] || die "no Hyprland binary at $hyprland/bin/Hyprland"
[ -x "$seed" ] || die "the hydeSeed activation script is not executable: $seed"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/hydenix-nested.XXXXXX")
cleanup() {
    # Kill first, then delete: the instances hold the socket and the log open, and a failing delete
    # must not be what stops them from being signalled.
    pkill -f "$TMP" 2>/dev/null || true
    if [ "$keep" -eq 1 ]; then
        echo "kept: $TMP"
    else
        # The linked tree keeps store modes, which are read-only, so make it writable before the
        # recursive delete or rm stops at the first directory it cannot descend into.
        chmod -R u+w "$TMP" 2>/dev/null || true
        rm -rf "$TMP" || true
    fi
}
trap cleanup EXIT

HOME_DIR="$TMP/home"
mkdir -p "$HOME_DIR"

echo "    hyprland:   $hyprland"
echo "    hyde:       $hyde"
echo "    seed:       $seed"
echo "    generation: $generation"
echo "    home:       $HOME_DIR"
echo

# ---------------------------------------------------------------------------
# deploy through the real artifacts, in the order the activation uses
# ---------------------------------------------------------------------------
# `home-files` is the tree of symlinks home-manager's linkGeneration creates, taken straight out of
# the built generation rather than reproduced here. Modes are not preserved: the tree is read-only
# in the store, and the seed below has to be able to write beside it.
echo "==> deploying the home-manager linked files"
cp -a --no-preserve=mode,ownership "$generation/home-files/." "$HOME_DIR/"

echo "==> running the hydeSeed activation script against the throwaway HOME"
export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export XDG_DATA_HOME="$HOME_DIR/.local/share"
export XDG_STATE_HOME="$HOME_DIR/.local/state"
export XDG_CACHE_HOME="$HOME_DIR/.cache"
export XDG_DATA_DIRS="$generation/home-path/share:/run/current-system/sw/share:${XDG_DATA_DIRS:-}"
export PATH="$generation/home-path/bin:$hyprland/bin:$HOME_DIR/.local/bin:$PATH"

"$seed"

[ -f "$HOME_DIR/.config/hypr/hyprland.lua" ] || die "the seed did not deploy ~/.config/hypr/hyprland.lua"
[ -f "$HOME_DIR/.local/share/hypr/hyde.lua" ] || die "the seed did not deploy ~/.local/share/hypr/hyde.lua"

if remaining=$(grep -rl '/home/khing/' "$HOME_DIR/.config/waybar" 2>/dev/null); then
    die "waybar config still carries the upstream author's home path: $remaining"
fi
echo "    deployment ok, no /home/khing paths left under ~/.config/waybar"

# ---------------------------------------------------------------------------
# parse check
# ---------------------------------------------------------------------------
echo
echo "==> Hyprland --verify-config against the deployed entry point"
set +e
"$hyprland/bin/Hyprland" --verify-config -c "$HOME_DIR/.config/hypr/hyprland.lua" 2>&1 | tail -8
status=${PIPESTATUS[0]}
set -e
[ "$status" -eq 0 ] || die "Hyprland rejected the deployed config (exit $status)"

[ "$verify_only" -eq 1 ] && exit 0

# ---------------------------------------------------------------------------
# nested session
# ---------------------------------------------------------------------------
# HyDE starts its daemons through `hyde-shell app -u ... -t service`, which registers systemd user
# units. That is deliberately not exercised here: the units would land in the live user manager.
# The clients are launched directly instead, so this covers the configuration and not the unit
# wiring.
#
# HyDE ships no wallpaper of its own — those come with the theme packages — so one is generated.
# The Lua is assembled line by line rather than through a quoted heredoc: the argument to awww img
# needs its own single quotes, and interpolating them into a double-quoted Lua string terminates it.
wallpaper="$TMP/wallpaper.png"
if command -v magick >/dev/null 2>&1; then
    magick -size 2560x1440 gradient:'#1e1e2e-#89b4fa' "$wallpaper"
else
    wallpaper=""
fi

{
    echo
    echo "-- Appended by lib/tests/nested-hyprland.sh for this run only."
    echo 'hl.on("hyprland.start", function()'
    echo '	hl.exec_cmd("waybar")'
    echo '	hl.exec_cmd("kitty")'
    if [ -n "$wallpaper" ]; then
        echo '	hl.exec_cmd("awww-daemon")'
        printf '\thl.exec_cmd("sh -c \x27sleep 3; awww img %s\x27")\n' "$wallpaper"
    fi
    for one in "${execs[@]}"; do
        printf '\thl.exec_cmd("%s")\n' "$one"
    done
    echo 'end)'
} >>"$HOME_DIR/.config/hypr/hyprland.lua"

echo
echo "==> starting nested Hyprland (close the window or Ctrl-C to stop)"
"$hyprland/bin/Hyprland" -c "$HOME_DIR/.config/hypr/hyprland.lua" >"$TMP/nested.log" 2>&1 &
hpid=$!

sig=""
for _ in $(seq 1 40); do
    sleep 0.5
    kill -0 "$hpid" 2>/dev/null || {
        echo "nested Hyprland exited early:" >&2
        tail -20 "$TMP/nested.log" >&2
        exit 1
    }
    for d in "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/hypr/*/; do
        [ -S "$d/.socket.sock" ] || continue
        s=$(basename "$d")
        [ "$s" = "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && continue
        sig="$s"
    done
    [ -n "$sig" ] && break
done
[ -n "$sig" ] || die "the nested instance never created a socket"

sleep 8
echo
echo "==> layers in the nested session"
hyprctl -i "$sig" layers 2>&1 | sed -n '1,20p'
echo
echo "==> config errors reported by the nested session"
hyprctl -i "$sig" configerrors 2>&1 | head -10
echo
echo "==> wallpaper daemon"
ap=$(pgrep -f awww-daemon | head -1 || true)
if [ -n "$ap" ]; then
    awl=$(tr '\0' '\n' <"/proc/$ap/environ" | sed -n 's/^WAYLAND_DISPLAY=//p')
    WAYLAND_DISPLAY="$awl" awww query 2>&1 | head -5
else
    echo "no awww-daemon running"
fi
