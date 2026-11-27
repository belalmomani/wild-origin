"""Generates the HUD / button icons (assets/ui/icons/*.png) with PIL: flat, glossy, cartoon style."""
from PIL import Image, ImageDraw, ImageFilter
import math, os
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "icons")
os.makedirs(OUT, exist_ok=True)
S = 512  # draw size, downscaled to 128

def new():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)

def save(im, name):
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    a = im.split()[3].filter(ImageFilter.GaussianBlur(10))
    sh.putalpha(a.point(lambda v: int(v * 0.45)))
    sh = Image.composite(Image.new("RGBA", (S, S), (0, 0, 0, 255)), Image.new("RGBA", (S, S), (0, 0, 0, 0)), sh.split()[3])
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    base.alpha_composite(sh, (6, 10))
    base.alpha_composite(im)
    base.resize((128, 128), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))

def ell(d, box, fill, outline=None, w=0):
    d.ellipse(box, fill=fill, outline=outline, width=w)

def gloss(d, box, alpha=90):
    x0, y0, x1, y1 = box
    d.ellipse((x0, y0, x1, y0 + (y1 - y0) * 0.55), fill=(255, 255, 255, alpha))

# --- clock
im, d = new()
ell(d, (40, 40, 472, 472), (240, 180, 40), (150, 100, 10), 14)
ell(d, (80, 80, 432, 432), (255, 252, 240), (190, 140, 30), 8)
for i in range(12):
    a = i * math.pi / 6
    r0, r1 = 150, 175 if i % 3 else 190
    d.line((256 + math.sin(a) * r0, 256 - math.cos(a) * r0, 256 + math.sin(a) * r1, 256 - math.cos(a) * r1), fill=(80, 60, 20), width=10)
d.line((256, 256, 256, 150), fill=(40, 30, 10), width=20)
d.line((256, 256, 330, 300), fill=(40, 30, 10), width=16)
ell(d, (238, 238, 274, 274), (200, 60, 40))
save(im, "clock")

# --- wood log
im, d = new()
d.rounded_rectangle((70, 170, 440, 360), 60, fill=(150, 95, 45), outline=(90, 55, 25), width=12)
for y in (215, 260, 305):
    d.line((110, y, 400, y), fill=(120, 72, 32), width=8)
ell(d, (40, 150, 210, 380), (225, 180, 115), (100, 62, 28), 12)
ell(d, (85, 205, 165, 325), (200, 150, 85))
ell(d, (110, 235, 140, 295), (170, 120, 60))
save(im, "wood")

# --- stone
im, d = new()
d.polygon([(70, 380), (110, 230), (230, 150), (350, 170), (440, 290), (420, 390)], fill=(150, 152, 160), outline=(80, 82, 90))
d.polygon([(110, 230), (230, 150), (350, 170), (300, 250), (180, 270)], fill=(190, 192, 200))
d.polygon([(300, 250), (350, 170), (440, 290), (420, 390), (330, 380)], fill=(120, 122, 132))
d.line([(70, 380), (110, 230), (230, 150), (350, 170), (440, 290), (420, 390), (70, 380)], fill=(70, 72, 80), width=10)
save(im, "stone")

# --- apple
im, d = new()
ell(d, (70, 120, 280, 430), (215, 40, 40), (120, 15, 15), 10)
ell(d, (232, 120, 442, 430), (215, 40, 40), (120, 15, 15), 10)
ell(d, (150, 145, 370, 400), (225, 55, 50))
d.ellipse((120, 160, 210, 270), fill=(255, 140, 130, 150))
d.line((256, 150, 270, 70), fill=(90, 55, 25), width=18)
d.polygon([(275, 90), (370, 50), (400, 110), (320, 135)], fill=(70, 160, 50), outline=(40, 100, 30))
save(im, "apple")

# --- meat (drumstick)
im, d = new()
ell(d, (120, 60, 440, 330), (170, 80, 40), (100, 45, 20), 12)
ell(d, (170, 90, 390, 290), (195, 100, 55))
d.line((170, 300, 90, 400), fill=(240, 232, 215), width=34)
ell(d, (50, 380, 120, 450), (240, 232, 215), (190, 180, 160), 8)
ell(d, (95, 410, 165, 480), (240, 232, 215), (190, 180, 160), 8)
d.ellipse((200, 100, 300, 170), fill=(255, 200, 150, 120))
save(im, "meat")

