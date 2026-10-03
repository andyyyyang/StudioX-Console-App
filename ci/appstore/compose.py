"""
App Store 宣傳圖：把 App 的截圖（docs/appstore/raw/，ui-screenshots.yml 的 [appstore-shots] 截的）合成宣傳圖，
存成 JPEG 到 docs/appstore/iphone69/、docs/appstore/ipad13/（ci/appstore.py 上傳的就是這兩個資料夾）。

  python3 ci/appstore/compose.py --fonts <放 Noto Sans CJK TC 的資料夾>

設計跟 App 同一套語言：暖黑底（Theme.page）、品牌橘、Xena 的彩虹漸層（標題的重點詞，像首頁的「5 件事」）、
Instrument Serif 斜體的編號、Inter Tight 的英文小字。背景是一條連續的光帶：8 張在 App Store 並排時接在一起。
手機有鈦金屬邊框與側邊按鍵；有的畫面把重點（確認卡片、LINE 的對話…）放大浮在手機旁邊。

每一張的文字、版型、放大的地方在下面的 SLIDES。
"""
import argparse
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW = os.path.join(ROOT, "docs", "appstore", "raw")
BRAND_FONTS = os.path.join(ROOT, "StudioXConsole", "Brand", "Fonts")

# App 的顏色（StudioXConsole/Brand/Theme.swift 的深色）
PAGE = (13, 13, 12)
INK = (238, 235, 229)
INK2 = (189, 185, 177)
MUTED = (133, 130, 123)
ACCENT = (255, 106, 51)
LINE = (238, 235, 229, 34)
IRIS = [(255, 138, 216), (180, 155, 255), (111, 214, 255)]  # xenaIris：粉、紫、青
GLOW = [(132, 92, 255), (64, 204, 255), (255, 107, 209), (255, 90, 31)]  # 光帶：紫、青、粉、橘

# 畫面代號、編號旁的小標、標題（\n 換行，*重點* 用彩虹漸層）、說明、版型、放大的地方
#   版型 top：字在上、手機在下（超出下緣）；bottom：手機在上（超出上緣）、字在下
#   zoom：box 是截圖上要放大的那一塊（比例）、width 是放大後佔畫面多寬；
#         pop＝從手機原本的位置浮出來，不然用 side（left／right／center）、y（高度比例）擺
#   layout_by：某個裝置用不同的版型（iPad 的畫面比例不一樣，重點的位置也不同）
SLIDES = [
    {"key": "home", "eyebrow": "AI 店長 Xena", "title": "每天一打開，\n就知道*該做什麼*", "sub": "訂單、客人、詢問，Xena 都整理好了", "hero": True},
    {"key": "voice", "eyebrow": "用說的", "title": "問一句，\n*Xena* 直接回答", "sub": "今天賣得怎樣、誰在等回覆，像跟店長講話", "layout": "bottom",
     "layout_by": {"ipad13": "top"},
     "zoom": {"ipad13": {"box": (0.209, 0.783, 0.791, 0.923), "width": 0.76, "radius": 0.03, "side": "center", "y": 0.812}}},
    {"key": "xena", "eyebrow": "交代 Xena", "title": "交代她做事，\n*你點頭*才執行", "sub": "標出貨、回客人、改商品，動手前一定先問你",
     "zoom": {"iphone69": {"box": (0.0364, 0.3605, 0.9636, 0.5279), "width": 0.90, "radius": 0.034, "pop": True},
              "ipad13": {"box": (0.219, 0.3125, 0.775, 0.567), "width": 0.76, "pop": True}}},
    {"key": "line", "eyebrow": "客服收件匣", "title": "官網和 LINE 的客人，\n*一個地方*回", "sub": "Xena 先回答，需要真人時才轉給你", "layout": "bottom",
     "zoom": {"ipad13": {"box": (0.428, 0.405, 0.962, 0.585), "width": 0.60, "radius": 0.03, "pop": True, "dy": 0.02}}},
    {"key": "orders", "eyebrow": "訂單", "title": "等出貨、待付款，\n*一眼*看完", "sub": "勾一勾，一次標好出貨", "shot": {"ipad13": "order"}},
    {"key": "traffic", "eyebrow": "流量與成效", "title": "生意好不好，\n*隨時*看得到", "sub": "即時訪客、Google 搜尋、每天的重點變化", "layout": "bottom"},
    {"key": "product", "eyebrow": "商品與內容", "title": "商品、內容，\n*手機上*就能改", "sub": "名稱、價格、庫存、上架，改完網站馬上更新"},
    {"key": "lock", "eyebrow": "安全", "title": "Face ID 保護，\n重要動作*再確認*", "sub": "退款、刪除這類動作，一定再驗證一次", "layout": "bottom"},
]

