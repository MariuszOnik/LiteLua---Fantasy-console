"""Style tuner: a PC window to tune how Heroes IV units look on the DS.

  python HeroesDS/tools/style_tuner.py

Pick a unit, animation and direction, move the sliders and judge by eye. The
preview is made by the same code as the cart graphics (h4atlas.convert: one
palette for the whole animation, alpha cut, outline, dithered shadow), drawn
the way the DS draws it, enlarged. Top: the animation playing at its fps;
below: all its frames. "Save style" writes the settings to tools/styles.json
(name -> Style fields); h4atlas.py --style <name> and make_h2b.py use them.
"""
import json
import os
import sys
import time
import tkinter as tk
from dataclasses import asdict
from tkinter import colorchooser, simpledialog, ttk

from PIL import Image, ImageTk

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import h4actor  # noqa: E402
import h4atlas  # noqa: E402
import h4r  # noqa: E402

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Data")
DIRS = list(h4actor.DIRECTIONS)

# Slider fields: (name, label, from, to, resolution)
SLIDERS = [
    ("scale", "scale", 0.1, 0.6, 0.005),
    ("colors", "colors (16-color texture)", 2, 15, 1),
    ("brightness", "brightness", 0.5, 1.6, 0.01),
    ("contrast", "contrast", 0.5, 2.0, 0.01),
    ("saturation", "saturation", 0.0, 2.0, 0.01),
    ("sharpen", "sharpen %", 0, 200, 5),
    ("alpha_cut", "alpha cut (edge)", 1, 254, 1),
    ("vivid", "vivid colors weight", 0, 40, 1),
    ("shadow_alpha", "shadow alpha", 0.0, 1.0, 0.05),
]


def ds_color(c):
    """One 8-bit channel as the DS shows it: 5 bits (32 levels)."""
    return (c >> 3) * 255 // 31


def ds_colors(img):
    """RGBA image with its colors rounded to the DS 15-bit colors."""
    r, g, b, a = img.split()
    r, g, b = (ch.point(ds_color) for ch in (r, g, b))
    return Image.merge("RGBA", (r, g, b, a))


