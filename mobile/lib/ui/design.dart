/// 设计令牌与通用组件（v2.0「校园助手」移动端设计系统）。
///
/// 全部取值来自 `设计规范.md` + `design-system.css`，别在页面里写死色值/字号。
///
/// 要点：
///   · 主色是**靛蓝** #2B54C8（不是刺眼的纯蓝），大面积用它配阴影
///   · 橙色 #F07A28 是稀缺色，只给「进行中 / 即将开始 / 预警」用，一屏最多 1~2 次
///   · 中性色带冷调（蓝灰），分 900/700/500/400/300/200/100/50 八档
///   · 字号 7 档：40 / 26 / 20 / 16 / 14 / 12.5 / 11；字重只用 400/500/600/700
///   · 圆角四级 10 / 14 / 18 / 24（卡片统一 14），间距走 8pt 栅格
///   · 阴影极浅、多层、冷调；深色模式靠 1px 边框分层，不用重阴影
///   · 数字一律等宽（tabular-nums），切换时不左右跳
library;

import 'package:flutter/material.dart';

/// 一套配色（浅色 / 深色各一份，同名同义）。
class Tone {
  const Tone({
    required this.bg,
    required this.surface,
    required this.surfaceSunk,
    required this.ink900,
    required this.ink700,
    required this.ink500,
    required this.ink400,
    required this.ink300,
    required this.ink200,
    required this.ink100,
    required this.primary,
    required this.primaryHover,
    required this.primarySoft,
    required this.primaryBorder,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.successSoft,
    required this.warn,
    required this.warnSoft,
    required this.danger,
    required this.dangerSoft,
    required this.onPrimary,
  });

  /// 页面底色。
  final Color bg;

  /// 卡片底。
  final Color surface;

  /// 下沉底（弹层里的次级块、分隔区域）。
  final Color surfaceSunk;

  /// 主标题 / 关键数值。
  final Color ink900;

  /// 正文。
  final Color ink700;

  /// 次要文字。
  final Color ink500;

  /// 辅助说明、时间。
  final Color ink400;

  /// 占位符、禁用、已结束。
  final Color ink300;

  /// 分隔线、边框。
  final Color ink200;

  /// 卡片内嵌底。
  final Color ink100;

  /// 主色，也是最低一档的浅底。
  final Color primary;
  final Color primaryHover;
  final Color primarySoft;
  final Color primaryBorder;

  /// 强调橙：进行中 / 即将开始 / 预警。**一屏最多用一两次**。
  final Color accent;
  final Color accentSoft;

  final Color success;
  final Color successSoft;
  final Color warn;
  final Color warnSoft;

  /// 危险：只给「清除数据」这类。
  final Color danger;
  final Color dangerSoft;

  /// 主色上的文字。
  final Color onPrimary;

  static const Tone light = Tone(
    bg: Color(0xFFF4F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceSunk: Color(0xFFF4F6FA),
    ink900: Color(0xFF0F1420),
    ink700: Color(0xFF333C52),
    ink500: Color(0xFF5E6980),
    ink400: Color(0xFF8A94A8),
    ink300: Color(0xFFB4BCCB),
    ink200: Color(0xFFE2E6EE),
    ink100: Color(0xFFEDF0F5),
    primary: Color(0xFF2B54C8),
    primaryHover: Color(0xFF1F3F9E),
    primarySoft: Color(0xFFEEF3FF),
    primaryBorder: Color(0xFFBCCEFB),
    accent: Color(0xFFF07A28),
    accentSoft: Color(0xFFFFF4EB),
    success: Color(0xFF0E9B5F),
    successSoft: Color(0xFFE8F7EF),
    warn: Color(0xFFC78413),
    warnSoft: Color(0xFFFFF7E5),
    danger: Color(0xFFD63B3B),
    dangerSoft: Color(0xFFFDEDED),
    onPrimary: Color(0xFFFFFFFF),
  );

  static const Tone dark = Tone(
    bg: Color(0xFF131720),
    surface: Color(0xFF1C2230),
    surfaceSunk: Color(0xFF232A3A),
    ink900: Color(0xFFF2F5FA),
    ink700: Color(0xFFCBD3E1),
    ink500: Color(0xFF98A3B8),
    ink400: Color(0xFF7C879D),
    ink300: Color(0xFF5D677D),
    ink200: Color(0xFF2C3345),
    ink100: Color(0xFF232A3A),
    primary: Color(0xFF6B8CF0),
    primaryHover: Color(0xFF93AEF6),
    primarySoft: Color(0xFF1E2A4A),
    primaryBorder: Color(0xFF2E3D63),
    accent: Color(0xFFF07A28),
    accentSoft: Color(0xFF3A2A1A),
    success: Color(0xFF3FBF85),
    successSoft: Color(0xFF14301F),
    warn: Color(0xFFE0A63C),
    warnSoft: Color(0xFF332813),
    danger: Color(0xFFFF6B6B),
    dangerSoft: Color(0xFF3A1F1F),
    onPrimary: Color(0xFFFFFFFF),
  );

  static Tone of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// 字阶。**只允许这几档**；颜色由 [Tone] 补。
class Type {
  const Type._();

  /// 数字用等宽字形，切换值时不会左右跳。
  static const List<FontFeature> _tnum = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  /// 40 / Bold —— 天气大温度（唯一展示级）。
  static const TextStyle display = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: -1.8,
    fontFeatures: _tnum,
  );

  /// 26 / Bold —— 页面主标题。
  static const TextStyle h1 = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.65,
  );

