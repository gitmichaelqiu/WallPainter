#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
asset_root="$repo_root/WallPainter/WallPainter.icon/Assets"
output="$repo_root/WallPainter/Resources/WallPainterStatusBarTemplate.png"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

render_silhouette() {
    local source="$1"
    local size="$2"
    local result="$work_dir/$3-silhouette.png"

    magick -size "$size" xc:white \
        -alpha off \
        \( "$source" -alpha extract -resize "${size}!" \) \
        -compose CopyOpacity \
        -composite \
        "$result"

    print -r -- "$result"
}

# These transforms mirror the visible layers in WallPainter.icon/icon.json. The
# panel contours are redrawn as continuous vectors to avoid raster edge gaps;
# the emblem itself remains the exact source asset from the icon package.
panel_source="$repo_root/Scripts/status-bar-panels.svg"
panel="$work_dir/panel.png"
magick -background none "$panel_source" -resize 1024x1024 "$panel"
wallpainter_mark="$(render_silhouette "$asset_root/ios-appearance-icon-transparent.png" 410x410 wallpainter-mark)"
composited="$work_dir/composited.png"
canvas="$work_dir/canvas.png"
scaled="$work_dir/scaled.png"
alpha="$work_dir/final-alpha.png"

magick -size 1024x1024 xc:none \
    "$panel" -geometry +0+0 -composite \
    "$canvas"

magick "$canvas" \
    "$wallpainter_mark" -geometry +566+565 -composite \
    -resize 36x36 \
    "$composited"

magick "$composited" \
    -trim \
    +repage \
    -resize 34x34 \
    -background none \
    -gravity center \
    -extent 36x36 \
    "$scaled"

magick "$scaled" \
    -alpha extract \
    -threshold 28% \
    "$alpha"

magick -size 36x36 xc:white \
    -alpha off \
    "$alpha" \
    -compose CopyOpacity \
    -composite \
    "$output"
