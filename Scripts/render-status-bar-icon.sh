#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
asset_root="$repo_root/WallPainter/WallPainter.icon/Assets"
output="$repo_root/WallPainter/Resources/WallPainterStatusBarTemplate.png"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Trace the actual alpha silhouettes from the icon package. This keeps the
# status item tied to the app icon's real curves without shipping the colorful
# application icon into the menu bar.
trace_silhouette() {
    local source="$1"
    local size="$2"
    local name="$3"
    local mask="$work_dir/$name-mask.png"
    local trace="$work_dir/$name-trace.svg"

    magick "$source" \
        -alpha extract \
        -resize "$size" \
        -threshold 50% \
        "$mask"

    inkscape "$mask" \
        --actions="select-all;object-trace:2,true,false,false,2,1,0.2;export-filename:$trace;export-do" \
        >/dev/null 2>&1

    # object-trace writes the foreground contour before its background contour.
    # Extract only that first path and discard Inkscape's embedded source image.
    perl -0777 -ne \
        '@paths = /<path\b.*?\bd="([^"]+)"/sg; print $paths[0] // ""' \
        "$trace"
}

front_path="$(trace_silhouette "$asset_root/6_shape2_rounded copy.png" 1024x576 front)"
mark_path="$(trace_silhouette "$asset_root/ios-appearance-icon-transparent.png" 512x512 mark)"
vector="$work_dir/wallpainter-status-bar.svg"
rendered="$work_dir/wallpainter-status-bar-rendered.png"
alpha="$work_dir/wallpainter-status-bar-alpha.png"

print -r -- "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\" viewBox=\"0 0 64 64\">" > "$vector"
print -r -- "  <g transform=\"translate(32 32) scale(1.1) translate(-32 -32)\">" >> "$vector"
print -r -- "    <g fill=\"none\" stroke=\"#fff\" stroke-width=\"14\" stroke-linecap=\"round\" stroke-linejoin=\"round\" vector-effect=\"non-scaling-stroke\">" >> "$vector"
# The rear contour intentionally stays open and joins the traced front panel at
# its lower-left and upper-right edges, following the requested icon sketch.
print -r -- "      <path d=\"M 16.2 45.2 C 13.2 44.8 11.7 42.2 10.8 39.4 L 7.8 30.2 C 7 27.8 8.8 25.1 12 23.5 L 39.3 9.4 C 42.4 7.8 45.5 7.3 47 9.8 C 48.5 11.9 52 17.8 54.8 21\" stroke-width=\"3.5\"/>" >> "$vector"
print -r -- "      <path d=\"$front_path\" transform=\"translate(8 21) scale(.055)\"/>" >> "$vector"
print -r -- "    </g>" >> "$vector"
print -r -- "    <path d=\"$mark_path\" transform=\"translate(34.5 34.5) scale(.045)\" fill=\"#fff\"/>" >> "$vector"
print -r -- "  </g>" >> "$vector"
print -r -- "</svg>" >> "$vector"

# Render oversized, then reduce with Lanczos so the 18-point menu-bar image
# keeps continuous antialiased contours instead of jagged bitmap edges.
inkscape "$vector" \
    --export-filename="$rendered" \
    --export-width=288 \
    >/dev/null 2>&1

magick "$rendered" \
    -resize 36x36 \
    -alpha extract \
    -level 0,35% \
    "$alpha"

magick -size 36x36 xc:white \
    -alpha off \
    "$alpha" \
    -compose CopyOpacity \
    -composite \
    "$output"
