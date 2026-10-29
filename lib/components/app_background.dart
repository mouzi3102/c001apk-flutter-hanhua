import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// 全局静态背景组件（AppBackground）：仅主题渐变基座。
///
/// - 位于 MaterialApp.builder 底层 Stack（Navigator 之下），透明 Scaffold
///   下任意路由可见；
/// - 整体包 `RepaintBoundary`——渐变合成结果缓存为单层位图，路由 push/pop
///   动画期间引擎直接复用纹理合成、不再逐帧重绘背景（防中端机 GPU 合成慢
///   导致的闪烁/卡顿）；
/// - `IgnorePointer` 不拦截任何交互。
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return RepaintBoundary(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: brightness == Brightness.dark
                ? AppTheme.darkBackgroundGradient
                : AppTheme.lightBackgroundGradient,
          ),
        ),
      ),
    );
  }
}
