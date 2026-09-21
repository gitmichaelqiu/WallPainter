#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
asset_root="$repo_root/WallPainter/WallPainter.icon/Assets"
output="$repo_root/WallPainter/Resources/WallPainterStatusBarTemplate.png"
pdf_output="$repo_root/WallPainter/Resources/WallPainterStatusBarTemplate.pdf"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Trace the actual alpha silhouettes from the icon package. This keeps the
# status item tied to the app icon's real curves without shipping the colorful
# application icon into the menu bar.
trace_silhouette() {
    local source="$1"
    local size="$2"
    local name="$3"
    local simplify="${4:-false}"
    local mask="$work_dir/$name-mask.png"
    local trace="$work_dir/$name-trace.svg"
    local actions="select-all;object-trace:2,true,false,false,2,1,0.2;"

    magick "$source" \
        -alpha extract \
        -resize "$size" \
        -threshold 50% \
        "$mask"

    if [[ "$simplify" == true ]]; then
        actions+="path-simplify:0.1;"
    fi
    actions+="export-filename:$trace;export-do"

    inkscape "$mask" \
        --actions="$actions" \
        >/dev/null 2>&1

    # object-trace writes the foreground contour before its background contour.
    # Extract only that first path and discard Inkscape's embedded source image.
    perl -0777 -ne \
        '@paths = /<path\b.*?\bd="([^"]+)"/sg; print $paths[0] // ""' \
        "$trace"
}

back_path="$(trace_silhouette "$asset_root/4_shape1.png" 1024x576 back true)"
if [[ "$back_path" != *" -123.1492,"* ]]; then
    print -u2 "Unexpected traced rear-panel path format"
    exit 1
fi
back_outer_path="${back_path%% -123.1492,*}"
front_path="$(trace_silhouette "$asset_root/6_shape2_rounded copy.png" 1024x576 front true)"
mark_path="$(trace_silhouette "$asset_root/ios-appearance-icon-transparent.png" 512x512 mark false)"
back_vector="$work_dir/wallpainter-status-bar-back.svg"
front_vector="$work_dir/wallpainter-status-bar-front.svg"
mark_vector="$work_dir/wallpainter-status-bar-mark.svg"
back_rendered="$work_dir/wallpainter-status-bar-back-rendered.png"
front_rendered="$work_dir/wallpainter-status-bar-front-rendered.png"
mark_rendered="$work_dir/wallpainter-status-bar-mark-rendered.png"
connector_vector="$work_dir/wallpainter-status-bar-connector.svg"
connector_rendered="$work_dir/wallpainter-status-bar-connector-rendered.png"
back_alpha="$work_dir/wallpainter-status-bar-back-alpha.png"
back_mask="$work_dir/wallpainter-status-bar-back-mask.png"
back_masked_alpha="$work_dir/wallpainter-status-bar-back-masked-alpha.png"
back_masked="$work_dir/wallpainter-status-bar-back-masked.png"
panels="$work_dir/wallpainter-status-bar-panels.png"
back_joined="$work_dir/wallpainter-status-bar-back-joined.png"
rendered="$work_dir/wallpainter-status-bar-rendered.png"
alpha="$work_dir/wallpainter-status-bar-alpha.png"
template_vector="$work_dir/wallpainter-status-bar-template.svg"

print -r -- "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\" viewBox=\"0 0 64 64\">" > "$back_vector"
print -r -- "  <g transform=\"translate(32 32) scale(1.1) translate(-32 -32)\">" >> "$back_vector"
print -r -- "    <path d=\"$back_path\" transform=\"translate(-7 10) scale(.07)\" fill=\"none\" stroke=\"#fff\" stroke-width=\"48\" stroke-linecap=\"round\" stroke-linejoin=\"round\" vector-effect=\"non-scaling-stroke\"/>" >> "$back_vector"
print -r -- "  </g>" >> "$back_vector"
print -r -- "</svg>" >> "$back_vector"

print -r -- "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\" viewBox=\"0 0 64 64\">" > "$front_vector"
print -r -- "  <g transform=\"translate(32 32) scale(1.1) translate(-32 -32)\">" >> "$front_vector"
print -r -- "    <path d=\"$front_path\" transform=\"translate(8 21) scale(.055)\" fill=\"none\" stroke=\"#fff\" stroke-width=\"48\" stroke-linecap=\"round\" stroke-linejoin=\"round\" vector-effect=\"non-scaling-stroke\"/>" >> "$front_vector"
print -r -- "  </g>" >> "$front_vector"
print -r -- "</svg>" >> "$front_vector"

print -r -- "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\" viewBox=\"0 0 64 64\">" > "$mark_vector"
print -r -- "  <g transform=\"translate(32 32) scale(1.1) translate(-32 -32)\">" >> "$mark_vector"
print -r -- "    <path d=\"$mark_path\" transform=\"translate(34.5 34.5) scale(.055)\" fill=\"#fff\"/>" >> "$mark_vector"
print -r -- "  </g>" >> "$mark_vector"
print -r -- "</svg>" >> "$mark_vector"

