#!/usr/bin/env python3
"""Build the MDSyndrome wordmark and lockups as pure outlines (no live text).

Font: Inter (SIL Open Font License 1.1 — logo use permitted), variable instance wght 600 / opsz 32,
shaped with HarfBuzz (kerning on). Needs: pip install fonttools uharfbuzz.
Usage: python3 build_wordmark.py --font /path/to/Inter[opsz,wght].ttf --out-dir final
"""
import argparse, re
import uharfbuzz as hb
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

INK, CORAL, PAPER = "#17181C", "#FF5E4D", "#F7F4EF"
TEXT = "MDSyndrome"
TRACKING = -0.012  # em; slight tightening for display size

def wordmark_path(font_path, cap_height, x0, baseline):
    """Return (svg path d, advance width) for TEXT with the given cap height, starting at (x0, baseline)."""
    face = hb.Face(hb.Blob.from_file_path(font_path))
    font = hb.Font(face)
    font.set_variations({"wght": 600, "opsz": 32})
    upem = face.upem
    cap = TTFont(font_path)["OS/2"].sCapHeight
    size = cap_height / cap * upem          # font size in canvas units
    scale = size / upem
    buf = hb.Buffer()
    buf.add_str(TEXT)
    buf.guess_segment_properties()
    hb.shape(font, buf, {"kern": True, "liga": True})
    svg_pen = SVGPathPen(None)
    x = 0.0
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        # canvas = (x0 + (x + dx)*scale, baseline - y*scale): flip y, position glyph
        pen = TransformPen(svg_pen, (scale, 0, 0, -scale, x0 + (x + pos.x_offset) * scale, baseline - pos.y_offset * scale))
        font.draw_glyph_with_pen(info.codepoint, pen)
        x += pos.x_advance + TRACKING * upem
    x -= TRACKING * upem
    d = svg_pen.getCommands()
    d = re.sub(r"(\d+\.\d{2})\d+", r"\1", d)  # 2-decimal precision keeps files small
    return d, x * scale

def symbol_group(transform, outline, inset=16):
    inner = 48 - inset
    l = 123
    return (f'<g transform="{transform} rotate(-45 128 128)">'
            f'<path fill="{outline}" fill-rule="evenodd" d="M{l} 80H72a48 48 0 0 0 0 96h{l - 72}zM{l - inset} {80 + inset}H72a{inner} {inner} 0 0 0 0 {2 * inner}h{l - inset - 72}z"/>'
            f'<path fill="{CORAL}" d="M133 80h51a48 48 0 0 1 0 96h-51z"/></g>')

def write(path, view_box, body, title):
    open(path, "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view_box}">\n  <title>{title}</title>\n  {body}\n</svg>\n')
    print("wrote", path)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", required=True)
    ap.add_argument("--out-dir", default="final")
    a = ap.parse_args()
    out = a.out_dir

    # Wordmark alone: cap height 160 on a 256-high canvas (baseline 208, 48 margin).
    d, w = wordmark_path(a.font, 160, 0, 208)
    write(f"{out}/wordmark.svg", f"-24 0 {w + 48:.0f} 256", f'<path fill="{INK}" d="{d}"/>', "MDSyndrome wordmark")
    write(f"{out}/wordmark-reversed.svg", f"-24 0 {w + 48:.0f} 256", f'<path fill="{PAPER}" d="{d}"/>', "MDSyndrome wordmark (reversed)")

    # Horizontal lockup: symbol 256 box (visible 40..216); cap height = 0.42 × 176 ≈ 74, caps centred
    # on the symbol's optical centre; gap 36 (≈ one outline-thickness × 2) after the symbol's right edge.
    cap = 74
    baseline = 128 + cap / 2
    text_x = 216 + 36
    d, w = wordmark_path(a.font, cap, text_x, baseline)
    right = text_x + w + 40
    vb = f"0 0 {right:.0f} 256"
    write(f"{out}/lockup-horizontal.svg", vb, symbol_group("", INK) + f'<path fill="{INK}" d="{d}"/>', "MDSyndrome horizontal lockup")
    write(f"{out}/lockup-horizontal-reversed.svg", vb, symbol_group("", PAPER, inset=14) + f'<path fill="{PAPER}" d="{d}"/>', "MDSyndrome horizontal lockup (reversed)")

    # Stacked lockup: symbol on top, wordmark centred below with cap height 52.
    cap = 52
    d0, w = wordmark_path(a.font, cap, 0, 0)
    width = max(256, w + 64)
    sx = (width - 256) / 2
    tx = (width - w) / 2
    baseline = 216 + 40 + cap
    d, _ = wordmark_path(a.font, cap, tx, baseline)
    vb = f"0 0 {width:.0f} {baseline + 40:.0f}"
    write(f"{out}/lockup-stacked.svg", vb, symbol_group(f"translate({sx:.2f} 0)", INK) + f'<path fill="{INK}" d="{d}"/>', "MDSyndrome stacked lockup")
    write(f"{out}/lockup-stacked-reversed.svg", vb, symbol_group(f"translate({sx:.2f} 0)", PAPER, inset=14) + f'<path fill="{PAPER}" d="{d}"/>', "MDSyndrome stacked lockup (reversed)")

if __name__ == "__main__":
    main()
