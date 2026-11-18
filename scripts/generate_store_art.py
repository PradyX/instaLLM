#!/usr/bin/env python3
"""Frame each Play Store screenshot set as artwork: brand row, headline,
subtitle, and the app capture as a rounded card on a soft gradient panel.

Style follows the panel layout the user supplied as reference: small brand mark
and wordmark top-left, two-line headline under it, one or two lines of muted
supporting text, then the device capture as a rounded card with a soft shadow,
on alternating deep-green and cream panels.

Layout rules per store size, all outputs exactly at Play's recommended pixels:
  phone     1080x2160   portrait, text block above the card
  7-inch    2048x1152   landscape, text column left, card right
  10-inch   1920x1080   landscape, text column left, card right
  desktop   2560x1440   landscape, text column left, card right

The text layer is rendered at 2x and downsampled for crisp type and corners;
the app capture is composited at 1x afterwards so it is never resampled twice.
"""

import collections
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "screens"
OUT = ROOT / "screens/framed"

CREAM = (247, 244, 233)
CREAM_HI = (253, 252, 247)
CREAM_LO = (243, 240, 229)
INK = (24, 31, 15)
INK_HI = (33, 41, 22)
INK_LO = (13, 18, 9)
INK_TEXT = (30, 37, 21)
INK_SOFT = (94, 106, 74)
CREAM_SOFT = (214, 221, 194)
GREEN = (78, 99, 48)
GREEN_LIGHT = (150, 173, 112)

FONT_SF = "/System/Library/Fonts/SFNS.ttf"
FONT_ARIAL = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_ARIAL_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

TILE = Image.open(ROOT / "assets/icons/installm.png").convert("RGBA")

SS = 2  # supersample factor for the text/background layer


def font(size, weight="Bold"):
    size = int(round(size * SS))
    try:
        f = ImageFont.truetype(FONT_SF, size)
        f.set_variation_by_name(weight)
        return f
    except Exception:
        return ImageFont.truetype(
            FONT_ARIAL_BOLD if weight == "Bold" else FONT_ARIAL, size
        )


def vgrad(size, top, bottom):
    w, h = size
    grad = Image.new("L", (1, h))
    for y in range(h):
        grad.putpixel((0, y), int(round(255 * y / max(1, h - 1))))
    return Image.composite(
        Image.new("RGB", size, bottom), Image.new("RGB", size, top), grad.resize(size)
    )


