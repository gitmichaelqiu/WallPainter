#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
asset_root="$repo_root/WallPainter/WallPainter.icon/Assets"
output="$repo_root/WallPainter/Resources/WallPainterStatusBarTemplate.png"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

render_outline() {
    local source="$1"
    local size="$2"
    local name="$3"
    local edge="$work_dir/$name-edge.png"
    local result="$work_dir/$name-outline.png"

    magick "$source" \
        -alpha extract \
        -resize "${size}!" \
        -threshold 50% \
        -morphology EdgeOut Disk:52 \
        -morphology Close Disk:6 \
        "$edge"

    magick -size "$size" xc:white \
        -alpha off \
        \( "$edge" \) \
        -compose CopyOpacity \
        -composite \
        "$result"

    print -r -- "$result"
}

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

# These transforms mirror the visible layers in WallPainter.icon/icon.json.
back_panel="$(render_outline "$asset_root/4_shape1.png" 896x504 back-panel)"
front_panel="$(render_outline "$asset_root/6_shape2_rounded copy.png" 768x432 front-panel)"
wallpainter_mark="$(render_silhouette "$asset_root/ios-appearance-icon-transparent.png" 410x410 wallpainter-mark)"
composited="$work_dir/composited.png"
scaled="$work_dir/scaled.png"
alpha="$work_dir/final-alpha.png"

magick -size 1024x1024 xc:none \
    "$back_panel" -geometry +-2+223 -composite \
    "$front_panel" -geometry +205+362 -composite \
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
