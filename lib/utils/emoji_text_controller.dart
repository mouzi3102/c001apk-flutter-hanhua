import 'package:flutter/material.dart';

import 'emoji_util.dart';
import 'storage_util.dart';

/// 能在输入框内把 `[墨镜滑稽]` 这类表情文字直接画成表情图的控制器。
///
/// 默认 TextField 只能显示纯文本，点表情面板后框里只剩一串方括号文字，
/// 这里通过 buildTextSpan 把命中的表情替换成 WidgetSpan，所见即所得；
/// 发送时文本仍是原样的 `[xx]`，服务端和其它端渲染不受影响。
class EmojiTextEditingController extends TextEditingController {
  EmojiTextEditingController({super.text});

  static final RegExp _pattern = RegExp(r'[\[［【]\s*([^\]］】]{1,14})\s*[\]］】]');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // 输入法组词阶段交回默认实现，避免拼音候选被拆散
    if (!GStorage.showEmoji ||
        (withComposing && value.composing.isValid && !value.composing.isCollapsed)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final String raw = text;
    if (raw.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final List<InlineSpan> children = <InlineSpan>[];
    final double emojiSize = (style?.fontSize ?? 15.0) * 1.15;
    int cursor = 0;

    for (final RegExpMatch match in _pattern.allMatches(raw)) {
      final String matched = match.group(0) ?? '';
      final String name = match.group(1) ?? '';
      final String? file =
          EmojiUtil.emojiMap[matched] ?? EmojiUtil.lookup('[$name]');
      if (file == null || !file.endsWith('.png')) {
        continue;
      }
      if (match.start > cursor) {
        children.add(TextSpan(
          text: raw.substring(cursor, match.start),
          style: style,
        ));
      }
      children.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.0),
          child: Image.asset(
            'assets/emojis/$file',
            width: emojiSize,
            height: emojiSize,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ));
      cursor = match.end;
    }

    if (cursor < raw.length) {
      children.add(TextSpan(text: raw.substring(cursor), style: style));
    }
    if (children.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return TextSpan(style: style, children: children);
  }
}
