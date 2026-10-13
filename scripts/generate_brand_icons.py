#!/usr/bin/env python3
"""Rasterize the supplied SVG; launcher/splash generators consume this PNG.

Install CairoSVG 2.9.1 (and Cairo on macOS) in a temporary virtualenv, then run
this script followed by `dart run flutter_launcher_icons` and
`dart run flutter_native_splash:create`. No image-generation service is used.
"""

from pathlib import Path

import cairosvg


root = Path(__file__).resolve().parent.parent
cairosvg.svg2png(
    url=str(root / "InstaLLM_llama_vector.svg"),
    write_to=str(root / "assets/icons/installm.png"),
    output_width=1024,
    output_height=1024,
)
