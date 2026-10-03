#!/usr/bin/env python3
"""Generate the macOS app icon (Big Sur+ grid) for MDSyndrome from the capsule geometry.

Usage: python3 build_app_icon.py [--theme dark|light] [--small] -o out.svg
Canvas 1024; tile = 824×824 continuous-corner squircle at (100,100), as in Apple's macOS icon template.
Stdlib only.
"""
import argparse, math

INK, CORAL, PAPER = "#17181C", "#FF5E4D", "#F7F4EF"
THEMES = {
    # tile gradient top→bottom, outline colour, outline inset (thinner when light-on-dark)
    "dark":  ("#2A2C33", "#121317", PAPER, 14),
    "light": ("#FFFFFF", "#E9E4DB", INK, 16),
}

def squircle(cx, cy, half, n=5.0, steps=720):
    """Superellipse |x|^n + |y|^n = 1: close match to Apple's continuous-corner icon shape."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = half * math.copysign(abs(c) ** (2 / n), c)
        y = half * math.copysign(abs(s) ** (2 / n), s)
        pts.append(f"{cx + x:.2f} {cy + y:.2f}")
    return "M" + "L".join(pts) + "Z"

def capsule(outline, inset, seam):
    # Same construction as final/symbol.svg, in the 256 box; inset = outline thickness.
    l = 128 - seam / 2
    r = 128 + seam / 2
    inner_r = 48 - inset
    return (
        f'<path fill="{outline}" fill-rule="evenodd" d="M{l} 80H72a48 48 0 0 0 0 96h{l - 72}z'
        f'M{l - inset} {80 + inset}H72a{inner_r} {inner_r} 0 0 0 0 {2 * inner_r}h{l - inset - 72}z"/>'
        f'<path fill="{CORAL}" d="M{r} 80h{184 - r}a48 48 0 0 1 0 96h-{184 - r}z"/>'
    )

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--theme", choices=THEMES, default="dark")
    ap.add_argument("--small", action="store_true", help="heavier small-size cut (16/32 px)")
    ap.add_argument("-o", "--out", required=True)
    a = ap.parse_args()
    top, bottom, outline, inset = THEMES[a.theme]
    if a.small:
        inset, seam = inset + 8, 16
    else:
        seam = 10
    # Capsule bbox in the 256 box spans ~40..216 (176). Fill ~58 % of the tile; nudge up 1.5 % (optical centre).
    scale = 0.58 * 824 / 176
    tx = 512 - 128 * scale
    ty = 512 - 128 * scale - 0.015 * 824
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <title>MDSyndrome app icon ({a.theme}{", small" if a.small else ""})</title>
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/>
    </linearGradient>
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="10"/>
      <feOffset dy="10" result="b"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.3"/></feComponentTransfer>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <path d="{squircle(512, 512, 412)}" fill="url(#tile)" filter="url(#shadow)"/>
  <g transform="translate({tx:.2f} {ty:.2f}) scale({scale:.4f}) rotate(-45 128 128)">
    {capsule(outline, inset, seam)}
  </g>
</svg>
'''
    open(a.out, "w").write(svg)
    print("wrote", a.out)

if __name__ == "__main__":
    main()
