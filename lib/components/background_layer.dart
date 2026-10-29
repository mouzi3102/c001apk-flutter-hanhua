import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/storage_util.dart';

/// 自定义背景层。
///
/// 读取 hive settings 箱内契约键（与设置页子代理写入侧保持一模一样的字面量）：
/// - `custom_bg_enabled`（bool，默认 false）
/// - `custom_bg_path`（String，默认 ''）
/// - `custom_bg_blur`（double，默认 0）
///
/// enabled 且 path 非空时渲染 `Positioned.fill` + `Image.file(fit: cover)`，
/// 天然铺满任意分辨率/横竖屏；blur>0 时外层包 `BackdropFilter`。
/// 不拦截任何指针事件（IgnorePointer），仅作最底层衬底。
class BackgroundLayer extends StatelessWidget {
  const BackgroundLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final bool enabled =
        GStorage.settings.get('custom_bg_enabled', defaultValue: false) == true;
    final String path =
        GStorage.settings.get('custom_bg_path', defaultValue: '') as String;
    final double blur =
        (GStorage.settings.get('custom_bg_blur', defaultValue: 0) as num)
            .toDouble();

    if (!enabled || path.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget image = Positioned.fill(
      child: Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      ),
    );

    if (blur > 0) {
      image = Positioned.fill(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          // BackdropFilter 自身需要一个不透明/可见 child 才能裁切区域；
          // 这里把同一张图再次叠上，保证模糊作用于背景图本身。
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        ),
      );
    }

    return IgnorePointer(child: image);
  }
}