# --- fish
im, d = new()
d.polygon([(380, 256), (480, 170), (480, 342)], fill=(60, 140, 200), outline=(30, 80, 130))
ell(d, (40, 150, 420, 362), (110, 180, 225), (40, 100, 160), 12)
d.pieslice((60, 215, 420, 420), 200, 340, fill=(235, 245, 250))
ell(d, (110, 215, 160, 265), (255, 255, 255), (20, 30, 40), 6)
ell(d, (125, 228, 148, 252), (20, 30, 40))
d.arc((230, 190, 330, 320), 280, 80, fill=(40, 100, 160), width=8)
save(im, "fish")

# --- pelt (hide)
im, d = new()
d.polygon([(130, 90), (230, 130), (290, 130), (390, 90), (450, 200), (400, 260), (440, 400), (330, 440), (256, 410), (180, 440), (70, 400), (110, 260), (60, 200)], fill=(125, 82, 48), outline=(70, 42, 20))
d.polygon([(230, 150), (290, 150), (330, 300), (256, 380), (180, 300)], fill=(150, 104, 62))
for i in range(6):
    d.line((200 + i * 22, 230, 205 + i * 22, 300), fill=(105, 68, 38), width=6)
save(im, "pelt")

# --- star (level)
im, d = new()
pts = []
for i in range(10):
    r = 215 if i % 2 == 0 else 95
    a = -math.pi / 2 + i * math.pi / 5
    pts.append((256 + r * math.cos(a), 270 + r * math.sin(a)))
d.polygon(pts, fill=(250, 200, 40), outline=(170, 110, 10))
d.line(pts + [pts[0]], fill=(170, 110, 10), width=12)
save(im, "star")

# --- heart
im, d = new()
ell(d, (50, 90, 270, 310), (225, 40, 60), (130, 15, 30), 10)
ell(d, (242, 90, 462, 310), (225, 40, 60), (130, 15, 30), 10)
d.polygon([(60, 250), (452, 250), (256, 450)], fill=(225, 40, 60))
d.line([(62, 262), (256, 450), (450, 262)], fill=(130, 15, 30), width=10)
ell(d, (110, 130, 190, 200), (255, 150, 160))
save(im, "heart")

# --- button glyphs (white, bold)
def glyph(name, fn):
    im, d = new()
    fn(d)
    save(im, name)

W = (255, 255, 255)
def jump(d):  # running figure
    ell(d, (270, 60, 350, 140), W)
    d.line((300, 150, 250, 270), fill=W, width=38)
    d.line((250, 270, 330, 330), fill=W, width=34); d.line((330, 330, 310, 440), fill=W, width=32)
    d.line((250, 270, 180, 330), fill=W, width=34); d.line((180, 330, 120, 410), fill=W, width=30)
    d.line((290, 170, 380, 220), fill=W, width=30); d.line((290, 170, 190, 190), fill=W, width=30)
glyph("jump", jump)
def crouch(d):
    ell(d, (200, 90, 290, 180), W)
    d.line((240, 190, 250, 300), fill=W, width=40)
    d.line((250, 300, 340, 330), fill=W, width=34); d.line((340, 330, 330, 430), fill=W, width=32)
    d.line((250, 300, 180, 340), fill=W, width=34); d.line((180, 340, 190, 430), fill=W, width=32)
    d.line((240, 210, 330, 250), fill=W, width=28)
glyph("crouch", crouch)
def aim(d):
    d.ellipse((90, 90, 422, 422), outline=W, width=30)
    d.ellipse((215, 215, 297, 297), fill=W)
    for p in ((256, 30, 256, 130), (256, 382, 256, 482), (30, 256, 130, 256), (382, 256, 482, 256)):
        d.line(p, fill=W, width=30)