class Tuner:
    def __init__(self, root):
        self.root = root
        root.title("HeroesDS style tuner")
        self.lib = h4r.Library(DATA)
        names = sorted({e.name[len("combat_actor."):-4] for a in self.lib.archives
                        for e in a.find("combat_actor.") if e.name.lower().startswith("combat_actor.")
                        and "." not in e.name[len("combat_actor."):-4]}, key=str.lower)
        self.actors = names
        self.vars = {}
        self.pending = None
        self.result = None
        self.anim_frame = 0
        self.ground = (112, 104, 66)

        left = ttk.Frame(root, padding=6)
        left.pack(side="left", fill="y")
        right = ttk.Frame(root, padding=6)
        right.pack(side="left", fill="both", expand=True)

        def combo(label, values, default, cmd):
            ttk.Label(left, text=label).pack(anchor="w")
            v = tk.StringVar(value=default)
            c = ttk.Combobox(left, textvariable=v, values=values, width=28)
            c.pack(anchor="w", pady=(0, 4))
            c.bind("<<ComboboxSelected>>", lambda e: cmd())
            c.bind("<Return>", lambda e: cmd())
            return v, c

        self.actor, _ = combo("unit", self.actors, "bandit", self.actor_changed)
        self.state, self.state_box = combo("animation", [], "melee", self.changed)
        self.dir, _ = combo("direction", DIRS, "sw", self.changed)
        self.base, self.base_box = combo("preset (Reset goes back to it)", list(h4atlas.STYLES), "oldschool",
                                         self.load_style)
        grid = ttk.Frame(left)
        grid.pack(anchor="w")
        for row_i, (name, label, lo, hi, res) in enumerate(SLIDERS):
            ttk.Label(grid, text=label, wraplength=120).grid(row=row_i, column=0, sticky="sw")
            v = tk.DoubleVar()
            tk.Scale(grid, from_=lo, to=hi, resolution=res, orient="horizontal", length=170,
                     variable=v, command=lambda _v: self.changed()).grid(row=row_i, column=1)
            self.vars[name] = v
        self.full_colors = tk.BooleanVar()
        ttk.Checkbutton(left, text="256 colors (8 bpp texture, 2x video memory)", variable=self.full_colors,
                        command=self.changed).pack(anchor="w")
        self.dither = tk.BooleanVar()
        ttk.Checkbutton(left, text="dithered shadow (else half size)", variable=self.dither,
                        command=self.changed).pack(anchor="w")
        self.matte = tk.BooleanVar()
        ttk.Checkbutton(left, text="blend edges with ground (smooth)", variable=self.matte,
                        command=self.changed).pack(anchor="w")
        orow = ttk.Frame(left)
        orow.pack(anchor="w", pady=2)
        self.outline_on = tk.BooleanVar()
        ttk.Checkbutton(orow, text="outline", variable=self.outline_on, command=self.changed).pack(side="left")
        self.outline_color = (24, 16, 12)
        self.outline_button = tk.Button(orow, text="outline color", command=self.pick_outline)
        self.outline_button.pack(side="left", padx=4)
        zrow = ttk.Frame(left)
        zrow.pack(anchor="w")
        ttk.Label(zrow, text="zoom").pack(side="left")
        self.zoom = tk.IntVar(value=3)
        tk.Scale(zrow, from_=1, to=5, orient="horizontal", length=170, variable=self.zoom,
                 command=lambda _v: self.redraw()).pack(side="left")
        row = ttk.Frame(left)
        row.pack(anchor="w", pady=4)
        self.ground_button = tk.Button(row, text="ground color", command=self.pick_ground)
        self.ground_button.pack(side="left")
        ttk.Button(row, text="Reset", command=self.load_style).pack(side="left", padx=4)
        ttk.Button(row, text="Save style", command=self.save).pack(side="left")
        self.info = ttk.Label(left, text="", justify="left", wraplength=250)
        self.info.pack(anchor="w", pady=6)

        self.anim_label = ttk.Label(right)
        self.anim_label.pack(anchor="w")
        self.strip_canvas = tk.Canvas(right, width=900, height=420, bg="#202020", highlightthickness=0)
        self.strip_canvas.pack(fill="both", expand=True)

        self.load_style()
        self.actor_changed()
        self.tick()

    # --- settings <-> Style ------------------------------------------------------

    def load_style(self):
        st = h4atlas.STYLES[self.base.get()]
        self.ground = tuple(st.ground)
        self.vars["scale"].set(st.scale)
        for name, *_ in SLIDERS:
            if name != "scale":
                self.vars[name].set(getattr(st, name))
        self.full_colors.set(st.colors > 15)
        self.vars["colors"].set(min(st.colors, 15))
        self.outline_on.set(bool(st.outline))
        if st.outline:
            self.outline_color = tuple(st.outline)
        self.show_colors()
        self.dither.set(st.shadow == "dither")
        self.matte.set(st.edge == "matte")
        self.changed()

    def style(self):
        g = lambda n: self.vars[n].get()  # noqa: E731
        return h4atlas.Style(
            colors=255 if self.full_colors.get() else int(g("colors")), edge="matte" if self.matte.get() else "cut",
            alpha_cut=int(g("alpha_cut")), ground=self.ground, brightness=round(g("brightness"), 3),
            contrast=round(g("contrast"), 3), saturation=round(g("saturation"), 3), sharpen=int(g("sharpen")),
            outline=self.outline_color if self.outline_on.get() else None,
            shadow="dither" if self.dither.get() else "half", shadow_alpha=round(g("shadow_alpha"), 2),
            vivid=int(g("vivid")), scale=round(g("scale"), 3))

    # --- events -------------------------------------------------------------------

    def actor_changed(self):
        try:
            res = f"combat_actor.{self.actor.get()}.h4d"
            states = h4actor.parse(self.lib.read(res), res)["states"]
        except (KeyError, ValueError) as e:
            self.info.config(text=f"cannot read {self.actor.get()}: {e}")
            return
        names = [n for n, s in states.items() if s["dirs"]]
        self.state_box.config(values=names)
        if self.state.get() not in names:
            self.state.set("melee" if "melee" in names else names[0])
        self.changed()

    def changed(self):
        if self.pending:
            self.root.after_cancel(self.pending)
        self.pending = self.root.after(300, self.convert)

    def pick_ground(self):
        c = colorchooser.askcolor(color="#%02x%02x%02x" % self.ground, title="Ground (background) color")
        if c and c[0]:
            self.ground = tuple(int(x) for x in c[0])
            self.show_colors()
            self.changed()

    def pick_outline(self):
        c = colorchooser.askcolor(color="#%02x%02x%02x" % self.outline_color, title="Outline color")
        if c and c[0]:
            self.outline_color = tuple(int(x) for x in c[0])
            self.outline_on.set(True)
            self.show_colors()
            self.changed()

    def show_colors(self):
        """Buttons show their color (text in black or white, whichever reads)."""
        for button, rgb in ((self.ground_button, self.ground), (self.outline_button, self.outline_color)):
            fg = "black" if sum(rgb) > 380 else "white"
            button.config(bg="#%02x%02x%02x" % rgb, fg=fg, activebackground="#%02x%02x%02x" % rgb)

    def save(self):
        name = simpledialog.askstring("Save style", "Style name:", initialvalue="tuned")
        if not name:
            return
        data = {}
        if os.path.exists(h4atlas.STYLES_FILE):
            with open(h4atlas.STYLES_FILE, encoding="utf-8") as f:
                data = json.load(f)
        fields_ = asdict(self.style())
        fields_["_note"] = f"tuned on {self.actor.get()} {self.state.get()} {self.dir.get()}"
        data[name] = fields_
        with open(h4atlas.STYLES_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=1)
        h4atlas.STYLES[name] = self.style()
        self.base_box.config(values=list(h4atlas.STYLES))
        self.base.set(name)
        self.info.config(text=self.info.cget("text") + f"\nsaved as '{name}' -> tools/styles.json")

    # --- conversion and drawing -----------------------------------------------------

    def convert(self):
        self.pending = None
        t0 = time.time()
        try:
            atlas, shadow, meta = h4atlas.convert(self.lib, self.actor.get(), self.state.get(), self.dir.get(),
                                                  round(self.vars["scale"].get(), 3), style=self.style())
        except Exception as e:  # Show any problem in the window, keep running
            self.info.config(text=f"does not fit the DS: {e}", foreground="#c00000")
            return
        bpp = 4 if len(atlas.getpalette()) // 3 <= 16 else 8
        kb = atlas.width * atlas.height * bpp // 8
        skb = shadow.width * shadow.height // 2 if shadow else 0
        self.result = (ds_colors(atlas.convert("RGBA")), shadow.convert("RGBA") if shadow else None, meta)
        self.anim_frame = 0
        total = (kb + skb) // 1024
        # One duel has ~110 KB for both units' animations (DS_GRAPHICS.md)
        if total <= 48:
            verdict, color = "fine for a duel", "#007000"
        elif total <= 96:
            verdict, color = "big: only with a small opponent", "#b06000"
        else:
            verdict, color = "too big for a duel (~110 KB for both units)", "#c00000"
        text = (f"{meta['sequence']}\n{len(meta['frames'])} frames, {meta['fps']} fps, hit {meta['hit']}"
                f"\natlas {atlas.width}x{atlas.height} {bpp} bpp = {kb // 1024} KB")
        if shadow:
            text += f"\nshadow {shadow.width}x{shadow.height} 4 bpp = {skb // 1024} KB"
        text += f"\nvideo memory ~{total} KB: {verdict}\nconverted in {time.time() - t0:.1f} s"
        self.info.config(text=text, foreground=color)
        self.redraw()

    def frame_image(self, n):
        """Frame n (1-based) as the DS draws it, on the ground color, unzoomed."""
        atlas, shadow, meta = self.result
        z = meta["szoom"]
        # Screen boxes of every frame and shadow piece, so all frames share one size
        boxes = [(r[4], r[5], r[4] + r[2], r[5] + r[3]) for r in meta["rects"]]
        boxes += [(r[4], r[5], r[4] + r[2] * z, r[5] + r[3] * z) for r in meta["srects"]]
        left, top, right, bottom = h4atlas.union(boxes + [(0, 0, 0, 0)])
        left, top = left - 2, top - 2
        ground = tuple(ds_color(c) for c in self.ground)
        img = Image.new("RGBA", (right + 2 - left, bottom + 2 - top), ground + (255,))
        s = meta["sframes"][n - 1]
        if shadow and s:
            x, y, w, h, ox, oy = meta["srects"][s - 1]
            part = shadow.crop((x, y, x + w, y + h)).resize((w * z, h * z), Image.NEAREST)
            level = round(meta["salpha"] * 31) / 31  # The DS has 32 alpha levels
            part.putalpha(part.getchannel("A").point(lambda a: round(a * level)))
            img.alpha_composite(part, (ox - left, oy - top))
        i = meta["frames"][n - 1]
        if i:
            x, y, w, h, ox, oy = meta["rects"][i - 1]
            img.alpha_composite(atlas.crop((x, y, x + w, y + h)), (ox - left, oy - top))
        return img

    def redraw(self):
        if not self.result:
            return
        meta = self.result[2]
        z = self.zoom.get()
        frames = [self.frame_image(n) for n in range(1, len(meta["frames"]) + 1)]
        self.frames = frames
        c = self.strip_canvas
        c.delete("all")
        width = max(c.winfo_width(), 600)
        x = y = 0
        row_h = 0
        self.strip_photos = []
        for n, f in enumerate(frames, 1):
            big = f.resize((f.width * z, f.height * z), Image.NEAREST)
            if x + big.width > width and x:
                x, y, row_h = 0, y + row_h + 14, 0
            ph = ImageTk.PhotoImage(big)
            self.strip_photos.append(ph)
            c.create_image(x, y + 12, image=ph, anchor="nw")
            c.create_text(x + 2, y, text=str(n) + (" hit" if n - 1 == meta["hit"] and meta["hit"] else ""),
                          fill="#ffd060", anchor="nw")
            x += big.width + 4
            row_h = max(row_h, big.height)
        c.config(scrollregion=(0, 0, width, y + row_h + 14))

    def tick(self):
        if self.result and getattr(self, "frames", None):
            meta = self.result[2]
            n = self.anim_frame % len(self.frames)
            f = self.frames[n]
            z = self.zoom.get() + 1
            self.anim_photo = ImageTk.PhotoImage(f.resize((f.width * z, f.height * z), Image.NEAREST))
            self.anim_label.config(image=self.anim_photo)
            self.anim_frame += 1
            self.root.after(int(1000 / max(1, meta["fps"])), self.tick)
        else:
            self.root.after(200, self.tick)


def main():
    root = tk.Tk()
    Tuner(root)
    root.geometry("1300x980+20+10")
    root.mainloop()


if __name__ == "__main__":
    main()
