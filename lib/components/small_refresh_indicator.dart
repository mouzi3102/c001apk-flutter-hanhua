import 'package:flutter/material.dart';

import 'app_loading_indicator.dart';

/// 下拉刷新：手势与触发逻辑仍由系统 [RefreshIndicator.noSpinner] 负责，
/// 指示器换成全站统一的 [AppLoadingIndicator]（纯圆弧、无白底无阴影），
/// 与页面加载时的圆环保持一致，只是尺寸更小。
///
/// 指示器出现时会把列表整体下移一个窄条的高度（[AnimatedPadding]），
/// 让圆环独占顶部空档，避免直接压在文字/卡片上。
class SmallRefreshIndicator extends StatefulWidget {
  const SmallRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.indicatorKey,
    this.notificationPredicate,
    this.size = 22,
    this.topPadding = 6.0,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// 外部可用 `RefreshIndicatorState.show()` 主动触发刷新
  final GlobalKey<RefreshIndicatorState>? indicatorKey;

  /// 透传给底层 RefreshIndicator 的滚动通知过滤（如只在顶层列表生效）
  final ScrollNotificationPredicate? notificationPredicate;

  /// 指示器直径
  final double size;
  final double topPadding;

  @override
  State<SmallRefreshIndicator> createState() => _SmallRefreshIndicatorState();
}

class _SmallRefreshIndicatorState extends State<SmallRefreshIndicator> {
  RefreshIndicatorStatus? _status;

  bool get _visible {
    switch (_status) {
      case RefreshIndicatorStatus.drag:
      case RefreshIndicatorStatus.armed:
      case RefreshIndicatorStatus.snap:
      case RefreshIndicatorStatus.refresh:
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 指示器所在窄条的高度：圆环 + 上下留白
    final double band = widget.size + widget.topPadding * 2;
    return Stack(
      children: [
        RefreshIndicator.noSpinner(
          key: widget.indicatorKey,
          onRefresh: widget.onRefresh,
          notificationPredicate: widget.notificationPredicate ??
              defaultScrollNotificationPredicate,
          onStatusChange: (status) {
            if (!mounted) return;
            if (_status != status) {
              setState(() => _status = status);
            }
          },
          // 刷新期间把列表往下让出一个空档，圆环就不会浮在内容上面
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(top: _visible ? band : 0),
            child: widget.child,
          ),
        ),
        if (_visible)
          Positioned(
            top: widget.topPadding,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: AppLoadingIndicator(size: widget.size),
              ),
            ),
          ),
      ],
    );
  }
}
