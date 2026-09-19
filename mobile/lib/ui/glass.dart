/// Liquid Glass（macOS Tahoe 风格）的玻璃容器。
///
/// 半透明磨砂 + 背景模糊 + 高光描边 + 柔和投影；深浅色自适应。
/// 只管质感：child 是什么就显示什么，不改变布局结构。
library;

import 'dart:ui';

import 'package:flutter/material.dart';

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 0,
    this.blur = 22,
    this.tint,
    this.borderColor,
    this.shadow = true,
  });

  final Widget child;

  /// 圆角；0 表示不裁切圆角（整条边的面板）。
  final double radius;

  /// 背景模糊强度。
  final double blur;

  /// 玻璃的染色；给透明就用纯模糊。
  final Color? tint;

  final Color? borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint =
        this.tint ?? (dark ? const Color(0x8C22252E) : const Color(0x8CFFFFFF));
    final line = borderColor ??
        (dark ? const Color(0x24FFFFFF) : const Color(0x99FFFFFF));
    final shadowColor =
        dark ? const Color(0x66000000) : const Color(0x23283A5E);

    Widget panel = ClipRRect(
      borderRadius:
          radius > 0 ? BorderRadius.circular(radius) : BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                tint.withValues(alpha: tint.a * 0.55),
                tint,
              ],
            ),
            borderRadius:
                radius > 0 ? BorderRadius.circular(radius) : null,
            border: Border.all(color: line),
          ),
          child: child,
        ),
      ),
    );
    if (radius > 0) {
      panel = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: shadow
              ? <BoxShadow>[
                  BoxShadow(
                      color: shadowColor,
                      blurRadius: 26,
                      offset: const Offset(0, 10)),
                ]
              : null,
        ),
        child: panel,
      );
    }
    return panel;
  }
}

/// 页面底下的彩色渐变：玻璃要能「透」出颜色才成立。
/// 浅色偏晨雾蓝紫，深色偏夜色；只做背景，不影响任何内容。
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const <Color>[
                  Color(0xFF17181C),
                  Color(0xFF1B2030),
                  Color(0xFF231A22),
                ]
              : const <Color>[
                  Color(0xFFEEF1FB),
                  Color(0xFFE9F0FA),
                  Color(0xFFF6EEE9),
                ],
        ),
      ),
      child: child,
    );
  }
}