print -r -- "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\" viewBox=\"0 0 64 64\">" > "$connector_vector"
# Continue the traced rear contour into the front panel's upper-right corner.
# Match the panels' non-scaling stroke so the join stays smooth and uniform at
# every export resolution.
print -r -- "  <path d=\"M 53.8 16.0 C 54.1 17.3 54.2 18.7 53.4 19.95\" fill=\"none\" stroke=\"#fff\" stroke-width=\"48\" stroke-linecap=\"round\" stroke-linejoin=\"round\" vector-effect=\"non-scaling-stroke\"/>" >> "$connector_vector"
print -r -- "</svg>" >> "$connector_vector"

# Keep a vector copy for AppKit to rasterize at the status-item's actual size.
# The local stroke widths compensate for each traced panel's source transform;
# unlike the PNG pipeline, this path is never reduced before AppKit displays it.
print -r -- "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\" viewBox=\"0 0 64 64\">" > "$template_vector"
print -r -- "  <g>" >> "$template_vector"
print -r -- "    <g transform=\"translate(32 32) scale(1.1) translate(-32 -32)\">" >> "$template_vector"
print -r -- "      <path d=\"$back_outer_path\" transform=\"translate(-7 10) scale(.07)\" fill=\"none\" stroke=\"#fff\" stroke-width=\"40\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" >> "$template_vector"
print -r -- "    </g>" >> "$template_vector"
print -r -- "  </g>" >> "$template_vector"
print -r -- "  <path d=\"M 53.8 16.0 C 54.1 17.3 54.2 18.7 53.4 19.95\" fill=\"none\" stroke=\"#fff\" stroke-width=\"3\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" >> "$template_vector"
print -r -- "  <g transform=\"translate(32 32) scale(1.1) translate(-32 -32)\">" >> "$template_vector"
print -r -- "    <path d=\"$front_path\" transform=\"translate(8 21) scale(.055)\" fill=\"none\" stroke=\"#fff\" stroke-width=\"50\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" >> "$template_vector"
print -r -- "    <path d=\"$mark_path\" transform=\"translate(34.5 34.5) scale(.055)\" fill=\"#fff\"/>" >> "$template_vector"
print -r -- "  </g>" >> "$template_vector"
print -r -- "</svg>" >> "$template_vector"

inkscape "$template_vector" \
    --export-filename="$pdf_output" \
    >/dev/null 2>&1

inkscape "$back_vector" \
    --export-filename="$back_rendered" \
    --export-width=2048 \
    >/dev/null 2>&1

inkscape "$front_vector" \
    --export-filename="$front_rendered" \
    --export-width=2048 \
    >/dev/null 2>&1

inkscape "$mark_vector" \
    --export-filename="$mark_rendered" \
    --export-width=2048 \
    >/dev/null 2>&1

inkscape "$connector_vector" \
    --export-filename="$connector_rendered" \
    --export-width=2048 \
    >/dev/null 2>&1

# The traced rear panel contains a short inner horizontal contour. It is the
# same edge as the front panel's top edge at menu-bar scale, so composing both
# traces directly makes that edge look heavier. Erase only that rear contour;
# all other traced geometry remains unchanged.
magick "$back_rendered" -alpha extract "$back_alpha"
magick -size 2048x2048 xc:white \
    -fill black \
    -draw 'rectangle 477,512 1820,677' \
    "$back_mask"
magick "$back_alpha" "$back_mask" \
    -compose Multiply \
    -composite \
    "$back_masked_alpha"
magick -size 2048x2048 xc:white \
    -alpha off \
    "$back_masked_alpha" \
    -compose CopyOpacity \
    -composite \
    "$back_masked"

magick "$back_masked" "$connector_rendered" \
    -compose over \
    -composite \
    "$back_joined"
# Place the join behind the front panel. Its original top contour then masks
# the connector endpoint, leaving a continuous rear line without a cap or a
# second stroke over the front edge.
magick "$back_joined" "$front_rendered" \
    -compose over \
    -composite \
    "$panels"
magick "$panels" "$mark_rendered" \
    -compose over \
    -composite \
    "$rendered"

# Render oversized, then reduce with Lanczos to a high-resolution resource. The
# status item displays this image at 18 points, so retaining 512 pixels here
# prevents the menu-bar renderer from magnifying a low-resolution bitmap when the icon is
# inspected or composited on a high-density display.
magick "$rendered" \
    -filter Lanczos \
    -resize 512x512 \
    -alpha extract \
    -level 0,25% \
    "$alpha"

magick -size 512x512 xc:white \
    -alpha off \
    "$alpha" \
    -compose CopyOpacity \
    -composite \
    "$output"
