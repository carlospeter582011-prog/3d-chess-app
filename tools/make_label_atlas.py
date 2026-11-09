# Renders the a-h / 1-8 coordinate glyphs into a 4x4 atlas (128px cells) like the web version's canvas labels:
# colour rgba(240,222,190,0.85), semi-bold, centred at (64,70). Run: python3 make_label_atlas.py labels_atlas.png
import sys
from PIL import Image, ImageDraw, ImageFont
out = sys.argv[1] if len(sys.argv) > 1 else 'labels_atlas.png'
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
glyphs = list('abcdefgh') + list('12345678')
font = ImageFont.truetype(FONT, 78)
rgb = (240, 222, 190)
img = Image.new('RGBA', (512, 512), rgb + (0,))   # RGB everywhere = text colour, so mip/bilinear filtering never darkens edges
for i, g in enumerate(glyphs):
    mask = Image.new('L', (128, 128), 0)
    ImageDraw.Draw(mask).text((64, 70), g, font=font, fill=int(255 * 0.85), anchor='mm')
    cell = Image.new('RGBA', (128, 128), rgb + (0,))
    cell.putalpha(mask)
    img.paste(cell, ((i % 4) * 128, (i // 4) * 128))
img.save(out)