  /// 20 / Bold —— 强调卡标题。
  static const TextStyle h2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.3,
  );

  /// 16 / SemiBold —— 列表项标题、卡片小标题。
  static const TextStyle h3 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.1,
  );

  /// 14 / Regular —— 正文（中文行高松一点，1.55）。
  static const TextStyle body = TextStyle(fontSize: 14, height: 1.55);

  /// 12.5 / Regular —— 辅助说明。
  static const TextStyle sm = TextStyle(fontSize: 12.5, height: 1.45);

  /// 11 / Medium —— 标签、角标、时间。
  static const TextStyle xs = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  /// 数字专用（等宽）：金额、时间、温度。
  static TextStyle num(TextStyle base) =>
      base.copyWith(fontFeatures: _tnum, letterSpacing: -0.02 * base.fontSize!);
}

/// 圆角。
class R {
  const R._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;
}

/// 间距（8pt 栅格）。
class Sp {
  const Sp._();
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;

  /// 页面左右安全边距。
  static const double gutter = 16;

  /// 底部留白：给底部导航让位（60 的导航 + 余量）。
  static const double bottomInset = 84;
}

/// 阴影：极浅、多层、冷调。
class Sh {
  const Sh._();

  static List<BoxShadow> _of(BuildContext context, _ShLevel level) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = dark ? const Color(0xFF000000) : const Color(0xFF0F1420);
    switch (level) {
      case _ShLevel.xs:
        return <BoxShadow>[
          BoxShadow(color: c.withValues(alpha: dark ? .30 : .05), blurRadius: 2, offset: const Offset(0, 1)),
        ];
      case _ShLevel.md:
        return <BoxShadow>[
          BoxShadow(color: c.withValues(alpha: dark ? .30 : .04), blurRadius: 4, offset: const Offset(0, 2)),
          BoxShadow(color: c.withValues(alpha: dark ? .32 : .06), blurRadius: 20, offset: const Offset(0, 8)),
        ];
      case _ShLevel.brand:
        return <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF2B54C8).withValues(alpha: dark ? .45 : .28),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ];
      case _ShLevel.sm:
        return <BoxShadow>[
          BoxShadow(color: c.withValues(alpha: dark ? .30 : .04), blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(color: c.withValues(alpha: dark ? .24 : .04), blurRadius: 8, offset: const Offset(0, 2)),
        ];
    }
  }
}

enum _ShLevel { xs, sm, md, brand }

/// 正文默认色 = 主文字色，没给颜色的 Text 都落在这一档。
extension ToneContext on BuildContext {
  Tone get tone => Tone.of(this);

  TextStyle get h1 => Type.h1.copyWith(color: tone.ink900);
  TextStyle get h2 => Type.h2.copyWith(color: tone.ink900);
  TextStyle get h3 => Type.h3.copyWith(color: tone.ink900);
  TextStyle get body => Type.body.copyWith(color: tone.ink700);
  TextStyle get sm => Type.sm.copyWith(color: tone.ink400);
  TextStyle get xs => Type.xs.copyWith(color: tone.ink400);

