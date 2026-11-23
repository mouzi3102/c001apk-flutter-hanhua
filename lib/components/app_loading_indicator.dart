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

/// 整页加载占位：把 [AppLoadingIndicator] 贴在内容顶部（而不是屏幕正中），
/// 数据回来后内容从顶部开始渲染，视觉上不会出现"圆环从中间跳到顶部"。
class PageLoadingIndicator extends StatelessWidget {
  const PageLoadingIndicator({
    super.key,
    this.topPadding = 20,
    this.size = 22,
  });

  final double topPadding;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Align(
        alignment: Alignment.topCenter,
        child: AppLoadingIndicator(size: size),
      ),
    );
  }
}
