#!/bin/bash
set -euo pipefail

FONTS_CONF_SRC="/usr/share/cjk-fonts-flatpak/fonts.conf"

for home_dir in /home/*; do
    [ -d "$home_dir" ] || continue
    user_conf_dir="$home_dir/.var/app/org.mozilla.firefox/config/fontconfig"
    [ -f "$user_conf_dir/fonts.conf" ] && continue
    mkdir -p "$user_conf_dir"
    cp "$FONTS_CONF_SRC" "$user_conf_dir/fonts.conf"
done