  /// 卡片/面板统一阴影（极浅）。
  List<BoxShadow> get cardShadow => Sh._of(this, _ShLevel.sm);
}

/// 页面底：纯色底（主题里 scaffoldBackgroundColor 已经是它，需要自己兜底时才用）。
class PageSurface extends StatelessWidget {
  const PageSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(color: Tone.of(context).bg, child: child);
}

/// 卡片：白底 + 圆角 14 + 极浅阴影，内边距 16。
class Card2 extends StatelessWidget {
  const Card2({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.radius = R.md,
    this.sunk = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;

  /// true 用下沉底（嵌在卡片里的次级块）。
  final bool sunk;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = Tone.of(context);
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: sunk ? tone.surfaceSunk : tone.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: sunk ? null : Sh._of(context, _ShLevel.sm),
      ),
      // 里面垫一层透明 Material：卡片里的 InkWell / ListTile 才有地方画水波纹
      // （不然 Flutter 会断言「ListTile 的背景色和墨水可能看不见」）。
      child: Padding(
        padding: padding,
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
    return Padding(
      padding: margin,
      child: onTap == null
          ? box
          : _Pressable(radius: radius, onTap: onTap!, child: box),
    );
  }
}

/// 按下有轻微回弹（scale .975），和原型的 `.feature-tile:active` 一致。
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap, required this.radius});

  final Widget child;
  final VoidCallback onTap;
  final double radius;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? .975 : 1,
        duration: const Duration(milliseconds: 220),
        curve: const CurveCubic(),
        child: widget.child,
      ),
    );
  }
}

/// 原型的缓动 `cubic-bezier(.32, .72, 0, 1)`：起步快、收尾慢。
class CurveCubic extends Curve {
  const CurveCubic();
  @override
  double transformInternal(double t) => Cubic(.32, .72, 0, 1).transform(t);
}

/// 分组标题（设置页用）。
class GroupLabel extends StatelessWidget {
  const GroupLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 3, bottom: Sp.s2),
        child: Text(
          text,
          style: Type.xs.copyWith(
            color: Tone.of(context).ink400,
            fontWeight: FontWeight.w600,
            letterSpacing: .55,
          ),
        ),
      );
}

/// 分组卡：一张卡里包若干行，行间 1px 分隔（左侧缩进 55）。
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children, this.margin = EdgeInsets.zero});

  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final tone = Tone.of(context);
    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(R.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tone.surface,
            borderRadius: BorderRadius.circular(R.md),
            boxShadow: Sh._of(context, _ShLevel.sm),
          ),
          child: Column(
            children: <Widget>[
              for (var i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 55,
                    color: tone.ink200,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置/列表里的一行：左图标（32×32 圆角 9）+ 标题 + 副标题 + 右侧值 + 箭头。
class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.tint,
    this.tintColor,
    this.value,
    this.valueColor,
    this.chevron = true,
    this.onTap,
    this.trailing,
    this.danger = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? tint;
  final Color? tintColor;
  final String? value;
  final Color? valueColor;
  final bool chevron;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tone = Tone.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              IconPlate(
                icon: icon!,
                size: 32,
                radius: 9,
                iconSize: 17,
                tint: tint,
                tintColor: tintColor,
              ),
              const SizedBox(width: 11),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: Type.h3.copyWith(
                      fontSize: 16,
                      color: danger ? tone.danger : tone.ink900,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: Type.xs.copyWith(color: tone.ink400)),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else ...<Widget>[
              if (value != null)
                Text(
                  value!,
                  style: Type.sm.copyWith(color: valueColor ?? tone.ink400),
                ),
              if (chevron && !danger) ...<Widget>[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 17, color: tone.ink300),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 方形图标底板（功能宫格 38/11、设置行 32/9、记账分类 44/12）。
class IconPlate extends StatelessWidget {
  const IconPlate({
    super.key,
    required this.icon,
    this.size = 38,
    this.radius = 11,
    this.iconSize,
    this.tint,
    this.tintColor,
  });

  final IconData icon;
  final double size;
  final double radius;
  final double? iconSize;
  final Color? tint;
  final Color? tintColor;

  @override
  Widget build(BuildContext context) {
    final tone = Tone.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint ?? tone.primarySoft,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize ?? size * .53, color: tintColor ?? tone.primary),
    );
  }
}

/// 顶部右上角的「第 N 教学周」胶囊。
class WeekChip extends StatelessWidget {
  const WeekChip({super.key, required this.text, this.strong = true});

  final String text;

  /// false = 教学周没设置，用弱色。
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final tone = Tone.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: strong ? tone.primarySoft : tone.ink100,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: strong ? tone.primaryBorder : tone.ink200),
      ),
      child: Text(
        text,
        style: Type.xs.copyWith(
          color: strong ? tone.primary : tone.ink400,
          fontWeight: FontWeight.w600,
          letterSpacing: .22,
        ),
      ),
    );
  }
}

