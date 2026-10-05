# Acknowledgements

MDSyndrome includes the following third-party software.

| Component | Use | License |
|---|---|---|
| [cmark-gfm](https://github.com/swiftlang/swift-cmark) (`gfm` branch, Swift package by the Swift project) | Markdown parsing (CommonMark + GitHub Flavored Markdown) | BSD-2-Clause and MIT, see [COPYING](https://github.com/swiftlang/swift-cmark/blob/gfm/COPYING) |
| [Inter](https://github.com/rsms/inter) | Typeface of the wordmark (converted to outlines in `design/icon`; not shipped in the app) | SIL Open Font License 1.1 |
| [SwiftMath](https://github.com/mgriebling/SwiftMath) | Native LaTeX typesetting in the preview | MIT |
| Math fonts bundled with SwiftMath (Latin Modern, TeX Gyre, XITS, Fira, Noto, Libertinus, …) | Glyphs for typeset formulas | SIL Open Font License 1.1 / GUST Font License |
| Editor theme palettes (Tomorrow+, Tomorrow, Solarized Light/Dark, Mou Paper, Writer) | Colours and heading sizes follow the themes bundled with [MacDown](https://github.com/MacDownApp/macdown) (MIT). Tomorrow is by Chris Kempson (MIT) and Solarized by Ethan Schoonover (MIT). Only the colour values are used, no files | MIT |
| [Mermaid](https://github.com/mermaid-js/mermaid) 12.1.0 (`mermaid.min.js`, vendored unmodified) | Diagrams in fenced `mermaid` blocks, drawn in a hidden web view | MIT. The bundle contains its own dependencies (d3, DOMPurify, dagre, Cytoscape, KaTeX and others) under MIT, ISC, Apache-2.0 and MPL-2.0 licences |
| [Viz.js](https://github.com/mdaines/viz-js) 3.31.0 (`viz-global.js`, vendored unmodified) with [Graphviz](https://graphviz.org) and [Expat](https://libexpat.github.io) compiled to WebAssembly | Diagrams in fenced `dot` / `graphviz` blocks | Viz.js: MIT. Graphviz: Eclipse Public License 1.0. Expat: MIT |
| [KaTeX](https://katex.org) 0.19.0 (`katex.min.js`, CSS and the woff2 fonts, vendored unmodified) | Formulas SwiftMath cannot typeset | MIT. Fonts: SIL Open Font License 1.1 |