def glow(size, colour, centre, radius, strength):
    """Soft radial accent, full-canvas so it never shows a hard edge."""
    small = (max(2, size[0] // 6), max(2, size[1] // 6))
    layer = Image.new("L", small, 0)
    px = layer.load()
    cx, cy = centre[0] / 6, centre[1] / 6
    r = radius / 6
    for y in range(small[1]):
        for x in range(small[0]):
            t = min(1.0, math.hypot(x - cx, y - cy) / r)
            s = t * t * (3 - 2 * t)
            px[x, y] = int(255 * strength * (1 - s))
    layer = layer.resize(size, Image.LANCZOS)
    tint = Image.new("RGBA", size, (*colour, 255))
    tint.putalpha(layer)
    return tint


def wrap(draw, text, fnt, max_width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if draw.textlength(trial, font=fnt) <= max_width or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def balanced_wrap(draw, text, fnt, max_width):
    """Wrap, then narrow the measure until the lines are even.

    A greedy wrap leaves an orphan ("Entirely on your phone." / "phone.");
    with the same line count, a slightly narrower measure spreads the words
    evenly, which is what the headline and subtitle in the reference do.
    """
    lines = wrap(draw, text, fnt, max_width)
    if len(lines) < 2:
        return lines
    best = None
    for step in range(100, 54, -2):
        cand = wrap(draw, text, fnt, max_width * step / 100)
        if len(cand) != len(lines):
            continue
        score = max(len(c) for c in cand) - min(len(c) for c in cand)
        if best is None or score < best[0]:
            best = (score, cand)
    return best[1] if best else lines


def brand_row(canvas, xy, dark, tile_px_ss, name_size_ss, tracking=0.0):
    """Launcher tile + wordmark, drawn on the supersampled layer."""
    d = ImageDraw.Draw(canvas)
    x, y = xy
    tile = TILE.resize((tile_px_ss, tile_px_ss), Image.LANCZOS)
    canvas.alpha_composite(tile, (int(x), int(y)))
    f = font(name_size_ss / SS, "Bold")
    tx = x + tile_px_ss + name_size_ss * 0.55
    ty = y + tile_px_ss / 2
    colour = CREAM if dark else INK_TEXT
    if tracking:
        # letter-spaced wordmark, as in the reference panels
        cx = tx
        for ch in "InstaLLM":
            d.text((cx, ty), ch, font=f, fill=colour, anchor="lm")
            cx += d.textlength(ch, font=f) + tracking * SS
    else:
        d.text((tx, ty), "InstaLLM", font=f, fill=colour, anchor="lm")


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255
    )
    return mask


def drop_shadow(canvas_size, box, radius, blur, alpha):
    mask = Image.new("L", canvas_size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(blur))
    layer = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    layer.paste(Image.new("RGBA", canvas_size, (0, 0, 0, alpha)), (0, 0), mask)
    return layer


# ---------------------------------------------------------- system chrome
def modal_top_colour(shot):
    """The dominant colour at the very top edge of the capture."""
    w = shot.size[0]
    counts = collections.Counter(shot.crop((0, 0, w, 8)).getdata())
    return counts.most_common(1)[0][0]


def top_edge_columns(shot):
    """One colour per column, sampled from the capture's top edge.

    The captures are edge-to-edge with the system bars hidden, so rows 0-3 are
    flat app background; stretching them upward rebuilds what the bar sits
    over, including a drawer scrim or a sidebar edge. The wide horizontal
    median removes any glyph stroke that reaches the first row without
    softening those real vertical edges.
    """
    w = shot.size[0]
    strip = shot.crop((0, 0, w, 4)).resize((w, 1), Image.BOX)
    return strip.resize((w, 9), Image.NEAREST).filter(ImageFilter.MedianFilter(9)) \
        .crop((0, 4, w, 5))


def luminance(rgb):
    r, g, b = rgb
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def chrome_font(px, weight="Semibold"):
    """Absolute pixel size, for the 2x chrome layers below."""
    try:
        f = ImageFont.truetype(FONT_SF, px)
        f.set_variation_by_name(weight)
        return f
    except Exception:
        return ImageFont.truetype(FONT_ARIAL_BOLD, px)


def android_status_bar(w, h, fg):
    """Time on the left, signal / wifi / battery on the right, as Android draws
    them over an edge-to-edge app."""
    S = 2
    W, H = w * S, h * S
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)

    d.text(
        (H * 0.72, H * 0.52), "9:41", font=chrome_font(round(H * 0.52)), fill=fg,
        anchor="lm",
    )

    x = W - H * 0.60
    # battery: outlined body, filled charge, nub
    bw, bh = H * 0.84, H * 0.42
    nub_w, nub_h = H * 0.045, H * 0.15
    top = H * 0.5 - bh / 2
    body = (x - nub_w * 2.6 - bw, top, x - nub_w * 2.6, top + bh)
    d.rounded_rectangle(
        body, radius=bh * 0.3, outline=fg, width=max(2, round(H * 0.055))
    )
    inset = bh * 0.24
    d.rounded_rectangle(
        (body[0] + inset, body[1] + inset, body[2] - inset, body[3] - inset),
        radius=bh * 0.14, fill=fg,
    )
    d.rounded_rectangle(
        (body[2] + nub_w * 0.6, H * 0.5 - nub_h, x, H * 0.5 + nub_h),
        radius=nub_w, fill=fg,
    )

    # wifi: three arcs plus the dot, opening upward
    x = body[0] - H * 0.42
    wr = H * 0.38
    cx, cy = x - wr, H * 0.70
    lw = max(2, round(H * 0.06))
    for frac in (0.40, 0.71, 1.0):
        r = wr * frac
        d.arc((cx - r, cy - r, cx + r, cy + r), 225, 315, fill=fg, width=lw)
    d.ellipse((cx - lw, cy - lw, cx + lw, cy + lw), fill=fg)

    # signal: four bars of rising height
    x = cx - wr - H * 0.42
    bar_w, gap, base = H * 0.115, H * 0.05, H * 0.72
    for i in range(4):
        bh_i = H * (0.20 + 0.12 * i)
        bx = x - 4 * bar_w - 3 * gap + i * (bar_w + gap)
        d.rounded_rectangle(
            (bx, base - bh_i, bx + bar_w, base), radius=bar_w * 0.35, fill=fg
        )
    return lay.resize((w, h), Image.LANCZOS)


def macos_title_bar(w, h, fg):
    """Traffic lights and the window title, so the capture reads as a window."""
    S = 2
    W, H = w * S, h * S
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)

    r, cy, x = H * 0.135, H * 0.47, H * 0.62
    for colour in ((236, 106, 94), (224, 187, 82), (106, 191, 105)):
        d.ellipse((x, cy - r, x + 2 * r, cy + r), fill=colour)
        x += 2 * r + H * 0.115

    d.text(
        (W / 2, cy), "InstaLLM", font=chrome_font(round(H * 0.30)),
        fill=(*fg, 190), anchor="mm",
    )
    # hairline so the bar separates from the app body
    d.rectangle((0, H - S, W, H), fill=(0, 0, 0, 34))
    return lay.resize((w, h), Image.LANCZOS)


