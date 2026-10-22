# Builds AppIcon.svg: the icon is a keycap (seen slightly from the front) with a Redaction "k" legend
# and a faint carbon-copy offset of the legend.
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.transformPen import TransformPen

font = TTFont("../Fonts/Redaction-Regular.otf")
gs = font.getGlyphSet()
name = font.getBestCmap()[ord("k")]
bp = BoundsPen(gs); gs[name].draw(bp)
xmin, ymin, xmax, ymax = bp.bounds

def glyph(cx, cy, h):
    s = h / (ymax - ymin)
    pen = SVGPathPen(gs)
    gs[name].draw(TransformPen(pen, (s, 0, 0, -s, cx - (xmin + xmax) / 2 * s, cy + (ymin + ymax) / 2 * s)))
    return pen.getCommands()

# top surface: x 178..846, y 142..782  (front skirt taller than back = viewed slightly from the front)
k = glyph(512, 458, 318)
ghost = glyph(526, 472, 318)

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <linearGradient id="skirt" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#4B4FDB"/>
      <stop offset="1" stop-color="#262A92"/>
    </linearGradient>
    <linearGradient id="sides" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#000" stop-opacity="0.22"/>
      <stop offset="0.14" stop-color="#000" stop-opacity="0"/>
      <stop offset="0.86" stop-color="#000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000" stop-opacity="0.22"/>
    </linearGradient>
    <linearGradient id="top" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#5D61EC"/>
      <stop offset="1" stop-color="#4549D3"/>
    </linearGradient>
    <radialGradient id="dish" cx="0.5" cy="0.42" r="0.62">
      <stop offset="0" stop-color="#000" stop-opacity="0.10"/>
      <stop offset="1" stop-color="#000" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity="0.35"/>
      <stop offset="0.5" stop-color="#fff" stop-opacity="0.04"/>
      <stop offset="1" stop-color="#fff" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#skirt)"/>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#sides)"/>
  <rect x="178" y="142" width="668" height="640" rx="128" fill="url(#top)"/>
  <rect x="178" y="142" width="668" height="640" rx="128" fill="url(#dish)"/>
  <rect x="179.5" y="143.5" width="665" height="637" rx="126.5" fill="none" stroke="url(#rim)" stroke-width="3"/>
  <path d="{ghost}" fill="#1E2178" opacity="0.55"/>
  <path d="{k}" fill="#EEF0F4"/>
</svg>
'''
open("AppIcon.svg", "w").write(svg)