DEVICES = {
    # prefix：截圖檔名的前綴；size：畫布；shot_w：截圖縮到多寬；radius：螢幕圓角（比例）；margin：左右留白
    "iphone69": {"prefix": "iphone69-dark-", "size": (1320, 2868), "shot_w": 980, "radius": 0.118, "bezel": 0.034,
                 "margin": 112, "top": 200, "eyebrow": 40, "title": 112, "hero_title": 128, "sub": 46, "gap": 120, "phone": True},
    "ipad13": {"prefix": "ipad13-dark-", "size": (2064, 2752), "shot_w": 1640, "radius": 0.028, "bezel": 0.024,
               "margin": 172, "top": 190, "eyebrow": 52, "title": 152, "hero_title": 168, "sub": 60, "gap": 130, "phone": False},
}


# ── 字 ───────────────────────────────────────────────────────────────────────

_fonts = {}


def font(path, size):
    k = (path, size)
    if k not in _fonts:
        _fonts[k] = ImageFont.truetype(path, size)
    return _fonts[k]


def cjk(fonts, weight, size):
    return font(os.path.join(fonts, f"NotoSansCJKtc-{weight}.otf"), size)


def serif(size, italic=True):
    return font(os.path.join(BRAND_FONTS, "InstrumentSerif-Italic.ttf" if italic else "InstrumentSerif-Regular.ttf"), size)


def inter(weight, size):
    return font(os.path.join(BRAND_FONTS, f"InterTight-{weight}.ttf"), size)


def runs(text):
    """「就知道*該做什麼*」→ [(就知道, False), (該做什麼, True)]"""
    out, hot = [], False
    for i, part in enumerate(text.split("*")):
        if part:
            out.append((part, hot))
        hot = not hot
    return out


