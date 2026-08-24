#!/usr/bin/env python3
"""Package the official OpenAI logomark as a 1024x1024 Railway template icon.

The mark's path data is used verbatim from the upstream SVG. The only change is
the monochrome fill (black -> white), which the mark is designed for, so it
stays legible on Railway's dark cards. It is then centred on a solid near-black
rounded tile so the icon reads on light backgrounds too.
"""
import io
import re
from pathlib import Path

from PIL import Image, ImageDraw
from reportlab.graphics import renderPM
from svglib.svglib import svg2rlg

SRC = Path("/tmp/dev-openai.svg")
OUT_SVG = Path("assets/icon.svg")
OUT_PNG = Path("assets/icon.png")

SIZE = 1024
PAD = 200              # padding around the mark inside the tile
RADIUS = 224           # rounded-corner radius of the tile
TILE = (13, 13, 15)    # near-black, matches a dark developer-tool card

svg = SRC.read_text()
assert "OpenAI icon" in svg, "unexpected source svg"

# Recolour the monochrome mark; leave every path coordinate untouched.
white_svg = svg.replace('fill="#000000"', 'fill="#FFFFFF"', 1)
assert 'fill="#FFFFFF"' in white_svg
assert white_svg.count("<path") == svg.count("<path") == 1

OUT_SVG.parent.mkdir(parents=True, exist_ok=True)
OUT_SVG.write_text(white_svg)

# Rasterise the mark on transparency at the inner size.
inner = SIZE - 2 * PAD
sized = re.sub(r'width="\d+px"', f'width="{inner}px"', white_svg)
sized = re.sub(r'height="\d+px"', f'height="{inner}px"', sized)
tmp = Path("/tmp/_mark_white.svg")
tmp.write_text(sized)

drawing = svg2rlg(str(tmp))
png_bytes = renderPM.drawToString(drawing, fmt="PNG", bg=0x0D0D0F)
mark = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
mark = mark.resize((inner, inner), Image.LANCZOS)

# Rounded near-black tile.
tile = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
ImageDraw.Draw(tile).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1],
                                       radius=RADIUS, fill=TILE + (255,))
tile.paste(mark, (PAD, PAD), mark)
tile.save(OUT_PNG, "PNG", optimize=True)

w, h = Image.open(OUT_PNG).size
print(f"wrote {OUT_PNG} {w}x{h} ({OUT_PNG.stat().st_size}B)")
print(f"wrote {OUT_SVG} ({OUT_SVG.stat().st_size}B)")
