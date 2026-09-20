# -*- coding: utf-8 -*-
"""生成安卓自适应图标（adaptive icon，Android 8+ 优先用这套）。

为什么单独做这一套：
  · mipmap-*/ic_launcher.png 是给老系统（Android 7 及以下）用的位图；
  · Android 8+ 有 adaptive icon，系统会把「前景层」裁成自己想要的形状
    （圆的、方的、水滴形……各家桌面不一样），**裁得比位图狠**。
  · 自适应图标的规范：总画布 108dp，其中**安全区只有中间 72dp**（66%），
    外面那圈随时可能被裁掉。所以 logo 必须压在中间 66% 里。

生成物：
  mipmap-anydpi-v26/ic_launcher.xml          前景/背景的声明
  mipmap-anydpi-v26/ic_launcher_round.xml    同上（圆形启动器）
  drawable/ic_launcher_foreground.png        前景层（透明底 + 白色 logo）
  values/ic_launcher_background.xml          背景色（深灰 34,34,34）
"""
import io
import os

from PIL import Image

SRC = r'D:\下载\Image_1789890840834_943.jpg'
RES = r'D:\App\MyDay\mobile\android\app\src\main\res'

SIZES = {
    'mdpi': 108,
    'hdpi': 162,
    'xhdpi': 216,
    'xxhdpi': 324,
    'xxxhdpi': 432,
}

BG = '343434'  # 深灰 (34,34,34) 的十六进制

# 自适应图标安全区占画布的比例：官方规范是 72/108 = 0.6667。
# 但圆形启动器（如部分国产 ROM 的默认桌面）会裁到接近外接圆，
# 小字 CLOUD 落在圆上会显得贴边，所以收到 0.52 多留一档余量。
SAFE_RATIO = 0.52


def main() -> None:
    src = Image.open(SRC).convert('RGB')
    w, h = src.size
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
        raise SystemExit('没找到 logo')

    logo_w = maxx - minx + 1
    logo_h = maxy - miny + 1
    cx = (minx + maxx) / 2.0
    cy = (miny + maxy) / 2.0

    for name, canvas_size in SIZES.items():
        out_dir = os.path.join(RES, f'mipmap-{name}')
        os.makedirs(out_dir, exist_ok=True)

        # 前景层：透明底，logo 按 SAFE_RATIO 缩放后居中
        fg = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
        target = int(canvas_size * SAFE_RATIO)
        scale = target / max(logo_w, logo_h)

        # 把 logo 区域抠出来放大；因为是白线条 + 深底，
        # 直接缩放整块会带过来一圈深色方块，所以按亮度转成 alpha
        box = (int(round(cx - logo_w / 2)), int(round(cy - logo_h / 2)),
               int(round(cx + logo_w / 2)), int(round(cy + logo_h / 2)))
        pad = 400
        canvas = Image.new('RGB', (w + pad * 2, h + pad * 2), (0, 0, 0))
        canvas.paste(src, (pad, pad))
        crop = canvas.crop((box[0] + pad, box[1] + pad,
                            box[2] + pad, box[3] + pad))

        nw = max(1, int(round(crop.width * scale)))
        nh = max(1, int(round(crop.height * scale)))
        crop = crop.resize((nw, nh), Image.LANCZOS)

        # 亮度当 alpha：白线条留下，深底变透明
        alpha = crop.convert('L').point(lambda v: 0 if v < 70 else min(255, int((v - 70) * 255 / 110)))
        white = Image.new('RGBA', (nw, nh), (255, 255, 255, 255))
        white.putalpha(alpha)

        fg.paste(white, ((canvas_size - nw) // 2, (canvas_size - nh) // 2), white)
        fg_path = os.path.join(RES, 'drawable', 'ic_launcher_foreground.png')
        os.makedirs(os.path.dirname(fg_path), exist_ok=True)
        # 只有一套前景图（放 xxxhdpi 尺寸），其余密度靠系统缩放——
        # 自适应图标这么做是常见做法，省得每个密度都存一份。
        if name == 'xxxhdpi':
            fg.save(fg_path, 'PNG', optimize=True)
            print(f'前景层 {canvas_size}x{canvas_size} -> {fg_path}')

    # anydpi-v26 的两份 xml
    anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n'
    )
    for fn in ('ic_launcher.xml', 'ic_launcher_round.xml'):
        p = os.path.join(anydpi, fn)
        io.open(p, 'w', encoding='utf-8', newline='\n').write(xml)
        print('写', p)

    # 背景色
    values = os.path.join(RES, 'values')
    os.makedirs(values, exist_ok=True)
    bp = os.path.join(values, 'ic_launcher_background.xml')
    io.open(bp, 'w', encoding='utf-8', newline='\n').write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        f'    <!-- 图标底色：沿用凯森给的 logo 原图深灰 -->\n'
        f'    <color name="ic_launcher_background">#{BG}</color>\n'
        '</resources>\n'
    )
    print('写', bp)


if __name__ == '__main__':
    main()
