from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


TRACK_CHANGES_CODEPOINT = 0xE673
ANDROID_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
WINDOWS_SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]


def render_master(font_path: Path, size: int = 1024) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    inset = round(size * 0.035)
    radius = round(size * 0.23)
    draw.rounded_rectangle(
        (inset, inset, size - inset, size - inset),
        radius=radius,
        fill=(14, 15, 22, 255),
        outline=(203, 184, 255, 82),
        width=max(2, round(size * 0.012)),
    )

    glyph = chr(TRACK_CHANGES_CODEPOINT)
    font = ImageFont.truetype(str(font_path), round(size * 0.67))
    bounds = font.getbbox(glyph)
    glyph_width = bounds[2] - bounds[0]
    glyph_height = bounds[3] - bounds[1]
    origin = (
        round((size - glyph_width) / 2 - bounds[0]),
        round((size - glyph_height) / 2 - bounds[1]),
    )

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).text(origin, glyph, font=font, fill=255)
    gradient = Image.new("RGBA", (size, size))
    pixels = gradient.load()
    start = (218, 205, 255)
    end = (132, 101, 231)
    for y in range(size):
        for x in range(size):
            ratio = (x + y) / (2 * (size - 1))
            pixels[x, y] = tuple(
                round(start[index] + (end[index] - start[index]) * ratio)
                for index in range(3)
            ) + (255,)
    image.alpha_composite(Image.composite(gradient, Image.new("RGBA", image.size), mask))
    return image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--flutter-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    args = parser.parse_args()

    font_path = (
        args.flutter_root
        / "bin"
        / "cache"
        / "artifacts"
        / "material_fonts"
        / "materialicons-regular.otf"
    )
    if not font_path.is_file():
        raise FileNotFoundError(font_path)

    master = render_master(font_path)
    source_path = args.project_root / "app" / "assets" / "branding" / "app_icon.png"
    source_path.parent.mkdir(parents=True, exist_ok=True)
    master.save(source_path)

    android_root = args.project_root / "app" / "android" / "app" / "src" / "main" / "res"
    for folder, size in ANDROID_SIZES.items():
        destination = android_root / folder / "ic_launcher.png"
        master.resize((size, size), Image.Resampling.LANCZOS).save(destination)

    windows_icon = (
        args.project_root
        / "app"
        / "windows"
        / "runner"
        / "resources"
        / "app_icon.ico"
    )
    master.save(windows_icon, format="ICO", sizes=[(size, size) for size in WINDOWS_SIZES])


if __name__ == "__main__":
    main()