CHROME = {"android": android_status_bar, "macos": macos_title_bar}


def add_system_chrome(shot, chrome):
    """Stack the platform bar above the capture.

    The bar takes its fill from the capture's own top edge, so it reads as the
    app running under the system bar (which is how the app is configured:
    SystemUiMode.edgeToEdge), not as a strip bolted onto the screenshot.
    """
    w = shot.size[0]
    h = chrome["h"]
    bg = modal_top_colour(shot)
    fg = CREAM if luminance(bg) < 140 else INK_TEXT
    # The status bar sits over the app, so it follows the app's own edge;
    # a window title bar is chrome, so it keeps one flat colour.
    if chrome["kind"] == "android":
        base = top_edge_columns(shot).resize((w, h), Image.NEAREST)
    else:
        base = Image.new("RGB", (w, h), bg)
    bar = Image.alpha_composite(
        base.convert("RGBA"), CHROME[chrome["kind"]](w, h, fg)
    )
    app = Image.new("RGB", (w, shot.size[1] + h))
    app.paste(bar.convert("RGB"), (0, 0))
    app.paste(shot, (0, h))
    return app


def build(canvas_size, dark, headline, subtitle, shot_path, layout):
    W, H = canvas_size
    # --- supersampled text layer
    art = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    bg = (
        vgrad((W * SS, H * SS), INK_HI, INK_LO)
        if dark
        else vgrad((W * SS, H * SS), CREAM_HI, CREAM_LO)
    )
    art.paste(bg, (0, 0))

    if layout["glow"]:
        art.alpha_composite(
            glow(
                (W * SS, H * SS),
                GREEN_LIGHT if dark else (240, 232, 205),
                (int(W * SS * layout["glow"][0]), int(H * SS * layout["glow"][1])),
                H * SS * layout["glow"][2],
                layout["glow"][3] * (1.0 if dark else 0.55),
            )
        )

    d = ImageDraw.Draw(art)
    body_colour = CREAM_SOFT if dark else INK_SOFT
    head_colour = CREAM if dark else INK_TEXT

    brand_row(
        art,
        (layout["brand"][0] * SS, layout["brand"][1] * SS),
        dark,
        layout["tile"] * SS,
        layout["wordmark"],
        layout.get("tracking", 0),
    )

    hf = font(layout["headline_size"], "Bold")
    max_w = layout["text_width"] * SS
    lines = balanced_wrap(d, headline, hf, max_w)
    sf = font(layout["sub_size"], "Regular")
    sub_lines = balanced_wrap(d, subtitle, sf, max_w)

    top = layout["headline_y"] * SS
    if layout.get("center_text"):
        # Landscape panels: the caption reads as part of the card, so centre the
        # whole text block on the card rather than pinning it under the brand.
        block = (
            len(lines) * layout["headline_size"] * SS * 1.12
            + layout["sub_gap"] * SS
            + len(sub_lines) * layout["sub_size"] * SS * 1.34
        )
        card_mid = (layout["card"][1] + layout["card"][3]) / 2 * SS
        floor = (layout["brand"][1] + layout["tile"] + 40) * SS
        top = max(floor, card_mid - block / 2)

    y = top
    for line in lines:
        d.text((layout["text_x"] * SS, y), line, font=hf, fill=head_colour, anchor="la")
        y += layout["headline_size"] * SS * 1.12

    y += layout["sub_gap"] * SS
    for line in sub_lines:
        d.text((layout["text_x"] * SS, y), line, font=sf, fill=body_colour, anchor="la")
        y += layout["sub_size"] * SS * 1.34

    canvas = art.resize((W, H), Image.LANCZOS).convert("RGB")

    # --- card: shadow on the 1x canvas, capture composited at native scale
    box, radius = layout["card"], layout["radius"]
    canvas = Image.alpha_composite(
        canvas.convert("RGBA"),
        drop_shadow((W, H), box, radius, layout["shadow_blur"], layout["shadow_alpha"]),
    ).convert("RGB")

    shot = Image.open(shot_path).convert("RGB")
    if layout.get("chrome"):
        shot = add_system_chrome(shot, layout["chrome"])
    cw, ch = box[2] - box[0], box[3] - box[1]
    shot = shot.resize((cw, ch), Image.LANCZOS)
    mask = rounded_mask((cw, ch), radius)
    canvas.paste(shot, (box[0], box[1]), mask)

    # hairline edge so the card separates from the panel even on cream
    edge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        box, radius=radius, outline=(0, 0, 0, 46) if not dark else (255, 255, 255, 34),
        width=2,
    )
    return Image.alpha_composite(canvas.convert("RGBA"), edge).convert("RGB")


