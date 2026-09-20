# -*- coding: utf-8 -*-
"""把凯森给的 Cloud logo 横图裁成安卓应用图标，并生成各密度资源。

输入：D:\\下载\\Image_1789890840834_943.jpg（500x350，深灰底 34,34,34 的白色线条 logo）
输出：mobile/android/app/src/main/res/mipmap-*/ic_launcher.png（5 个密度）

做法（凯森 2026-09-20 选定）：
  · 裁成正方形，只留中间的三角 logo，去掉左右空白
  · 底色沿用原图深灰 (34,34,34)
  · **留安全边距**：安卓桌面图标是圆的/圆角的，四角会被裁掉，
    所以 logo 只占正方形中央约 62%，剩下的都是背景。

顺便生成两个尺寸的圆形版（ic_launcher_round，有些启动器会用）——
不过项目现在 manifest 只引了 ic_launcher，round 只是备用。
"""
import io
import os

from PIL import Image

SRC = r'D:\下载\Image_1789890840834_943.jpg'
RES = r'D:\App\MyDay\mobile\android\app\src\main\res'

# 各密度的图标边长（安卓标准）
SIZES = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}

# logo 在正方形里占的比例。
# 0.56 是**按最狠的圆形裁切倒推**的：圆形会裁掉边角，logo 的长边（含最上面
# 那行小字 CLOUD）落在外接圆里才有保证。取 0.62 时圆形下小字几乎贴边，
# 放宽到 0.56 留出余量，代价是图标上 logo 稍小一点点。
LOGO_RATIO = 0.56

BG = (34, 34, 34)


def main() -> None:
    src = Image.open(SRC).convert('RGB')
    w, h = src.size

    # 1) 找 logo 边界（白色像素范围）
    gray = src.convert('L')
    px = gray.load()
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            if px[x, y] > 120:
                if x < minx:
                    minx = x
                if y < miny:
                    miny = y
                if x > maxx:
                    maxx = x
                if y > maxy:
                    maxy = y
    if maxx < 0:
        raise SystemExit('没找到 logo（整张图没有够亮的像素）')

    # 2) 算出要裁的正方形：边长取 logo 的长边除以 LOGO_RATIO
    logo_w = maxx - minx + 1
    logo_h = maxy - miny + 1
    side = int(max(logo_w, logo_h) / LOGO_RATIO)

    cx = (minx + maxx) / 2.0
    cy = (miny + maxy) / 2.0
    left = int(round(cx - side / 2.0))
    top = int(round(cy - side / 2.0))
    box = (left, top, left + side, top + side)

    # 3) 裁。源图不够大时先垫一层纯背景色再裁，免得出现黑边。
    pad = 2000
    canvas = Image.new('RGB', (w + pad * 2, h + pad * 2), BG)
    canvas.paste(src, (pad, pad))
    shifted = (box[0] + pad, box[1] + pad, box[2] + pad, box[3] + pad)
    crop = canvas.crop(shifted)
    print('裁切框(原图坐标):', box, '边长:', side)

    # 4) 生成各密度
    for name, size in SIZES.items():
        out_dir = os.path.join(RES, f'mipmap-{name}')
        os.makedirs(out_dir, exist_ok=True)

        icon = crop.resize((size, size), Image.LANCZOS)
        path = os.path.join(out_dir, 'ic_launcher.png')
        icon.save(path, 'PNG', optimize=True)
        print(f'{name:9s} {size}x{size} -> {path}  ({os.path.getsize(path)} bytes)')

        # 圆形版：圆形之外填背景色（深灰底 + 圆形 logo，看着还是方的但角是圆背景）
        round_icon = _round(icon, BG)
        rpath = os.path.join(out_dir, 'ic_launcher_round.png')
        round_icon.save(rpath, 'PNG', optimize=True)


def _round(icon: Image.Image, bg) -> Image.Image:
    """把方形图标裁成圆形，圆外填 bg。"""
    from PIL import ImageDraw

    size = icon.size[0]
    mask = Image.new('L', (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)

    out = Image.new('RGB', (size, size), bg)
    out.paste(icon, (0, 0), mask)
    return out


if __name__ == '__main__':
    main()
