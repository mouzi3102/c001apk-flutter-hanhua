import 'package:c001apk_flutter/components/network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:get/get.dart';

import '../utils/emoji_util.dart';
import '../utils/extensions.dart';
import '../utils/imageview_route.dart';
import '../utils/storage_util.dart';
import '../utils/utils.dart';

Widget htmlText(
  String html, {
  double fontSize = 15,
  bool isBold = false,
  List<String>? picArr,
  Function? onClick,
  Function? onShowTotalReply,
  Function? onViewFan,
}) {
  String? htmlConvert;
  if (GStorage.showEmoji) {
    // 宽松匹配：兼容全角括号、括号内多余空格，避免服务端/输入法带来的变体
    // 匹配不上而退化成「[墨镜滑稽]」这样的纯文字。
    final RegExp regExp = RegExp(r'[\[［【]\s*([^\]］】]{1,14})\s*[\]］】]');
    htmlConvert = html.replaceAll('\n', '<br/>').replaceAllMapped(
      regExp,
      (match) {
        final String matchedString = match.group(0) ?? '';
        final String name = match.group(1) ?? '';
        final String? src =
            EmojiUtil.emojiMap[matchedString] ?? EmojiUtil.lookup('[$name]');
        if (!src.isNullOrEmpty) {
          return '<img src="$src">';
        } else {
          return matchedString;
        }
      },
    );
  }

  return HtmlWidget(
    htmlConvert ?? html,
    onTapUrl: (url) {
      if (url.isEmpty) {
        if (onClick != null) {
          onClick();
        }
      } else if (url.contains('/feed/replyList')) {
        if (onShowTotalReply != null) {
          onShowTotalReply();
        }
      } else if (url.contains('image.coolapk.com')) {
        openImageViewWithGet(
          imgList: !picArr.isNullOrEmpty ? picArr! : [url],
        );
      } else if (url == '/contacts/fans') {
        if (onViewFan != null) {
          onViewFan();
        }
      } else {
        Utils.onOpenLink(url, null);
      }
      return true;
    },
    textStyle: TextStyle(
      fontSize: fontSize,
      height: 1.5,
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
    ),
    customStylesBuilder: (element) {
      switch (element.localName) {
        case 'a':
          return {'text-decoration': 'none'};
      }
      return null;
    },
    customWidgetBuilder: (element) {
      switch (element.localName) {
        case 'img':
          {
            double size =
                MediaQuery.of(Get.context!).textScaler.scale(fontSize);
            String src = element.attributes['src'] ?? '';
            // 本地表情优先按「文件名是否在表情表里」判定，而不是 endsWith('png')：
            // HTML 解析器可能给 src 拼上路径/查询参数/百分号编码，导致判定落空、
            // 表情退化成文字或被当成网络图片（表现为只看到 [墨镜滑稽] 这类字符）。
            if (EmojiUtil.isEmojiFile(src)) {
              final String file = EmojiUtil.emojiFile(src);
              final String? name = EmojiUtil.fileToKey[file];
              return InlineCustomWidget(
                alignment: PlaceholderAlignment.middle,
                child: Image.asset(
                  'assets/emojis/$file',
                  width: size * 1.3,
                  height: size * 1.3,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => Text(
                    name ?? '',
                    style: TextStyle(fontSize: fontSize),
                  ),
                ),
              );
            }
            return InlineCustomWidget(
              alignment: PlaceholderAlignment.middle,
              child: src.endsWith('icon')
                  ? Icon(
                      size: size * 1.3,
                      Icons.photo_outlined,
                      color: Theme.of(Get.context!).colorScheme.primary,
                    )
                  : src.endsWith('png')
                      ? Image.asset(
                          'assets/emojis/$src',
                          width: size * 1.3,
                          height: size * 1.3,
                        )
                      : src.startsWith('http')
                          ? networkImage(
                              src,
                              width: size * 1.3,
                              height: size * 1.3,
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(Get.context!)
                                      .colorScheme
                                      .primary,
                                ),
                                borderRadius:
                                    const BorderRadius.all(Radius.circular(4)),
                              ),
                              child: Text(
                                src,
                                style: TextStyle(
                                  height: 1,
                                  fontWeight: FontWeight.bold,
                                  fontSize: fontSize - 4,
                                  color: Theme.of(Get.context!)
                                      .colorScheme
                                      .primary,
                                ),
                                strutStyle: StrutStyle(
                                  height: 1,
                                  leading: 0,
                                  fontWeight: FontWeight.bold,
                                  fontSize: fontSize - 4,
                                ),
                              ),
                            ),
            );
          }
      }
      return null;
    },
  );
}