# ------------------------------------------------------------------ phone
PHONE = dict(
    text_x=78, text_width=924, brand=(78, 92), tile=54, wordmark=32, tracking=0.9,
    headline_y=214, headline_size=80, sub_size=33, sub_gap=26,
    card=(156, 536, 924, 2072), radius=34, shadow_blur=34, shadow_alpha=88,
    glow=(0.24, 0.05, 1.35, 0.34),
    chrome=dict(kind="android", h=72),
)

# ------------------------------------------------------------------ landscape
def landscape(w, h, chrome="android"):
    """Text column left, card right, both sized from the canvas proportions."""
    pad = int(round(0.045 * w))
    text_w = int(round(0.355 * w))
    gap = int(round(0.028 * w))
    card_x = pad + text_w + gap
    card_w = w - card_x - pad
    card_h = int(round(card_w * 9 / 16))
    if card_h > int(0.78 * h):  # never let a 16:9 card tower over the panel
        card_h = int(0.78 * h)
        card_w = int(round(card_h * 16 / 9))
        card_x = w - pad - card_w
    card_y = (h - card_h) // 2
    return dict(
        text_x=pad, text_width=text_w, brand=(pad, int(round(0.062 * h))),
        tile=int(round(0.042 * h)), wordmark=int(round(0.023 * h)),
        tracking=0.9,
        headline_y=int(round(0.175 * h)), headline_size=int(round(0.062 * h)),
        sub_size=int(round(0.026 * h)), sub_gap=int(round(0.022 * h)),
        card=(card_x, card_y, card_x + card_w, card_y + card_h),
        radius=int(round(0.012 * w)), shadow_blur=int(round(0.02 * w)),
        shadow_alpha=80,
        glow=(0.74, 0.14, 0.78, 0.42), center_text=True,
        chrome=dict(
            kind=chrome,
            h=48 if chrome == "android" else int(round(0.026 * w)),
        ),
    )


