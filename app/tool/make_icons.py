"""Generates the placeholder Melopet logo + Android launcher / notification icons.

When the real logo is ready, drop a 1024x1024 PNG at assets/images/logo.png and run
    python3 tool/make_icons.py --from assets/images/logo.png
(requires Pillow). Without --from it draws the placeholder (paw in a drop).
"""
import argparse
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

PINK = (249, 184, 207)
PINK2 = (231, 154, 192)
LAV = (199, 181, 242)
DEEP = (217, 102, 143)


def gradient(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + (size - y)) / (2 * size)  # top-right → bottom-left
            if t < 0.5:
                a, b, k = PINK, PINK2, t / 0.5
            else:
                a, b, k = PINK2, LAV, (t - 0.5) / 0.5
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * k) for i in range(3))
    return img


def draw_mark(d, w, drop_color, paw_color, ox=0, oy=0):
    # drop
    cx = ox + w * 0.5
    pts = []
    for i in range(0, 361, 3):
        a = math.radians(i)
        r = w * 0.28
        x = cx + r * math.cos(a)
        y = oy + w * 0.6 + r * math.sin(a)
        pts.append((x, y))
    d.polygon(pts, fill=drop_color)
    d.polygon([(cx, oy + w * 0.12), (cx - w * 0.25, oy + w * 0.5), (cx + w * 0.25, oy + w * 0.5)], fill=drop_color)
    # paw
    if paw_color is not None:
        d.ellipse([cx - w * 0.1, oy + w * 0.6, cx + w * 0.1, oy + w * 0.76], fill=paw_color)
        for a in (-0.9, -0.3, 0.3, 0.9):
            px = cx + math.sin(a) * w * 0.15
            py = oy + w * 0.61 - math.cos(a) * w * 0.13
            r = w * 0.045
            d.ellipse([px - r, py - r, px + r, py + r], fill=paw_color)


def placeholder(size=1024):
    bg = gradient(size)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.3), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)
    d = ImageDraw.Draw(out)
    draw_mark(d, size, (255, 255, 255, 245), DEEP + (255,))
    return out


def notification_icon(size):
    # white silhouette on transparent (Android status bar icons must be monochrome)
    img = Image.new("RGBA", (size * 4, size * 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = size * 4
    draw_mark(d, w, (255, 255, 255, 255), (0, 0, 0, 0))
    return img.resize((size, size), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="src")
    args = ap.parse_args()

    logo = Image.open(args.src).convert("RGBA") if args.src else placeholder()
    os.makedirs(os.path.join(ROOT, "assets", "images"), exist_ok=True)
    if not args.src:
        logo.save(os.path.join(ROOT, "assets", "images", "logo.png"))

    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        logo.resize((px, px), Image.LANCZOS).save(os.path.join(RES, f"mipmap-{folder}", "ic_launcher.png"))
    for folder, px in {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}.items():
        path = os.path.join(RES, f"drawable-{folder}")
        os.makedirs(path, exist_ok=True)
        notification_icon(px).save(os.path.join(path, "ic_stat_melopet.png"))

    web = os.path.join(ROOT, "web")
    if os.path.isdir(web):
        logo.resize((32, 32), Image.LANCZOS).save(os.path.join(web, "favicon.png"))
        for n, px in {"Icon-192.png": 192, "Icon-512.png": 512, "Icon-maskable-192.png": 192, "Icon-maskable-512.png": 512}.items():
            logo.resize((px, px), Image.LANCZOS).save(os.path.join(web, "icons", n))
    print("icons generated")


if __name__ == "__main__":
    main()
