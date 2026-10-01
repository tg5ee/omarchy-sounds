#!/usr/bin/env bash
# Omarchy Sounds — uninstaller. Keeps ~/.config/omarchy-sounds (your sounds)
# unless you pass --purge.

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-sounds"
HYPR="$HOME/.config/hypr"
UNITS=(omarchy-sounds.service omarchy-sounds-shutdown.service)

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

PLUGIN_ID="tomg.sounds"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

say "Removing the Sounds bar widget"
if command -v omarchy >/dev/null; then omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true; fi
rm -f "$PLUGIN_DIR/manifest.json" "$PLUGIN_DIR/Panel.qml"
rmdir "$PLUGIN_DIR" 2>/dev/null || true
if command -v omarchy-shell >/dev/null; then omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true; fi

say "Removing Hyprland hooks"
sed -i '/^-- omarchy-sounds >>>$/,/^-- <<< omarchy-sounds$/d' "$HYPR/hyprland.lua"
sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$HYPR/hyprland.lua"  # drop the blank line install.sh added before the block
rm -f "$HYPR/omarchy_sounds.lua"
if command -v hyprctl >/dev/null && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then hyprctl reload >/dev/null; fi

say "Removing commands"
rm -f "$HOME/.local/bin/omarchy-sounds" "$HOME/.local/bin/omarchy-sounds-play" "$HOME/.local/bin/omarchy-sounds-daemon"
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-sounds"

say "Removing Omarchy hooks"
for hook in battery-low theme-set post-update; do
  rm -f "$HOME/.config/omarchy/hooks/$hook.d/omarchy-sounds"
done

# Stop after the player is gone, so uninstalling doesn't play the shutdown sound
say "Removing services"
systemctl --user disable --now "${UNITS[@]}" >/dev/null 2>&1 || true
for unit in "${UNITS[@]}"; do rm -f "$HOME/.config/systemd/user/$unit"; done
systemctl --user daemon-reload

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$CONF"; say "Removed $CONF"
else
  say "Kept your settings and sounds in $CONF (use --purge to remove)"
fi