SETS = {
    "phone": dict(
        size=(1080, 2160),
        layout=PHONE,
        src=SCRIPTS,
        panels=[
            ("Answers, entirely on your phone.",
             "A local model writes the reply offline. No account, no cloud round trip.",
             "1.png"),
            ("Every chat, one drawer.",
             "Voice mode, search and your bots stay a single tap from the conversation.",
             "2.png"),
            ("Models, sized to your phone.",
             "Every entry shows its size, context window and what the device can hold.",
             "3.png"),
            ("Make it yours.",
             "Light, dark or auto, solid or translucent, and nine accent colours.",
             "4.png"),
            ("Your private assistant.",
             "Runs 100% on-device, so nothing you type leaves the phone.",
             "5.png"),
            ("Voice mode, hands free.",
             "Speak, and the answer comes back out loud. Nothing is saved as a chat.",
             "6.png"),
        ],
    ),
    "tablet_7inch": dict(
        size=(2048, 1152),
        layout=landscape(2048, 1152),
        src=SCRIPTS / "tablet_7inch",
        panels=[
            ("Start with one model.",
             "Install a model once and the tablet runs offline from then on.",
             "1.png"),
            ("Make it yours.",
             "Light, dark or auto, solid or translucent, and nine accent colours.",
             "2.png"),
        ],
    ),
    "tablet_10inch": dict(
        size=(1920, 1080),
        layout=landscape(1920, 1080),
        src=SCRIPTS / "tablet_10inch",
        panels=[
            ("Your workspace, on this device.",
             "Chats, bots and rooms beside a model that never leaves the tablet.",
             "1.png"),
            ("Your private assistant.",
             "Runs 100% on-device, so nothing you type leaves the tablet.",
             "2.png"),
            ("Know it before you download it.",
             "Fit, context window and capabilities for every model in the catalog.",
             "3.png"),
            ("Make it yours.",
             "Light, dark or auto, solid or translucent, and nine accent colours.",
             "4.png"),
        ],
    ),
    "desktop": dict(
        size=(2560, 1440),
        layout=landscape(2560, 1440, chrome="macos"),
        src=SCRIPTS / "desktop",
        panels=[
            ("Your workspace, locally.",
             "Chats, bots and rooms beside a model running on this machine.",
             "1.png"),
            ("Your private assistant.",
             "Runs 100% on-device, so nothing you type leaves the computer.",
             "2.png"),
            ("Know it before you download it.",
             "Fit, context window and capabilities for every model in the catalog.",
             "3.png"),
            ("Make it yours.",
             "Light, dark or auto, solid or translucent, and nine accent colours.",
             "4.png"),
        ],
    ),
}


def main():
    for name, cfg in SETS.items():
        out_dir = OUT / name
        out_dir.mkdir(parents=True, exist_ok=True)
        for i, (headline, subtitle, shot) in enumerate(cfg["panels"], start=1):
            img = build(
                cfg["size"],
                dark=(i % 2 == 1),
                headline=headline,
                subtitle=subtitle,
                shot_path=cfg["src"] / shot,
                layout=cfg["layout"],
            )
            assert img.size == cfg["size"], img.size
            path = out_dir / f"{i}.png"
            img.save(path, optimize=True)
            print(f"{path.relative_to(ROOT)}  {img.size[0]}x{img.size[1]}")


if __name__ == "__main__":
    main()