/// 小胶囊（标签、角标、状态）。
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.text,
    this.bg,
    this.fg,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  });

  final String text;
  final Color? bg;
  final Color? fg;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tone = Tone.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg ?? tone.ink100,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Text(
        text,
        style: Type.xs.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: fg ?? tone.ink300,
        ),
      ),
    );
  }
}

/// 圆角胶囊按钮（「回到今天」这类）。
class ChipButton extends StatelessWidget {
  const ChipButton({super.key, required this.label, this.icon, this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = Tone.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        decoration: BoxDecoration(
          color: tone.primarySoft,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: tone.primaryBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 13, color: tone.primary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: Type.sm.copyWith(
                color: tone.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 区块标题行：左标题 + 右链接（「全部 ›」）。
class SectionHead extends StatelessWidget {
  const SectionHead({
    super.key,
    required this.title,
    this.trailing,
    this.onTapTrailing,
    this.fontSize,
  });

  final String title;
  final String? trailing;
  final VoidCallback? onTapTrailing;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final tone = Tone.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: Type.h3.copyWith(
                fontSize: fontSize ?? 16,
                fontWeight: FontWeight.w700,
                color: tone.ink900,
              ),
            ),
          ),
          if (trailing != null)
            GestureDetector(
              onTap: onTapTrailing,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Text(
                  trailing!,
                  style: Type.sm.copyWith(
                    color: onTapTrailing == null ? tone.ink400 : tone.primary,
                    fontWeight: onTapTrailing == null ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 空 / 错误状态：一句人话 + 一行提示（图标可选）。
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.title, this.hint, this.icon});

  final String title;
  final String? hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tone = Tone.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 18, color: tone.ink300),
          const SizedBox(width: Sp.s2),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Type.body.copyWith(color: tone.ink700)),
              if (hint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(hint!, style: Type.xs.copyWith(color: tone.ink400)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 页面页头：左边「大标题 + 一行副标题」，右边周次胶囊。
///
/// 首页不用它（首页的页头是「日期 + 问候语」，见 `home_page.dart`）。
class PageHead extends StatelessWidget {
  const PageHead({
    super.key,
    required this.title,
    this.subtitle,
    this.weekText,
    this.weekStrong = true,
    this.weekKey,
  });

  final String title;
  final String? subtitle;
  final String? weekText;
  final bool weekStrong;
  final Key? weekKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s1, Sp.gutter, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: context.h1),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(subtitle!, style: context.sm),
                  ),
              ],
            ),
          ),
          if (weekText != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: WeekChip(
                key: weekKey,
                text: weekText!,
                strong: weekStrong,
              ),
            ),
        ],
      ),
    );
  }
}

/// 主卡入场：淡入 + 从下往上 10px，500ms（原型里的 `riseIn`）。
///
/// **故意只跑一次**。原型里的「进行中」脉冲点是无限循环的，那种动画会让
/// `pumpAndSettle()` 永远等不到静止、测试直接超时，所以这里不做循环动效。
class RiseIn extends StatefulWidget {
  const RiseIn({super.key, required this.child});

  final Widget child;

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..forward();

  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: const CurveCubic());

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (context, child) => Opacity(
          opacity: _a.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - _a.value)),
            child: child,
          ),
        ),
        child: widget.child,
      );
}

/// 快捷操作的一排按钮（功能页）。
class QuickButton extends StatelessWidget {
  const QuickButton({super.key, required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = Tone.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          decoration: BoxDecoration(
            color: tone.surface,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: tone.ink200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 15, color: tone.ink500),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sm.copyWith(
                    color: tone.ink700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
