import 'package:flutter/material.dart';

/// 下拉刷新：手势与触发逻辑仍由系统 [RefreshIndicator.noSpinner] 负责，
/// 只是把原生的大圆圈（`RefreshProgressIndicator`，固定 41dp）整体缩放，
/// 外观（白色圆底 + 投影 + 圆弧）与系统完全一致，直径缩到约 25dp。
class SmallRefreshIndicator extends StatefulWidget {
  const SmallRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.indicatorKey,
    this.notificationPredicate,
    this.scale = 0.62,
    this.topPadding = 6.0,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// 外部可用 `RefreshIndicatorState.show()` 主动触发刷新
  final GlobalKey<RefreshIndicatorState>? indicatorKey;

  /// 透传给底层 RefreshIndicator 的滚动通知过滤（如只在顶层列表生效）
  final ScrollNotificationPredicate? notificationPredicate;

  /// 相对原生 41dp 指示器的缩放比例
  final double scale;
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
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
          child: widget.child,
        ),
        if (_visible)
          Positioned(
            top: widget.topPadding,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                // 直接复用系统原生指示器，只做整体缩放：视觉与原生一致，尺寸变小
                child: Transform.scale(
                  scale: widget.scale,
                  child: RefreshProgressIndicator(
                    elevation: 3,
                    color: scheme.primary,
                    backgroundColor: Theme.of(context).canvasColor,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
