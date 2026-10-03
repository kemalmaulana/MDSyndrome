# MDSyndrome — logo & icon guidelines

<p align="center"><img src="previews/app-icon-1024.png" width="160" alt="MDSyndrome app icon"></p>

## The idea

A capsule split in two:
- **The outlined half** is the raw Markdown you type.
- **The solid half** is the rendered page you read.

That is the app's split view in one shape. It also plays on the name: a pill for *MD Syndrome*, the condition of writing everything in Markdown.

## Colour

| Role | Name | HEX | RGB | CMYK (approx.) | Pantone (nearest, verify on a swatch) |
|---|---|---|---|---|---|
| Rendered half, accents | **Dose Coral** | `#FF5E4D` | 255 94 77 | 0 63 70 0 | 178 C |
| Raw half, wordmark, dark tile | **Ink** | `#17181C` | 23 24 28 | 70 60 50 85 (rich black) | Black 6 C |
| Raw half on dark, light tile | **Paper** | `#F7F4EF` | 247 244 239 | 2 3 5 0 | uncoated warm white stock |

The two colours carry the meaning: the source is monochrome and the result is in colour. Don't add a third colour to the mark.

The app-icon tile is the only place a gradient appears. It runs from `#2A2C33` to `#121317` on the dark tile, and from `#FFFFFF` to `#E9E4DB` on the light tile.

## Versions

| File (in `final/`) | Use |
|---|---|
| `symbol.svg` | Default mark, full colour, on light backgrounds |
| `symbol-reversed.svg` | On dark backgrounds. The paper outline is thinned from 16 to 14 units because light on dark looks heavier |
| `symbol-small.svg` | At 32 px and below. It has a heavier outline (22 units) and a wider seam so the halves never fuse |
| `lockup-horizontal(-reversed).svg` | Default lockup: README headers, website, About window |
| `lockup-stacked(-reversed).svg` | Square-ish spaces: social cards, splash screens |
| `wordmark(-reversed).svg` | Only where the symbol is already shown nearby |
| `app-icon-dark.svg` | **The macOS app icon** (Big Sur+ grid: an 824 px squircle tile on a 1024 px canvas) |
| `app-icon-dark-small.svg` | Source for the 16 and 32 px app-icon files |
| `app-icon-light.svg` | Alternative light tile for marketing and documentation |

Single-colour versions (black, white, coral) and the web icons (favicon, PWA icons, `site.webmanifest`) are in `exports/`.

## Clear space and minimum size

- **Clear space:** keep at least **one capsule radius** clear on every side. That is half the capsule's thickness, or 48 units in the 256-unit drawing.
- **Minimum sizes:**
  - symbol: 16 px on screen, 6 mm in print (use `symbol-small.svg` at 32 px and below)
  - horizontal lockup: 120 px or 30 mm wide
  - stacked lockup: 64 px or 16 mm wide

## Typography

- The wordmark is **Inter SemiBold** (variable instance wght 600, opsz 32) with HarfBuzz kerning and −1.2 % tracking. It is converted to outlines, so no font is needed to display it.
- Inter is licensed under the SIL Open Font License 1.1, which allows logo use.
- To rebuild it: `python3 build_wordmark.py --font "Inter[opsz,wght].ttf"` (needs `pip install fonttools uharfbuzz`).

## Approved backgrounds

- Full colour: white, Paper, light greys.
- Reversed: Ink, dark greys, photos with a calm dark area.
- On Coral, use the one-colour **white** version.
- Never put the full-colour mark directly on Coral.

## Don't

- Rotate the capsule to anything other than −45°, or flip it. The raw half always sits lower left.
- Swap the halves (solid raw, outlined rendered). That reverses the meaning.
- Recolour the halves, add gradients, shadows or glows to the mark, or outline the solid half.
- Close or widen the seam beyond the drawn versions.
- Set the wordmark in another font, add tracking, or stack it differently from the provided lockups.
- Use the full-size symbol at 32 px or below. Use the small cut.

## Rebuilding

```bash
python3 build_app_icon.py --theme dark -o final/app-icon-dark.svg
python3 build_app_icon.py --theme dark --small -o final/app-icon-dark-small.svg
# The app's AppIcon.appiconset is rendered from these two files (16/32 px use the small cut).
```

## Notes

- **Trademark:** run a professional trademark and reverse-image search before commercial use. A capsule is a common shape in pharmacy branding.
- Concept history is in `concepts/`.
