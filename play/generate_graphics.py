#!/usr/bin/env python3
"""Generates the two Play Console graphics that are a hard listing requirement:
the 512x512 app icon and the 1024x500 feature graphic.

Both are derived from the single brand source (``app/assets/brand/logo.png``) so
they can be regenerated after a logo change instead of being hand-edited:

    python3 play/generate_graphics.py

Play rejects transparency in both images, so everything is flattened onto an
opaque background. The background is picked from the logo's own luminance: a
light logo gets the brand blue, a dark logo gets white - never white-on-white.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
LOGO = ROOT / "app" / "assets" / "brand" / "logo.png"
OUT_DIR = Path(__file__).resolve().parent / "graphics"

# site.themeColor (#004ac6) and a darker shade for the gradient.
BRAND_BLUE = (0, 74, 198)
BRAND_DARK = (0, 28, 84)
WHITE = (255, 255, 255)

APP_NAME = "PMapa"
TAGLINE = "Plan it. Map it. Share it."

ICON_SIZE = 512
ICON_LOGO_SCALE = 0.84  # small breathing room; Play applies its own masking
FEATURE_W, FEATURE_H = 1024, 500
# Play may crop the outer edges of the feature graphic in some placements, so
# keep every meaningful pixel inside this centred safe area.
FEATURE_SAFE_W, FEATURE_SAFE_H = 924, 400

MAX_ICON_BYTES = 1024 * 1024  # Play limit: 1 MB
MAX_FEATURE_BYTES = 15 * 1024 * 1024  # Play limit: 15 MB

FONT_DIRS = [ROOT / "app" / "assets" / "fonts"]
FALLBACK_BOLD = [
    Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf"),
    Path("/System/Library/Fonts/SFNSDisplay.ttf"),
    Path("/System/Library/Fonts/Helvetica.ttc"),
]
FALLBACK_REGULAR = [
    Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
    Path("/System/Library/Fonts/SFNSText.ttf"),
    Path("/System/Library/Fonts/Helvetica.ttc"),
]


def project_fonts() -> list[Path]:
    """Every TrueType/OpenType file shipped with the app, sorted for stability."""
    found: list[Path] = []
    for directory in FONT_DIRS:
        if directory.is_dir():
            for pattern in ("**/*.ttf", "**/*.otf"):
                found.extend(sorted(directory.glob(pattern)))
    return found


def pick_font_file(*, bold: bool) -> Path | None:
    """Prefers the project's own font; falls back to a system one, else None."""
    candidates = [p for p in project_fonts() if "italic" not in p.name.lower()]
    if bold:
        weighted = [p for p in candidates if any(
            w in p.name.lower() for w in ("bold", "semibold", "black", "700", "600"))]
    else:
        weighted = [p for p in candidates if any(
            w in p.name.lower() for w in ("regular", "medium", "400"))]
    for pool in (weighted, candidates):
        if pool:
            return pool[0]
    for path in (FALLBACK_BOLD if bold else FALLBACK_REGULAR):
        if path.exists():
            return path
    return None


