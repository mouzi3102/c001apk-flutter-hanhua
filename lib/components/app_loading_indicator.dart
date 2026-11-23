import 'package:flutter/material.dart';

/// 全站统一的加载圈：只有一段细圆弧，没有白色圆底和投影。
///
/// 之前页面加载用系统默认 `CircularProgressIndicator`（36dp 大圆圈），
/// 下拉刷新用 `RefreshProgressIndicator` 缩放（白底 + 阴影），两处观感
/// 不一致。这里收敛成一个尺寸更小的纯圆弧指示器，两处共用。
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({
    super.key,
    this.size = 22,
    this.strokeWidth = 2.4,
  });

  /// 指示器直径
  final double size;

  /// 圆弧粗细
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: scheme.primary,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}
