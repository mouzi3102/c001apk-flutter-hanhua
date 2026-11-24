import 'package:flutter/material.dart';

import 'emoji_util.dart';
import 'storage_util.dart';

/// 表情单字符编码：内部用 1 个私有区字符代表 1 个表情。
///
/// 之前的实现把 `[墨镜滑稽]` 原样写进 text，再用 WidgetSpan 画成图片：
/// text 里占 6 个字符、渲染上只占 1 个"格子"，长度不守恒。
/// 结果是光标位置、删除范围全部按 6 个字符算，插入表情后再打字就会
/// 插到方括号中间、或把表情拆成文字，退格也删不干净。
/// 现在 text 里只保留 1 个占位字符（U+E000..U+F8FF），长度与渲染 1:1，
/// 发送时再解码回 `[名字]`，服务端看到的仍是原样文本。
class EmojiCodec {
  static const int _base = 0xE000;
  static const int _max = 0xF8FF;

  static final Map<String, int> _byToken = <String, int>{};
  static final Map<int, String> _byCode = <int, String>{};
  static int _next = _base;

  static int codeFor(String token) {
    final int? exist = _byToken[token];
    if (exist != null) {
      return exist;
    }
    int code = _next;
    _next++;
    if (_next > _max) {
      _next = _base;
    }
    while (_byCode.containsKey(code)) {
      code++;
      if (code > _max) {
        code = _base;
      }
    }
    _byToken[token] = code;
    _byCode[code] = token;
    return code;
  }

  static String? tokenForCode(int code) => _byCode[code];

  static bool isPlaceholder(int codeUnit) =>
      codeUnit >= _base && codeUnit <= _max;

  /// 把内部占位字符解码回 `[名字]`，用于发送
  static String decode(String text) {
    if (text.isEmpty) {
      return text;
    }
    final StringBuffer sb = StringBuffer();
    int i = 0;
    while (i < text.length) {
      final int c = text.codeUnitAt(i);
      final String? token = isPlaceholder(c) ? _byCode[c] : null;
      if (token != null) {
        sb.write(token);
      } else {
        sb.writeCharCode(c);
      }
      i += 1;
    }
    return sb.toString();
  }
}

/// 能在输入框内把表情画成图片的控制器（text 与渲染宽度严格 1:1）。
class EmojiTextEditingController extends TextEditingController {
  EmojiTextEditingController({super.text});

  /// 插入一个表情；token 形如 `[墨镜滑稽]`
  void insertEmoji(String token) {
    final String key = token.trim();
    final String? file = EmojiUtil.lookup(key);
    // 关闭表情图片显示时，直接写可读文字，保持 text 长度与渲染一致
    if (!GStorage.showEmoji) {
      _insertText(key);
      return;
    }
    if (file == null || !file.endsWith('.png')) {
      // 没有对应图片（如 [图片]/[置顶]），按普通文字插入
      _insertText(key);
      return;
    }
    _insertText(String.fromCharCode(EmojiCodec.codeFor(key)));
  }

  /// 发送用文本：占位字符 -> `[名字]`
  String get outboundText => EmojiCodec.decode(text);

  void _insertText(String insert) {
    final TextEditingValue old = value;
    int start = old.selection.start;
    int end = old.selection.end;
    if (start < 0 || start > old.text.length) {
      start = old.text.length;
    }
    if (end < start || end > old.text.length) {
      end = start;
    }
    final String newText = old.text.replaceRange(start, end, insert);
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insert.length),
      composing: TextRange.empty,
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final String raw = text;
    if (raw.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    // 关闭表情显示时 text 里本来就没有占位字符，直接走系统默认渲染
    if (!GStorage.showEmoji) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final TextRange composing =
        (withComposing && value.composing.isValid && !value.composing.isCollapsed)
            ? value.composing
            : TextRange.empty;
    final double emojiSize = (style?.fontSize ?? 15.0) * 1.15;
    // 按物理像素解码，别把整张原图丢进纹理缓存
    final int cacheSize =
        (emojiSize * MediaQuery.of(context).devicePixelRatio).ceil();
    final List<InlineSpan> children = <InlineSpan>[];

    int plainStart = 0;
    int i = 0;
    while (i < raw.length) {
      final int c = raw.codeUnitAt(i);
      // 代理对整体算普通文字，别切一半
      if (c >= 0xD800 && c <= 0xDBFF && i + 1 < raw.length) {
        i += 2;
        continue;
      }
      final String? token =
          EmojiCodec.isPlaceholder(c) ? EmojiCodec.tokenForCode(c) : null;
      if (token == null) {
        i += 1;
        continue;
      }
      if (i > plainStart) {
        children.add(TextSpan(
          text: raw.substring(plainStart, i),
          style: _styleWithComposing(style, plainStart, i, composing),
        ));
      }
      final String? file = EmojiUtil.lookup(token);
      if (file != null && file.endsWith('.png')) {
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.0),
            child: Image.asset(
              'assets/emojis/$file',
              width: emojiSize,
              height: emojiSize,
              cacheWidth: cacheSize,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ));
      } else {
        children.add(TextSpan(text: token, style: style));
      }
      plainStart = i + 1;
      i += 1;
    }

    if (plainStart < raw.length) {
      children.add(TextSpan(
        text: raw.substring(plainStart),
        style: _styleWithComposing(style, plainStart, raw.length, composing),
      ));
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

  static TextStyle? _styleWithComposing(
    TextStyle? base,
    int start,
    int end,
    TextRange composing,
  ) {
    if (!composing.isValid || composing.isCollapsed) {
      return base;
    }
    // 输入法组词区间画下划线，而不是整框退回纯文本（旧实现会露出 [xx] 字面）
    if (composing.start < end && composing.end > start) {
      return (base ?? const TextStyle()).copyWith(
        decoration: TextDecoration.underline,
      );
    }
    return base;
  }
}