def gradient(size, colors, angle=0.0):
    """水平（略斜）的多色漸層"""
    w, h = size
    small = Image.new("RGB", (256, 1))
    px = small.load()
    n = len(colors) - 1
    for x in range(256):
        t = x / 255 * n
        i = min(int(t), n - 1)
        f = t - i
        a, b = colors[i], colors[i + 1]
        px[x, 0] = tuple(int(a[c] + (b[c] - a[c]) * f) for c in range(3))
    if not angle:
        return small.resize((w, 1), Image.BILINEAR).resize((w, h), Image.NEAREST)
    g = small.resize((w + h, 1), Image.BILINEAR).resize((w + h, h), Image.NEAREST)
    g = g.rotate(angle, resample=Image.BICUBIC, expand=False)
    return g.crop((h // 2, 0, h // 2 + w, h))


def draw_tracked(canvas, xy, text, f, fill, tracking=0.0):
    """一個字一個字畫（中文字距收緊一點）；英文單字整個畫，保留字距調整"""
    x, y = xy
    tokens, buf = [], ""
    for ch in text:
        if ch.isascii() and not ch.isspace():
            buf += ch
            continue
        if buf:
            tokens.append(buf)
            buf = ""
        tokens.append(ch)
    if buf:
        tokens.append(buf)
    d = ImageDraw.Draw(canvas)
    for tok in tokens:
        d.text((x, y), tok, font=f, fill=fill)
        x += f.getlength(tok) + f.size * tracking
    return x


def text_width(text, f, tracking=0.0):
    tokens, buf, w = [], "", 0.0
    for ch in text:
        if ch.isascii() and not ch.isspace():
            buf += ch
            continue
        if buf:
            tokens.append(buf)
            buf = ""
        tokens.append(ch)
    if buf:
        tokens.append(buf)
    for tok in tokens:
        w += f.getlength(tok) + f.size * tracking
    return w


def headline(canvas, xy, text, f, tracking, leading):
    """標題：一般字是 INK，*重點* 是 Xena 的彩虹漸層"""
    x0, y = xy
    for line in text.split("\n"):
        x = x0
        for part, hot in runs(line):
            if not hot:
                x = draw_tracked(canvas, (x, y), part, f, INK, tracking)
                continue
            w = int(text_width(part, f, tracking)) + f.size
            h = int(f.size * 1.5)
            mask = Image.new("L", (w, h), 0)
            draw_tracked(mask, (0, 0), part, f, 255, tracking)
            fill = gradient((w, h), IRIS)
            canvas.paste(fill, (int(x), int(y)), mask)
            x += text_width(part, f, tracking)
        y += f.size * leading
    return y


# ── 背景：連續的光帶 ──────────────────────────────────────────────────────────

def panorama(size, count, seed=7):
    """所有宣傳圖接起來的一整張背景：暖黑底、沿著一條波浪排的光暈、細顆粒"""
    w, h = size
    W = w * count
    scale = 16
    sw, sh = W // scale, h // scale
    layer = Image.new("RGB", (sw, sh), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    rnd = random.Random(seed)
    steps = count * 3
    for i in range(steps):
        t = i / (steps - 1)
        cx = t * sw
        # 波浪：一張在上、一張在下，光帶跨過接縫
        cy = sh * (0.5 + 0.30 * math.sin(t * math.pi * count * 0.62 + 0.6))
        r = sh * (0.20 + 0.10 * rnd.random())
        color = GLOW[i % len(GLOW)]
        k = 0.55 + 0.25 * rnd.random()
        d.ellipse((cx - r, cy - r * 0.8, cx + r, cy + r * 0.8), fill=tuple(int(c * k) for c in color))
    layer = layer.filter(ImageFilter.GaussianBlur(sh * 0.16))
    layer = layer.resize((W, h), Image.BICUBIC)
    base = Image.new("RGB", (W, h), PAGE)
    # 光暈壓暗，像在很深的底下透出來
    glow = Image.eval(layer, lambda v: int(v * 0.42))
    out = ImageChops.add(base, glow)
    # 上緣、下緣再暗一點（字在的地方乾淨）
    vignette = Image.new("L", (1, h))
    for y in range(h):
        t = y / (h - 1)
        vignette.putpixel((0, y), int(255 * (0.55 + 0.45 * math.sin(t * math.pi))))
    vignette = vignette.resize((W, h))
    out = Image.composite(out, Image.new("RGB", (W, h), PAGE), vignette)
    return thread(out, w, count)


def thread(img, w, count):
    """一條細細的光線，從第一張一路波到最後一張（在手機後面穿過，並排時接在一起）"""
    W, H = img.size
    pts = []
    for x in range(-40, W + 41, 8):
        t = x / W
        y = H * (0.50 + 0.13 * math.sin(t * math.pi * count * 0.5 + 0.9) + 0.035 * math.sin(t * math.pi * count * 1.7))
        pts.append((x, y))
    colors = IRIS + [ACCENT] + IRIS[::-1]

    def color_at(x):
        t = (x / W * (len(colors) - 1) * 2) % (len(colors) - 1)
        i = int(t)
        f = t - i
        a, b = colors[i], colors[min(i + 1, len(colors) - 1)]
        return tuple(int(a[c] + (b[c] - a[c]) * f) for c in range(3))

    glow = Image.new("RGB", (W, H), (0, 0, 0))
    core = Image.new("RGB", (W, H), (0, 0, 0))
    gd, cd = ImageDraw.Draw(glow), ImageDraw.Draw(core)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        c = color_at(x0)
        gd.line((x0, y0, x1, y1), fill=c, width=26)
        cd.line((x0, y0, x1, y1), fill=c, width=4)
    glow = glow.filter(ImageFilter.GaussianBlur(22)).point(lambda v: v * 50 // 100)
    core = core.point(lambda v: v * 78 // 100)
    return ImageChops.add(ImageChops.add(img, glow), core)


def grain(img, amount=7, seed=3):
    """細顆粒（避免大面積漸層出現色階）"""
    noise = Image.effect_noise(img.size, 64).point(lambda v: 128 + (v - 128) * amount // 64)
    noise = Image.merge("RGB", (noise, noise, noise))
    return ImageChops.add(img, noise, scale=1.0, offset=-128)


# ── 裝置 ─────────────────────────────────────────────────────────────────────

def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return m


def vertical(size, top, bottom):
    g = Image.new("RGB", (1, 2))
    g.putpixel((0, 0), top)
    g.putpixel((0, 1), bottom)
    return g.resize(size, Image.BILINEAR)


def device(shot, d):
    """截圖放進手機／平板：鈦金屬邊框、黑色邊、側邊按鍵。回傳 RGBA 與螢幕在裡面的位置"""
    sw = d["shot_w"]
    sh = round(shot.height * sw / shot.width)
    screen = shot.resize((sw, sh), Image.LANCZOS)
    r = round(sw * d["radius"])
    bezel = round(sw * d["bezel"])
    rim = max(4, bezel // 4)  # 金屬邊的厚度
    btn = rim + 3 if d["phone"] else 0
    W, H = sw + bezel * 2 + btn * 2, sh + bezel * 2
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ox = btn
    body = (W - btn * 2, H)
    R = r + bezel

    # 側邊按鍵（手機）：左邊動作鍵、音量；右邊電源
    if d["phone"]:
        bd = ImageDraw.Draw(out)
        metal = (74, 71, 67, 255)
        for (y0, y1, side) in [(0.155, 0.19, "l"), (0.235, 0.30, "l"), (0.32, 0.385, "l"), (0.245, 0.345, "r")]:
            x = 0 if side == "l" else W - btn * 2
            bd.rounded_rectangle((x, int(H * y0), x + btn * 2, int(H * y1)), radius=btn, fill=metal)

    # 金屬邊：上亮下暗的漸層
    frame = vertical(body, (138, 133, 126), (52, 50, 47)).convert("RGBA")
    frame.putalpha(rounded_mask(body, R))
    out.alpha_composite(frame, (ox, 0))
    # 金屬邊內側的高光（細線）
    hi = Image.new("RGBA", body, (0, 0, 0, 0))
    ImageDraw.Draw(hi).rounded_rectangle((1, 1, body[0] - 2, body[1] - 2), radius=R - 1, outline=(255, 255, 255, 46), width=2)
    out.alpha_composite(hi, (ox, 0))
    # 黑色的邊
    inner = (body[0] - rim * 2, body[1] - rim * 2)
    black = Image.new("RGBA", inner, (6, 6, 6, 255))
    black.putalpha(rounded_mask(inner, R - rim))
    out.alpha_composite(black, (ox + rim, rim))
    # 螢幕
    scr = screen.convert("RGBA")
    scr.putalpha(rounded_mask((sw, sh), r))
    out.alpha_composite(scr, (ox + bezel, bezel))
    # 玻璃的反光：左上一道很淡的斜光
    sheen = gradient((sw, sh), [(255, 255, 255), (0, 0, 0), (0, 0, 0)], angle=-24).convert("L")
    sheen = sheen.point(lambda v: v * 14 // 255)
    sheen = ImageChops.multiply(sheen, rounded_mask((sw, sh), r))
    white = Image.new("RGBA", (sw, sh), (255, 255, 255, 0))
    white.putalpha(sheen)
    out.alpha_composite(white, (ox + bezel, bezel))
    return out, (ox + bezel, bezel, sw, sh)


def place(canvas, img, x, y):
    """alpha_composite，但可以超出畫布（負的座標、超出右下）"""
    x, y = int(round(x)), int(round(y))
    sx, sy = max(0, -x), max(0, -y)
    ex, ey = min(img.width, canvas.width - x), min(img.height, canvas.height - y)
    if ex <= sx or ey <= sy:
        return
    canvas.alpha_composite(img.crop((sx, sy, ex, ey)), (x + sx, y + sy))


def shadow(canvas, box, radius, blur, color=(0, 0, 0), alpha=200, spread=0, dy=0):
    x0, y0, x1, y1 = box
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle((x0 - spread, y0 - spread + dy, x1 + spread, y1 + spread + dy), radius=radius + spread, fill=color + (alpha,))
    return Image.alpha_composite(canvas, layer.filter(ImageFilter.GaussianBlur(blur)))


def callout(canvas, shot, zoom, dev_box, screen, d):
    """把截圖的一塊放大，浮在手機旁邊：圓角、細邊、深陰影"""
    zx0, zy0, zx1, zy1 = zoom["box"]
    crop = shot.crop((int(zx0 * shot.width), int(zy0 * shot.height), int(zx1 * shot.width), int(zy1 * shot.height)))
    cw = int(canvas.width * zoom.get("width", 0.62))
    ch = round(crop.height * cw / crop.width)
    crop = crop.resize((cw, ch), Image.LANCZOS).convert("RGBA")
    rad = round(cw * zoom.get("radius", 0.05))
    crop.putalpha(rounded_mask((cw, ch), rad))
    border = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle((0, 0, cw - 1, ch - 1), radius=rad, outline=(255, 255, 255, 40), width=3)
    crop.alpha_composite(border)
    W = canvas.width
    if zoom.get("pop"):
        # 從手機裡「浮出來」：放大後的中心對準原本那一塊在手機上的位置
        sx, sy, sw, sh = screen
        cx = dev_box[0] + sx + (zx0 + zx1) / 2 * sw
        cy = dev_box[1] + sy + (zy0 + zy1) / 2 * sh
        x, y = int(cx - cw / 2), int(cy - ch / 2 + zoom.get("dy", 0) * canvas.height)
    else:
        side = zoom.get("side", "center")
        x = int(W * 0.045) if side == "left" else W - cw - int(W * 0.045) if side == "right" else (W - cw) // 2
        y = int(canvas.height * zoom["y"])
    canvas = shadow(canvas, (x, y, x + cw, y + ch), rad, blur=60, alpha=230, dy=40)
    canvas = shadow(canvas, (x, y, x + cw, y + ch), rad, blur=18, alpha=140, dy=10)
    place(canvas, crop, x, y)
    return canvas


# ── 一張 ─────────────────────────────────────────────────────────────────────

def lockup(canvas, x, y, size):
    """StudioX 的標誌（App 圖示的三角形，用向量畫）＋ studiox. 字樣。回傳下緣的 y"""
    d = ImageDraw.Draw(canvas)
    s = size / 614  # 圖示裡標誌的範圍是 205..819
    P = lambda px, py: (x + (px - 205) * s, y + (py - 205) * s)  # noqa: E731
    d.polygon([P(205, 205), P(819, 205), P(205, 819)], fill=INK)
    d.polygon([P(530, 530), P(819, 530), P(819, 819)], fill=INK)
    d.polygon([P(530, 530), P(530, 819), P(819, 819)], fill=(255, 90, 31))
    f = inter("Bold", int(size * 1.18))
    tx = x + size * 1.32
    ty = y + size * 0.5 - f.size * 0.62
    d.text((tx, ty), "studiox", font=f, fill=INK)
    d.text((tx + f.getlength("studiox"), ty), ".", font=f, fill=(255, 90, 31))
    return y + size


def text_block(canvas, fonts, d, slide, index, y):
    """編號＋細線＋小標、標題、說明（靠左，像 App 的版面）。回傳下緣的 y"""
    m = d["margin"]
    draw = ImageDraw.Draw(canvas)
    if slide.get("hero"):
        y = lockup(canvas, m, y - d["eyebrow"] * 0.4, int(d["eyebrow"] * 1.5)) + int(d["eyebrow"] * 2.4)
    # 01 ─── AI 店長 Xena
    num = f"{index:02d}"
    f_num = serif(int(d["eyebrow"] * 1.9))
    draw.text((m, y - int(d["eyebrow"] * 0.62)), num, font=f_num, fill=ACCENT)
    nx = m + f_num.getlength(num) + d["eyebrow"] * 0.7
    ly = y + int(d["eyebrow"] * 0.62)
    draw.line((nx, ly, nx + d["eyebrow"] * 2.2, ly), fill=ACCENT + (255,), width=3)
    f_eye = cjk(fonts, "Medium", d["eyebrow"])
    draw_tracked(canvas, (nx + d["eyebrow"] * 2.8, y - int(d["eyebrow"] * 0.12)), slide["eyebrow"], f_eye, INK2, 0.08)
    y += int(d["eyebrow"] * 2.6)
    size = d["hero_title"] if slide.get("hero") else d["title"]
    f_title = cjk(fonts, "Bold", size)
    y = headline(canvas, (m - size * 0.04, y), slide["title"], f_title, tracking=-0.025, leading=1.24)
    y += int(d["sub"] * 0.55)
    f_sub = cjk(fonts, "Regular", d["sub"])
    draw_tracked(canvas, (m, y), slide["sub"], f_sub, INK2, 0.02)
    return y + int(d["sub"] * 1.5)


def compose(device_key, slide, index, background, fonts, raw_dir, out_dir):
    d = DEVICES[device_key]
    scene = slide.get("shot", {}).get(device_key, slide["key"])
    src = os.path.join(raw_dir, f"{d['prefix']}{scene}.jpg")
    if not os.path.exists(src):
        print(f"  沒有 {src}，略過")
        return None
    W, H = d["size"]
    canvas = background.crop(((index - 1) * W, 0, index * W, H)).convert("RGBA")
    shot = Image.open(src).convert("RGB")
    dev, screen = device(shot, d)
    layout = slide.get("layout_by", {}).get(device_key, slide.get("layout", "top"))

    if layout == "top":
        text_bottom = text_block(canvas, fonts, d, slide, index, d["top"])
        dx = (W - dev.width) // 2
        dy = int(text_bottom + d["gap"])
    else:
        # 手機在上、超出上緣；字在下面
        dx = (W - dev.width) // 2
        visible = int(H * 0.66)
        dy = visible - dev.height
        # 先量字有多高，再擺在手機下面
        probe = Image.new("RGBA", canvas.size)
        h = text_block(probe, fonts, d, slide, index, 0)
        ty = int(visible + (H - visible - h) / 2 + d["eyebrow"] * 0.6)

    box = (int(dx), int(dy), int(dx + dev.width), int(dy + dev.height))
    # 手機後面：一圈 Xena 色的光、再一層深陰影
    halo = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    cx, cy = (box[0] + box[2]) // 2, (box[1] + box[3]) // 2
    hd.ellipse((cx - dev.width * 0.62, cy - dev.height * 0.36, cx + dev.width * 0.62, cy + dev.height * 0.36), fill=(132, 92, 255, 54))
    canvas = Image.alpha_composite(canvas, halo.filter(ImageFilter.GaussianBlur(W * 0.12)))
    canvas = shadow(canvas, box, int(dev.width * 0.12), blur=90, alpha=235, dy=60)
    place(canvas, dev, dx, dy)

    if layout != "top":
        text_block(canvas, fonts, d, slide, index, ty)

    zoom = slide.get("zoom", {}).get(device_key)
    if zoom:
        canvas = callout(canvas, shot, zoom, box, screen, d)

    os.makedirs(out_dir, exist_ok=True)
    # 高畫質 JPEG（色彩不降採樣，字的邊緣不糊）：一張約 1MB，PNG 要 4MB
    out = os.path.join(out_dir, f"{index:02d}-{slide['key']}.jpg")
    canvas.convert("RGB").save(out, "JPEG", quality=95, subsampling=0, optimize=True)
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--fonts", required=True)
    p.add_argument("--raw", default=RAW)
    p.add_argument("--out", default=os.path.join(ROOT, "docs", "appstore"))
    p.add_argument("--only", default="", help="只做這幾張（畫面代號，逗號分開）")
    p.add_argument("--device", default="", help="只做這個裝置（iphone69／ipad13）")
    args = p.parse_args()
    only = [k for k in args.only.split(",") if k]
    for key, d in DEVICES.items():
        if args.device and key != args.device:
            continue
        out_dir = os.path.join(args.out, key)
        if not only:
            for f in os.listdir(out_dir) if os.path.isdir(out_dir) else []:
                if f.endswith((".png", ".jpg")):
                    os.remove(os.path.join(out_dir, f))
        background = grain(panorama(d["size"], len(SLIDES)))
        for i, slide in enumerate(SLIDES, start=1):
            if only and slide["key"] not in only:
                continue
            made = compose(key, slide, i, background, args.fonts, args.raw, out_dir)
            if made:
                print(made)


if __name__ == "__main__":
    main()
