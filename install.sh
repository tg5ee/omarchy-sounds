#!/usr/bin/env bash
# Omarchy Sounds — installer.
#
# What it does (the one line it adds to your config is fenced with
# "omarchy-sounds" markers, and ./uninstall.sh removes exactly that):
#   1. installs omarchy-sounds, omarchy-sounds-play and omarchy-sounds-daemon to
#      ~/.local/bin, and the event list to ~/.local/share/omarchy-sounds
#   2. writes ~/.config/hypr/omarchy_sounds.lua and requires it from hyprland.lua
#   3. installs two systemd user services: the event watcher (lock, notifications,
#      devices, power) and the one that plays the shutdown sound
#   4. adds battery-low, theme-set and post-update Omarchy hooks
#   5. creates ~/.config/omarchy-sounds/{config,sounds/} (your settings are kept;
#      settings for new events are added)
#   6. installs the "Sounds" bar widget (~/.config/omarchy/plugins/tomg.sounds) and
#      adds it to the right side of the bar

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-sounds"
HYPR="$HOME/.config/hypr"
UNIT_DIR="$HOME/.config/systemd/user"
SHARE="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-sounds"
HOOKS="$HOME/.config/omarchy/hooks"
UNITS=(omarchy-sounds.service omarchy-sounds-shutdown.service)
PLUGIN_ID="tomg.sounds"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
BEGIN="-- omarchy-sounds >>>"
END="-- <<< omarchy-sounds"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

# Event switches and settings share one namespace (window-open -> WINDOW_OPEN), so an
# event named like a setting (e.g. "volume" vs VOLUME) would silently break both.
dupes=$(grep -o '^[A-Z_]*=' "$SRC/config.default" | sort | uniq -d | tr -d =)
[ -z "$dupes" ] || { echo "config.default defines these keys twice: $dupes" >&2; exit 1; }

command -v pw-play >/dev/null || command -v paplay >/dev/null || command -v mpv >/dev/null \
  || warn "No audio player found (pw-play, paplay or mpv); sounds won't play until one is installed."

say "Installing commands to $BIN"
mkdir -p "$BIN"
install -m755 "$SRC/bin/omarchy-sounds" "$SRC/bin/omarchy-sounds-play" "$SRC/bin/omarchy-sounds-daemon" "$BIN/"
mkdir -p "$SHARE"
install -m644 "$SRC/share/events.tsv" "$SHARE/events.tsv"

say "Setting up $CONF"
mkdir -p "$CONF/sounds"
[ -f "$CONF/config" ] || cp "$SRC/config.default" "$CONF/config"
# Upgrades: add a switch for every event (and any new setting) the config doesn't have yet
while IFS= read -r line; do
  [[ $line =~ ^([A-Z_]+)= ]] || continue
  grep -q "^${BASH_REMATCH[1]}=" "$CONF/config" || echo "$line" >> "$CONF/config"
done < "$SRC/config.default"
cp "$SRC/sounds/README.md" "$CONF/sounds/README.md"
# Ship any sounds bundled with the repo, without overwriting yours
find "$SRC/sounds" -maxdepth 1 -type f \( -name '*.wav' -o -name '*.ogg' -o -name '*.oga' -o -name '*.flac' -o -name '*.mp3' \) \
  -exec cp -n {} "$CONF/sounds/" \;

say "Installing services (event watcher, shutdown sound)"
mkdir -p "$UNIT_DIR"
for unit in "${UNITS[@]}"; do install -m644 "$SRC/systemd/$unit" "$UNIT_DIR/$unit"; done
systemctl --user daemon-reload
systemctl --user enable "${UNITS[@]}" >/dev/null 2>&1
systemctl --user start omarchy-sounds-shutdown.service
# restart (not start) so re-running the installer picks up a new daemon
systemctl --user restart omarchy-sounds.service

say "Adding Omarchy hooks (battery-low, theme-set, post-update)"
for hook in battery-low theme-set post-update; do
  mkdir -p "$HOOKS/$hook.d"
  install -m755 "$SRC/hooks/$hook" "$HOOKS/$hook.d/omarchy-sounds"
done

say "Hooking into Hyprland"
install -m644 "$SRC/hypr/omarchy_sounds.lua" "$HYPR/omarchy_sounds.lua"
if ! grep -qF -- "$BEGIN" "$HYPR/hyprland.lua"; then
  cp "$HYPR/hyprland.lua" "$HYPR/hyprland.lua.bak.$(date +%s)"
  printf '\n%s\nrequire("hypr.omarchy_sounds")\n%s\n' "$BEGIN" "$END" >> "$HYPR/hyprland.lua"
fi

if command -v hyprctl >/dev/null && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  hyprctl reload >/dev/null
  errors=$(hyprctl configerrors)
  if [ -n "${errors//[[:space:]]/}" ]; then warn "Hyprland reported config errors:"; echo "$errors"; fi
fi

say "Installing the Sounds bar widget"
mkdir -p "$PLUGIN_DIR"
panel_changed=0
if [ -f "$PLUGIN_DIR/Panel.qml" ] && ! cmp -s "$SRC/plugin/Panel.qml" "$PLUGIN_DIR/Panel.qml"; then panel_changed=1; fi
install -m644 "$SRC/plugin/manifest.json" "$SRC/plugin/Panel.qml" "$PLUGIN_DIR/"
if command -v omarchy-shell >/dev/null && omarchy-shell shell listPlugins >/dev/null 2>&1; then
  if [ "$panel_changed" = 1 ]; then
    # The shell's plugin hot-reload keeps serving the previously compiled QML,
    # so an updated panel only shows up after a shell restart.
    echo "    Restarting the Omarchy shell to load the updated panel"
    omarchy restart shell >/dev/null 2>&1 || true
    for _ in $(seq 20); do omarchy-shell shell listPlugins >/dev/null 2>&1 && break; sleep 0.5; done
  fi
  omarchy-shell shell rescanPlugins >/dev/null
  if ! grep -q "\"$PLUGIN_ID\"" "$HOME/.config/omarchy/shell.json" 2>/dev/null; then
    omarchy plugin enable "$PLUGIN_ID" >/dev/null && echo "    Added to the right side of the bar (move it with: omarchy bar move $PLUGIN_ID --section left|center|right)"
  fi
else
  warn "Omarchy shell isn't running; enable the widget later with: omarchy plugin enable $PLUGIN_ID"
fi

say "Done. Drop your sounds into $CONF/sounds (see README.md there), then:"
echo "    omarchy-sounds status"
echo "    omarchy-sounds test"
