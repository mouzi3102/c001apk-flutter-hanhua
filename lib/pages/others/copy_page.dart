import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../../utils/emoji_util.dart';
import '../../utils/extensions.dart';
import '../../utils/storage_util.dart';
import '../../utils/utils.dart';

extension StringExtensions on String {
  String get getAllLinkAndText {
    if (isEmpty) return '';
    final regExp =
        RegExp(r'<a class="feed-link-url"\s+href="([^<>\"]*)"[^<]*[^>]*>');
    return replaceAllMapped(regExp, (match) => ' ${match.group(1)} ');
  }
}

/// 长按帖子 / 评论后的文本查看页。
///
/// 之前的实现直接把原文塞进 SelectableText：`[墨镜滑稽]` 这类表情 token
/// 会原样显示成文字，而且文本整块垂直居中、字号 22，长文时排版很别扭。
/// 现在：表情 token 画成表情图（整段仍可选中复制），文字左对齐、限宽、
/// 可滚动，顶部提供关闭 / 复制按钮。
class CopyPage extends StatelessWidget {
  const CopyPage({super.key});

  static final RegExp _emojiToken = RegExp(r'\[[^\[\]]{1,16}\]');

  @override
  Widget build(BuildContext context) {
    final String rawParam = Get.parameters['text'].orEmpty;
    final String plain =
        Utils.parseHtmlString(rawParam.getAllLinkAndText).trim();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const double emojiSize = 20;

    return Container(
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Get.back(),
                  ),
                  Expanded(
                    child: Text(
                      '查看文本',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制',
                    icon: const Icon(Icons.copy_all_outlined),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: plain));
                      SmartDialog.showToast('已复制');
                    },
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              // 短文本垂直居中（单手更好点按/阅读），长文本自然从顶部开始滚动
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const double padTop = 16;
                  const double padBottom = 32;
                  final double minHeight =
                      (constraints.maxHeight - padTop - padBottom) > 0
                          ? constraints.maxHeight - padTop - padBottom
                          : 0;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, padTop, 20, padBottom),
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minHeight),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: SelectionArea(
                            child: Text.rich(
                              TextSpan(
                                children:
                                    _buildSpans(context, plain, TextStyle(
                                  fontSize: 18,
                                  height: 1.6,
                                  color: scheme.onSurface,
                                ), emojiSize),
                                style: TextStyle(
                                  fontSize: 18,
                                  height: 1.6,
                                  color: scheme.onSurface,
                                ),
                              ),
                              textAlign: TextAlign.start,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<InlineSpan> _buildSpans(
    BuildContext context,
    String text,
    TextStyle style,
    double emojiSize,
  ) {
    if (text.isEmpty) {
      return <InlineSpan>[TextSpan(text: text, style: style)];
    }
    final bool showEmoji = GStorage.showEmoji;
    final double dpr = MediaQuery.of(context).devicePixelRatio;
    final int cacheSize = (emojiSize * dpr).ceil();
    final List<InlineSpan> spans = <InlineSpan>[];
    int last = 0;
    for (final Match m in _emojiToken.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: style));
      }
      final String token = m.group(0)!;
      final String? file = showEmoji ? EmojiUtil.lookup(token) : null;
      if (file != null && file.endsWith('.png')) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Image.asset(
            'assets/emojis/$file',
            width: emojiSize,
            height: emojiSize,
            cacheWidth: cacheSize,
            filterQuality: FilterQuality.medium,
          ),
        ));
      } else {
        spans.add(TextSpan(text: token, style: style));
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: style));
    }
    return spans;
  }
}
