# -*- coding: utf-8 -*-
"""生成 / 预览通知栏小图标（notification small icon）。

⚠️ 重要：这个脚本**只用来预览和比对形状，不要再用它的输出去当最终图标**。

── 为什么 ──
v1.7.6 的第一版方案就是这个脚本生成 5 张 PNG
（drawable-{m,h,x,xx,xxx}dpi/ic_notification.png）。
源 PNG 经检查是对的（上框 + 实心倒三角，30.6% 不透明像素），
但打进 release APK 之后被 AAPT 的 PNG 优化**重新编码成了细描边空心框**，
形状整个丢掉 —— 通知栏 24dp 下那种细线等于看不见。

最终定稿改用矢量 drawable：
    android/app/src/main/res/drawable/ic_notification.xml
矢量不走 PNG 优化，形状 100% 保真，体积也更小。
（还有一个必须的配套：res/raw/keep.xml 里的 tools:keep，
 否则资源压缩器会把 ic_notification 当成「没人引用」删掉。）

── 这个脚本现在的作用 ──
从原图裁出倒三角主体、做出剪影，导出一张预览图，
用来核对 drawable/ic_notification.xml 里的 path 画得对不对。
输出到 tools/_preview/，不进项目资源目录。

── 形状（供 XML 对照）──
  云朵主体：圆角横框，约 x 2.5~21.5、y 5~13
  云朵的尖：实心倒三角，约 x 7.5~16.5、y 14.5~20.5
"""
import os

from PIL import Image, ImageFilter

SRC = r'D:\下载\Image_1789890840834_943.jpg'
OUT = r'D:\App\MyDay\tools\_preview'

# 倒三角主体的范围（原图像素坐标，2026-09-20 实测）。
# 上边 y≈140 起（CLOUD 小字和横线下面），下尖 y≈228；横向 x 188-313。
TRI_BOX = (186, 138, 316, 230)

# 预览尺寸（96px = xxxhdpi，通知图标最大也就用到这里）
PREVIEW = 96


def main() -> None:
    src = Image.open(SRC).convert('RGB')

    # 1) 只取倒三角那块，放大处理（小尺寸下更精细）
    crop = src.crop(TRI_BOX).convert('L')
    cw, ch = crop.size
    scale = 8
    big = crop.resize((cw * scale, ch * scale), Image.LANCZOS)

    # 2) 二值化：把亮线条当作「要保留的形状」
    mask = big.point(lambda v: 255 if v > 110 else 0)

    # 3) 填实：逐行取每行最左/最右的亮像素，中间全填 → 实心剪影
    solid = Image.new('L', mask.size, 0)
    mp = mask.load()
    sp = solid.load()
    bw, bh = mask.size
    for y in range(bh):
        xs = [x for x in range(bw) if mp[x, y] > 0]
        if not xs:
            continue
        for x in range(min(xs), max(xs) + 1):
            sp[x, y] = 255

    # 4) 打磨：轻微膨胀，避免细尖角丢像素
    solid = solid.filter(ImageFilter.MaxFilter(3))

    # 5) 转成「纯白 + alpha」
    white = Image.new('RGBA', solid.size, (255, 255, 255, 0))
    white.putalpha(solid)

    # 6) 放进正方形画布（保持比例、居中）
    lw, lh = white.size
    side_src = max(lw, lh)
    placed = Image.new('RGBA', (side_src, side_src), (255, 255, 255, 0))
    placed.paste(white, ((side_src - lw) // 2, (side_src - lh) // 2), white)

    # 7) 导出预览（白底反色，方便肉眼看形状）
    os.makedirs(OUT, exist_ok=True)
    canvas = Image.new('RGBA', (PREVIEW, PREVIEW), (0, 0, 0, 0))
    scaled = placed.resize((PREVIEW, PREVIEW), Image.LANCZOS)
    canvas.paste(scaled, (0, 0), scaled)

    out = os.path.join(OUT, 'ic_notification_preview.png')
    canvas.save(out)
    print('wrote', out, f'{PREVIEW}x{PREVIEW}')

    # 再导一张「黑底白图」，更接近通知栏里的实际观感
    bg = Image.new('RGBA', (PREVIEW, PREVIEW), (40, 40, 40, 255))
    bg.alpha_composite(canvas)
    out2 = os.path.join(OUT, 'ic_notification_preview_dark.png')
    bg.convert('RGB').save(out2)
    print('wrote', out2)


if __name__ == '__main__':
    main()
