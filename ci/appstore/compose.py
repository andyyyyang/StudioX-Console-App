"""
App Store 宣傳圖：把 App 的截圖（docs/appstore/raw/，ui-screenshots.yml 的 [appstore-shots] 截的）合成「標題＋截圖」的宣傳圖，
存到 docs/appstore/iphone69/、docs/appstore/ipad13/（ci/appstore.py 上傳的就是這兩個資料夾）。

  python3 ci/appstore/compose.py --fonts <放 Noto Sans CJK TC 的資料夾>

每一張的標題、說明在下面的 SLIDES。深色底、品牌橘與 Xena 水珠的紫藍光暈；截圖圓角、細框、往下延伸出畫面。
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW = os.path.join(ROOT, "docs", "appstore", "raw")

# 畫面代號、小標、標題（\n 換行）、說明
SLIDES = [
    ("home", "AI 店長 XENA", "每天一打開，\n就知道要做什麼", "訂單、客人、詢問，Xena 整理好等你決定"),
    ("voice", "用說的", "問一句，\nXena 直接回答", "今天賣得怎樣、誰在等回覆，像跟店長講話"),
    ("line", "客服收件匣", "官網和 LINE 的客人，\n一個地方回", "Xena 先回答，需要真人才轉給你"),
    ("orders", "訂單", "等出貨、待付款，\n一眼看完", "勾一勾，一次標好出貨"),
    ("traffic", "流量與成效", "流量和營收，\n隨時掌握", "即時訪客、Google 搜尋、每天的重點變化"),
    ("product", "商品與內容", "商品、內容，\n手機上就能改", "價格、庫存、圖片，改完網站馬上更新"),
    ("xena", "交代 Xena", "交代她做事，\n你確認才執行", "回客人、改商品、標出貨，重要的事先問你"),
    ("lock", "安全", "Face ID 保護，\n重要動作再確認", "退款、刪除這類動作一定再驗證一次"),
]

DEVICES = {
    # 資料夾、截圖的前綴、畫布大小、截圖寬度、截圖圓角、文字大小
    "iphone69": {"prefix": "iphone69-dark-", "size": (1320, 2868), "shot_w": 1030, "radius": 96, "top": 150,
                 "eyebrow": 46, "title": 112, "sub": 50, "gap": 64},
    "ipad13": {"prefix": "ipad13-dark-", "size": (2064, 2752), "shot_w": 1600, "radius": 56, "top": 130,
               "eyebrow": 50, "title": 120, "sub": 54, "gap": 72},
}

INK = (244, 242, 238)
MUTED = (168, 162, 152)
ACCENT = (255, 90, 31)
BG = (12, 11, 10)


def font(fonts, weight, size):
    return ImageFont.truetype(os.path.join(fonts, f"NotoSansCJKtc-{weight}.otf"), size)


def glow(size):
    """深色底＋品牌橘（右上）與 Xena 水珠的紫、藍（左下）光暈"""
    w, h = size
    base = Image.new("RGB", size, BG)
    layer = Image.new("RGB", size, (0, 0, 0))
    d = ImageDraw.Draw(layer)
    r = int(w * 0.55)
    d.ellipse((int(w * 0.62) - r, int(h * 0.02) - r, int(w * 0.62) + r, int(h * 0.02) + r), fill=(120, 40, 12))
    d.ellipse((int(w * 0.1) - r, int(h * 0.62) - r, int(w * 0.1) + r, int(h * 0.62) + r), fill=(58, 30, 110))
    d.ellipse((int(w * 0.95) - r, int(h * 0.85) - r, int(w * 0.95) + r, int(h * 0.85) + r), fill=(20, 54, 110))
    layer = layer.filter(ImageFilter.GaussianBlur(int(w * 0.22)))
    return Image.blend(base, Image.eval(layer, lambda v: min(255, v + BG[0])), 0.55)


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=radius, fill=255)
    out = Image.new("RGBA", img.size)
    out.paste(img, (0, 0), mask)
    return out


def text_block(draw, fonts, d, canvas_w, slide):
    _, eyebrow, title, sub = slide
    y = d["top"]
    f_eye = font(fonts, "Bold", d["eyebrow"])
    w = draw.textlength(eyebrow, font=f_eye)
    draw.text(((canvas_w - w) / 2, y), eyebrow, font=f_eye, fill=ACCENT)
    y += int(d["eyebrow"] * 1.9)
    f_title = font(fonts, "Black", d["title"])
    for line in title.split("\n"):
        w = draw.textlength(line, font=f_title)
        draw.text(((canvas_w - w) / 2, y), line, font=f_title, fill=INK)
        y += int(d["title"] * 1.22)
    y += int(d["sub"] * 0.5)
    f_sub = font(fonts, "Medium", d["sub"])
    w = draw.textlength(sub, font=f_sub)
    draw.text(((canvas_w - w) / 2, y), sub, font=f_sub, fill=MUTED)
    return y + int(d["sub"] * 1.4)


def compose(device, slide, fonts, raw_dir, out_dir, index):
    d = DEVICES[device]
    src = os.path.join(raw_dir, f"{d['prefix']}{slide[0]}.jpg")
    if not os.path.exists(src):
        print(f"  沒有 {src}，略過")
        return None
    canvas = glow(d["size"]).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    y = text_block(draw, fonts, d, d["size"][0], slide) + d["gap"]

    shot = Image.open(src).convert("RGB")
    sw = d["shot_w"]
    sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    x = (d["size"][0] - sw) // 2
    bezel = max(10, sw // 70)
    # 外框（像手機的邊）與光暈陰影
    frame = Image.new("RGBA", (sw + bezel * 2, sh + bezel * 2), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle((0, 0, frame.width - 1, frame.height - 1), radius=d["radius"] + bezel, fill=(38, 36, 34, 255), outline=(78, 74, 70, 255), width=3)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x - bezel - 10, y - bezel + 30, x + sw + bezel + 10, y + sh + bezel + 60), radius=d["radius"] + bezel, fill=(0, 0, 0, 170))
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(frame, (x - bezel, y - bezel))
    canvas.alpha_composite(rounded(shot, d["radius"]), (x, y))

    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"{index:02d}-{slide[0]}.png")
    canvas.convert("RGB").save(out, "PNG", optimize=True)
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--fonts", required=True)
    p.add_argument("--raw", default=RAW)
    p.add_argument("--out", default=os.path.join(ROOT, "docs", "appstore"))
    p.add_argument("--only", default="")
    args = p.parse_args()
    for device in DEVICES:
        out_dir = os.path.join(args.out, device)
        if not args.only:
            for f in os.listdir(out_dir) if os.path.isdir(out_dir) else []:
                if f.endswith(".png"):
                    os.remove(os.path.join(out_dir, f))
        n = 0
        for slide in SLIDES:
            if args.only and slide[0] not in args.only.split(","):
                continue
            n += 1
            made = compose(device, slide, args.fonts, args.raw, out_dir, n)
            if made:
                print(made)


if __name__ == "__main__":
    main()
