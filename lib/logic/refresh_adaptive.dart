import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/storage_util.dart';
import '../utils/utils.dart';

/// 省电自适应刷新率控制器。
///
/// 在 MaterialApp.builder 最外层以 [Listener] 全局监听指针按下事件：
/// - 读 hive settings 契约键：
///   - `refresh_adaptive`（bool，默认 true）——省电自适应总开关
///   - `refresh_rate_fps`（int，0=自动，>0=所选档位）——既有键
/// - 交互发生时：若 adaptive 开启 → 恢复所选档位
///   `Utils.platform.invokeMethod('setFrameRate', {'fps': selected})`（selected=0 即发 0=自动）；
/// - 无交互 2 秒（每次交互重置 Timer）→ 降档发 `{'fps': 60}` 省电。
///
/// 与设置页 144Hz 子代理的写入侧使用同一 MethodChannel
/// （`samples.flutter.dev/channel`）与同一方法名 `setFrameRate`。
class RefreshAdaptive extends StatefulWidget {
  const RefreshAdaptive({super.key, required this.child});

  final Widget child;

  @override
  State<RefreshAdaptive> createState() => _RefreshAdaptiveState();
}

class _RefreshAdaptiveState extends State<RefreshAdaptive> {
  Timer? _idleTimer;

  bool get _adaptive =>
      GStorage.settings.get('refresh_adaptive', defaultValue: true) == true;

  int get _selectedFps =>
      (GStorage.settings.get('refresh_rate_fps', defaultValue: 0) as num)
          .toInt();

  void _onPointerDown(PointerDownEvent event) {
    if (!_adaptive) return;
    // 交互时恢复所选档位（0 = 自动）
    Utils.platform.invokeMethod('setFrameRate', {'fps': _selectedFps});

    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 2), () {
      // 无交互 2 秒 → 降档到 60 省电
      Utils.platform.invokeMethod('setFrameRate', {'fps': 60});
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      child: widget.child,
    );
  }
}