glyph("aim", aim)
def build(d):  # hammer
    d.line((130, 400, 330, 200), fill=(230, 190, 120), width=56)
    d.polygon([(250, 70), (440, 150), (400, 230), (330, 200), (300, 270), (210, 150)], fill=(215, 215, 225), outline=(120, 120, 135))
glyph("build", build)
def menu(d):
    for y in (150, 256, 362):
        d.rounded_rectangle((90, y - 22, 422, y + 22), 22, fill=W)
glyph("menu", menu)
def scope(d):
    d.ellipse((60, 60, 452, 452), outline=W, width=26)
    d.line((256, 60, 256, 452), fill=W, width=14); d.line((60, 256, 452, 256), fill=W, width=14)
    d.ellipse((226, 226, 286, 286), fill=W)
glyph("scope", scope)
def fire(d):  # arrow
    d.line((90, 420, 400, 110), fill=W, width=34)
    d.polygon([(450, 60), (440, 230), (280, 90)], fill=W)
    d.polygon([(90, 420), (60, 300), (150, 330)], fill=W); d.polygon([(90, 420), (210, 450), (180, 360)], fill=W)
glyph("fire", fire)
def hand(d):  # interact: open hand
    d.rounded_rectangle((150, 250, 360, 440), 50, fill=W)
    for i, (x, h) in enumerate(((150, 120), (210, 70), (270, 80), (330, 140))):
        d.rounded_rectangle((x, 440 - 190 - h, x + 52, 300), 26, fill=W)
    d.polygon([(150, 330), (80, 280), (100, 240), (170, 290)], fill=W)
glyph("hand", hand)
print("icons ->", OUT)

# --- coin
im, d = new()
ell(d, (40, 40, 472, 472), (250, 195, 40), (160, 105, 10), 16)
ell(d, (95, 95, 417, 417), (255, 218, 80), (200, 140, 20), 10)
d.polygon([(256, 140), (292, 226), (384, 232), (312, 290), (336, 380), (256, 330), (176, 380), (200, 290), (128, 232), (220, 226)], fill=(235, 165, 20))
d.ellipse((130, 100, 290, 170), fill=(255, 236, 140))
save(im, "coin")

# --- pause glyph
def pause(d):
    d.rounded_rectangle((130, 90, 215, 422), 26, fill=W)
    d.rounded_rectangle((297, 90, 382, 422), 26, fill=W)
glyph("pause", pause)

# --- player avatar (round, gold ring): boy with a blue cap
im, d = new()
ell(d, (20, 20, 492, 492), (120, 190, 235), (240, 190, 60), 22)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse((34, 34, 478, 478), fill=255)
inner = Image.new("RGBA", (S, S), (0, 0, 0, 0))
di = ImageDraw.Draw(inner)
di.rectangle((0, 0, S, S), fill=(135, 200, 240))
di.ellipse((-60, 380, 570, 700), fill=(70, 120, 70))          # shirt
di.rectangle((215, 330, 297, 420), fill=(235, 185, 140))        # neck
di.ellipse((130, 130, 382, 400), fill=(245, 200, 155))          # face
di.ellipse((120, 230, 160, 300), fill=(235, 185, 140)); di.ellipse((352, 230, 392, 300), fill=(235, 185, 140))
di.pieslice((110, 60, 402, 330), 180, 360, fill=(40, 80, 170))  # cap
di.rounded_rectangle((100, 190, 412, 225), 16, fill=(30, 60, 140))
di.polygon([(150, 215), (380, 215), (430, 250), (170, 250)], fill=(25, 50, 120))
for ex in (205, 307):
    di.ellipse((ex - 22, 270, ex + 22, 320), fill=(255, 255, 255)); di.ellipse((ex - 11, 282, ex + 11, 312), fill=(40, 30, 20))
di.arc((200, 310, 312, 380), 20, 160, fill=(150, 70, 60), width=10)
di.line((215, 258, 200, 250), fill=(70, 45, 25), width=8)
inner.putalpha(mask)
im.alpha_composite(inner)
d = ImageDraw.Draw(im)
d.ellipse((20, 20, 492, 492), outline=(240, 190, 60), width=22)
save(im, "avatar")
