"""Draw the Purrage app icon and write the Windows .ico.

The brief is doc-wip/product_naming_and_visual_identity_brief.md: a ginger cat paw
entering from the upper left, pinning a scruffy, distressed dust bunny on a warm
beige rounded square, with small muted impact marks and no text.

    python tool/make_icon.py

Writes assets/icon/purrage.png (1024) and windows/runner/resources/app_icon.ico.

Shapes are built as silhouettes: fill a mask, outline the mask's edge once, then
paste the highlights through the same mask. That keeps one clean outline around
the whole paw (and the whole dust bunny) instead of a line where the parts meet.
"""

import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCALE = 2
SIZE = 1024

BACKDROP = (241, 226, 200, 255)
BACKDROP_EDGE = (228, 208, 174, 255)
PAW = (240, 154, 62, 255)
PAW_LIGHT = (247, 184, 102, 255)
BUNNY = (214, 212, 204, 255)
BUNNY_LIGHT = (233, 231, 224, 255)
INK = (58, 42, 30, 255)
MARK = (207, 186, 152, 255)
GLINT = (255, 255, 255, 255)

INK_WIDTH = 15


def px(value: float) -> int:
    return int(round(value * SCALE))


def box(*values):
    return tuple(px(v) for v in values)


def rounded_silhouette(draw, **kwargs):
    """The icon's rounded square, used for the backdrop and the final clip."""
    draw.rounded_rectangle(
        (px(18), px(18), px(SIZE - 18), px(SIZE - 18)),
        radius=px(215),
        **kwargs,
    )


def filled(mask: Image.Image, colour) -> Image.Image:
    layer = Image.new("RGBA", mask.size, colour)
    out = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    out.paste(layer, (0, 0), mask)
    return out


def outlined(mask: Image.Image, width: int = INK_WIDTH) -> Image.Image:
    """One outline around the whole silhouette, not around each part."""
    grown = mask.filter(ImageFilter.MaxFilter(2 * px(width) + 1))
    ring = ImageChops.subtract(grown, mask)
    return Image.composite(Image.new("RGBA", mask.size, INK),
                           Image.new("RGBA", mask.size, (0, 0, 0, 0)), ring)


def mask_of(size, paint) -> Image.Image:
    mask = Image.new("L", size, 0)
    paint(ImageDraw.Draw(mask))
    return mask


def backdrop() -> Image.Image:
    canvas = Image.new("RGBA", (px(SIZE), px(SIZE)), (0, 0, 0, 0))
    rounded_silhouette(ImageDraw.Draw(canvas), fill=BACKDROP, outline=BACKDROP_EDGE, width=px(4))
    return canvas


def paw_shapes() -> Image.Image:
    size = (px(SIZE), px(SIZE))

    def paint(draw):
        # The arm is a wedge out of the corner, so it meets the pad along
        # diagonals instead of showing the straight edges of a box.
        draw.polygon([box(-220, -220), box(392, -96), box(64, 392)], fill=255)
        draw.ellipse(box(60, 24, 740, 620), fill=255)
        for cx, cy, rx, ry in [
            (620, 436, 108, 100),
            (532, 568, 108, 100),
            (392, 636, 102, 96),
            (240, 626, 94, 90),
        ]:
            draw.ellipse(box(cx - rx, cy - ry, cx + rx, cy + ry), fill=255)

    mask = mask_of(size, paint)
    out = Image.alpha_composite(filled(mask, PAW), outlined(mask))

    highlights = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(highlights)
    for cx, cy, rx, ry in [
        (270, 250, 84, 46),
        (430, 200, 88, 50),
        (560, 258, 70, 44),
        (300, 420, 76, 40),
        (462, 392, 68, 38),
        (612, 448, 40, 22),
        (524, 578, 40, 22),
        (386, 640, 38, 20),
        (236, 628, 34, 18),
    ]:
        draw.ellipse(box(cx - rx, cy - ry, cx + rx, cy + ry), fill=PAW_LIGHT)
    out.alpha_composite(Image.composite(highlights, Image.new("RGBA", size, (0, 0, 0, 0)), mask))
    return out


def bunny_shapes() -> Image.Image:
    size = (px(SIZE), px(SIZE))
    puffs = [
        (640, 560, 132),
        (742, 592, 128),
        (806, 676, 120),
        (744, 766, 126),
        (622, 796, 124),
        (532, 724, 118),
        (556, 618, 112),
        (700, 690, 150),
    ]

    def paint(draw):
        for cx, cy, radius in puffs:
            draw.ellipse(box(cx - radius, cy - radius, cx + radius, cy + radius), fill=255)

    mask = mask_of(size, paint)
    out = Image.alpha_composite(filled(mask, BUNNY), outlined(mask, width=13))

    # The face sits clear of the toes, on a lighter patch of fluff.
    draw = ImageDraw.Draw(out)
    draw.ellipse(box(600, 606, 804, 776), fill=BUNNY_LIGHT)

    # Distressed: uneven eyes, raised inner brows, a small tense mouth.
    draw.ellipse(box(632, 650, 680, 706), fill=INK)
    draw.ellipse(box(720, 660, 762, 710), fill=INK)
    draw.ellipse(box(644, 660, 660, 678), fill=GLINT)
    draw.ellipse(box(730, 670, 744, 686), fill=GLINT)
    draw.arc(box(616, 606, 690, 662), start=205, end=300, fill=INK, width=px(11))
    draw.arc(box(708, 612, 780, 666), start=240, end=335, fill=INK, width=px(11))
    draw.arc(box(668, 706, 728, 744), start=200, end=340, fill=INK, width=px(10))
    return out


def wisps(draw) -> None:
    for (x0, y0), (x1, y1) in [
        ((566, 536), (516, 482)),
        ((828, 612), (886, 566)),
        ((814, 792), (870, 838)),
        ((604, 850), (570, 902)),
    ]:
        draw.line(box(x0, y0, x1, y1), fill=INK, width=px(8))


def impact_marks(draw) -> None:
    for x0, y0, x1, y1 in [(196, 780, 164, 822), (270, 808, 254, 854)]:
        draw.line(box(x0, y0, x1, y1), fill=MARK, width=px(13))
    draw.ellipse(box(840, 690, 882, 732), fill=MARK)
    draw.ellipse(box(148, 642, 180, 674), fill=MARK)


def compose() -> Image.Image:
    canvas = backdrop()

    accents = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    impact_marks(ImageDraw.Draw(accents))
    canvas.alpha_composite(accents)

    canvas.alpha_composite(wisps_layer(canvas.size))
    canvas.alpha_composite(bunny_shapes())
    canvas.alpha_composite(paw_shapes())

    clip = Image.new("L", canvas.size, 0)
    rounded_silhouette(ImageDraw.Draw(clip), fill=255)
    out = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    out.paste(canvas, (0, 0), clip)
    return out


def wisps_layer(size) -> Image.Image:
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    wisps(ImageDraw.Draw(layer))
    return layer


def main() -> None:
    icon = compose().resize((SIZE, SIZE), Image.LANCZOS)

    png = os.path.join(HERE, "assets", "icon", "purrage.png")
    os.makedirs(os.path.dirname(png), exist_ok=True)
    icon.save(png)

    ico = os.path.join(HERE, "windows", "runner", "resources", "app_icon.ico")
    icon.save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print(f"wrote {png}")
    print(f"wrote {ico}")


if __name__ == "__main__":
    main()
