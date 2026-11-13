import 'package:flutter/material.dart';

/// 下拉刷新组件：行为完全交给系统 [RefreshIndicator.noSpinner]，
/// 只是把「转圈」换成自己能控制尺寸的小圆环（默认直径 20），
/// 解决首页刷新指示器太大、视觉突兀的问题。
class SmallRefreshIndicator extends StatefulWidget {
  const SmallRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.indicatorKey,
    this.size = 20.0,
    this.strokeWidth = 2.2,
    this.color,
    this.topPadding = 10.0,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// 外部可用 `RefreshIndicatorState.show()` 主动触发刷新
  final GlobalKey<RefreshIndicatorState>? indicatorKey;

  final double size;
  final double strokeWidth;
  final Color? color;
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

  bool get _running => _status == RefreshIndicatorStatus.refresh;

  @override
  Widget build(BuildContext context) {
    final Color color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Stack(
      children: [
        RefreshIndicator.noSpinner(
          key: widget.indicatorKey,
          onRefresh: widget.onRefresh,
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
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: _visible ? 1.0 : 0.0,
                  child: Container(
                    width: widget.size + 8,
                    height: widget.size + 8,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          Theme.of(context).cardColor.withValues(alpha: 0.92),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: widget.size,
                      height: widget.size,
                      child: _running
                          ? CircularProgressIndicator(
                              strokeWidth: widget.strokeWidth,
                              color: color,
                            )
                          : Transform.rotate(
                              angle: 0,
                              child: CircularProgressIndicator(
                                // 拖动阶段用「转圈 + 半透明」提示可继续下拉
                                value: null,
                                strokeWidth: widget.strokeWidth,
                                color: color.withValues(alpha: 0.75),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