def load_font(path: Path | None, size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    """Loads `path` at `size`, degrading to Pillow's built-in font if it fails."""
    if path is not None:
        try:
            return ImageFont.truetype(str(path), size)
        except OSError:
            pass  # unreadable/unsupported face - fall through to the default
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # Pillow < 10.1 has no size argument
        return ImageFont.load_default()


def mean_luminance(logo: Image.Image) -> float:
    """Average perceived brightness (0-255) of the logo's visible pixels."""
    rgba = logo.convert("RGBA")
    total = 0.0
    count = 0
    for r, g, b, a in rgba.getdata():
        if a > 32:  # ignore the transparent frame around the mark
            total += 0.299 * r + 0.587 * g + 0.114 * b
            count += 1
    return total / count if count else 0.0


def scaled(logo: Image.Image, size: int) -> Image.Image:
    return logo.convert("RGBA").resize((size, size), Image.LANCZOS)


def build_icon(logo: Image.Image, background: tuple[int, int, int]) -> Image.Image:
    """512x512 opaque icon: the mark centred on a flat brand background."""
    canvas = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), background + (255,))
    mark = scaled(logo, int(ICON_SIZE * ICON_LOGO_SCALE))
    offset = ((ICON_SIZE - mark.width) // 2, (ICON_SIZE - mark.height) // 2)
    canvas.alpha_composite(mark, offset)
    return canvas.convert("RGB")


def vertical_gradient(size: tuple[int, int],
                      top: tuple[int, int, int],
                      bottom: tuple[int, int, int]) -> Image.Image:
    width, height = size
    canvas = Image.new("RGB", size, top)
    draw = ImageDraw.Draw(canvas)
    span = max(height - 1, 1)
    for y in range(height):
        t = y / span
        colour = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        draw.line([(0, y), (width, y)], fill=colour)
    return canvas


def build_feature_graphic(logo: Image.Image, logo_is_dark: bool) -> Image.Image:
    """1024x500 banner: mark + name + tagline, centred inside the safe area."""
    canvas = vertical_gradient((FEATURE_W, FEATURE_H), BRAND_BLUE, BRAND_DARK).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    title_font = load_font(pick_font_file(bold=True), 104)
    tagline_font = load_font(pick_font_file(bold=False), 42)

    title_box = draw.textbbox((0, 0), APP_NAME, font=title_font)
    tagline_box = draw.textbbox((0, 0), TAGLINE, font=tagline_font)
    title_w, title_h = title_box[2] - title_box[0], title_box[3] - title_box[1]
    tagline_w, tagline_h = tagline_box[2] - tagline_box[0], tagline_box[3] - tagline_box[1]

    mark_size = 260
    gap = 56
    line_gap = 22
    text_w = max(title_w, tagline_w)
    text_h = title_h + line_gap + tagline_h

    group_w = mark_size + gap + text_w
    if group_w > FEATURE_SAFE_W:  # shrink the mark rather than spill out of the safe area
        mark_size = max(160, mark_size - (group_w - FEATURE_SAFE_W))
        group_w = mark_size + gap + text_w
    group_h = max(mark_size, text_h, 1)
    if group_h > FEATURE_SAFE_H:
        mark_size = max(160, mark_size - (group_h - FEATURE_SAFE_H))
        group_h = max(mark_size, text_h)

    left = (FEATURE_W - group_w) // 2
    mark_top = (FEATURE_H - mark_size) // 2

    if logo_is_dark:
        # A dark mark would disappear on the blue gradient: give it a white plate.
        plate_pad = 26
        draw.ellipse(
            [left - plate_pad, mark_top - plate_pad,
             left + mark_size + plate_pad, mark_top + mark_size + plate_pad],
            fill=WHITE + (255,),
        )
    canvas.alpha_composite(scaled(logo, mark_size), (left, mark_top))

    text_left = left + mark_size + gap
    text_top = (FEATURE_H - text_h) // 2
    draw.text((text_left - title_box[0], text_top - title_box[1]),
              APP_NAME, font=title_font, fill=WHITE + (255,))
    draw.text((text_left - tagline_box[0], text_top + title_h + line_gap - tagline_box[1]),
              TAGLINE, font=tagline_font, fill=(214, 228, 255, 255))

    return canvas.convert("RGB")


def save(image: Image.Image, path: Path, limit: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)
    size = path.stat().st_size
    reopened = Image.open(path)
    assert reopened.size == image.size, f"{path.name}: unexpected size {reopened.size}"
    assert reopened.mode == "RGB", f"{path.name}: must have no alpha channel, got {reopened.mode}"
    assert size <= limit, f"{path.name}: {size} bytes exceeds the Play limit of {limit}"
    print(f"  {path.relative_to(ROOT)}  {reopened.size[0]}x{reopened.size[1]}  "
          f"{reopened.mode}  {size / 1024:.0f} KB")


def main() -> int:
    if not LOGO.is_file():
        print(f"brand source not found: {LOGO}", file=sys.stderr)
        return 1

    logo = Image.open(LOGO)
    luminance = mean_luminance(logo)
    logo_is_dark = luminance < 128
    icon_bg = BRAND_BLUE if not logo_is_dark else WHITE

    bold = pick_font_file(bold=True)
    regular = pick_font_file(bold=False)
    print(f"source: {LOGO.relative_to(ROOT)} ({logo.size[0]}x{logo.size[1]}, "
          f"mean luminance {luminance:.0f} -> {'dark' if logo_is_dark else 'light'} mark)")
    print(f"fonts:  title={bold} tagline={regular}")
    print("written:")

    save(build_icon(logo, icon_bg), OUT_DIR / "icon-512.png", MAX_ICON_BYTES)
    save(build_feature_graphic(logo, logo_is_dark),
         OUT_DIR / "feature-graphic-1024x500.png", MAX_FEATURE_BYTES)
    return 0


if __name__ == "__main__":
    sys.exit(main())
