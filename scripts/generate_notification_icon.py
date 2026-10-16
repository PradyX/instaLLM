#!/usr/bin/env python3
"""Derive the Android notification small icon from the master brand artwork.

Android paints a notification's small icon itself and reads only its alpha
channel (white on a dark shade, dark on a light one), so the coloured app icon
cannot be used there: it collapses into a blank circle. The app icon's own
silhouette can, and this script produces exactly that straight from
`InstaLLM_llama_vector.svg`, so the notice icon stays the app's llama instead of
a generic glyph and cannot drift from the artwork.

Every opaque layer of the mark is filled white and stacked; the tile background
is dropped (it would fill the whole icon) and the eye, nose and interior shading
contribute nothing to an alpha silhouette, so they are left out. Standard library
only, unlike the CairoSVG step in scripts/generate_brand_icons.py.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "InstaLLM_llama_vector.svg"
TARGET = (
    ROOT / "android/app/src/main/res/drawable/ic_stat_installm.xml"
)

# Labels of the layers that make up the silhouette, as the artwork comments
# them. A layer the SVG adds later fails the check below instead of quietly
# disappearing from the icon.
LAYERS = (
    "Green back and left shoulder",
    "Soft ivory nape and tall neck",
    "Under-ledge neck shadow",
    "Far ear",
    "Near ear",
    "Head, muzzle and chin",
    "Lower muzzle cast-shadow",
    "Delicate junction between muzzle and mouth",
    "A few fresh blades of grass held at the lips",
)
# Drawn in the SVG, but invisible in a single-colour silhouette.
SKIPPED = ("Dark app-icon background", "Vertical pill-shaped eye", "Tiny angular nose")

ROW = '<path\n        android:fillColor="#FFFFFFFF"\n        android:pathData="{}" />'


def layers() -> list[tuple[str, str]]:
    """Return (comment label, path data) for the clipped mark, in draw order."""
    body = re.search(
        r'<g clip-path="url\(#tileClip\)">(.*?)</g>', SOURCE.read_text(), re.S
    )
    if body is None:
        raise SystemExit(f"{SOURCE.name}: no clipped mark group found")

    found: list[tuple[str, str]] = []
    label = ""
    for match in re.finditer(r"<!--(.*?)-->|<path\b([^>]*)/>", body.group(1), re.S):
        if match.group(1) is not None:
            label = match.group(1).strip(" -")
        else:
            data = re.search(r'd="([^"]+)"', match.group(2))
            if data is None:
                raise SystemExit(f"{SOURCE.name}: a path has no d attribute")
            found.append((label, data.group(1)))

    unexpected = sorted(
        {
            label
            for label, _ in found
            if not label.startswith(LAYERS + SKIPPED)
        }
    )
    if unexpected:
        raise SystemExit(
            f"{SOURCE.name}: unclassified layer(s) {unexpected}; decide "
            "whether they belong in the silhouette before regenerating"
        )
    return found


def main() -> None:
    keep = [
        (label, data)
        for label, data in layers()
        if label.startswith(LAYERS)
    ]
    if not keep:
        raise SystemExit(f"{SOURCE.name}: no silhouette layers matched")

    viewport = re.search(
        r'viewBox="0 0 (\d+) (\d+)"', SOURCE.read_text()
    )
    if viewport is None:
        raise SystemExit(f"{SOURCE.name}: no viewBox to size the icon from")
    width, height = viewport.groups()

    paths = "\n".join(
        f"    <!-- {label} -->\n    {ROW.format(data)}" for label, data in keep
    )
    TARGET.write_text(
        f"""<?xml version="1.0" encoding="utf-8"?>
<!--
  Status bar / notification small icon: the app icon's own llama, as a
  single-colour silhouette.

  Android draws this icon itself and uses only its alpha channel, painting it
  white on a dark shade and dark on a light one. The full-colour launcher
  mipmap therefore arrives in the shade as a blank circle, which is why notices
  carry a silhouette instead — this one, so the notice still looks like InstaLLM
  rather than a generic glyph.

  Regenerate with scripts/generate_notification_icon.py after any change to
  InstaLLM_llama_vector.svg; do not hand-edit the paths below.
-->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="{width}"
    android:viewportHeight="{height}">
{paths}
</vector>
"""
    )
    print(f"wrote {TARGET.relative_to(ROOT)} from {len(keep)} layers")


if __name__ == "__main__":
    main()
