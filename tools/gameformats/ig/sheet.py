"""sheet.py OUT.png COLS IMG... - paste renders (transparent PNGs) on white in a grid."""
import sys
from PIL import Image

out, cols, imgs = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
T = 256
rows = (len(imgs) + cols - 1) // cols
s = Image.new("RGB", (T * cols, T * rows), "white")
for i, p in enumerate(imgs):
    im = Image.open(p).convert("RGBA").resize((T, T))
    s.paste(Image.alpha_composite(Image.new("RGBA", (T, T), "white"), im).convert("RGB"),
            ((i % cols) * T, (i // cols) * T))
s.save(out)
