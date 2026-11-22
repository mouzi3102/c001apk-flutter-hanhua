import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../../constants/constants.dart';
import '../../utils/cache_util.dart';
import '../../utils/extensions.dart';
import '../../utils/global_data.dart';
import '../../utils/menu_labels.dart';
import '../../utils/storage_util.dart';
import '../../utils/utils.dart';

// ignore: constant_identifier_names
enum WebviewMenuItem { Refresh, Copy, Open_In_Browser, Clear_Cache, Go_Back }

class WebviewPage extends StatefulWidget {
  const WebviewPage({super.key});

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> {
  final String _url = Get.parameters['url'] ?? '';
  final bool _isLogin = Get.parameters['isLogin'] == '1';
  final _titleStream = StreamController<String?>();
  final _progressStream = StreamController<double>();

  InAppWebViewController? _webViewController;

  /// 外部链接确认框是否正在显示：网页里多个链接/重定向会连续触发
  /// shouldOverrideUrlLoading，不加这个门闩会叠出一串提示框
  bool _externalLinkDialogShowing = false;

  @override
  void initState() {
    super.initState();
    CookieManager().deleteAllCookies();
    if (GlobalData().isLogin) {
      CookieManager().setCookie(
        url: WebUri.uri(Uri.parse('.coolapk.com')),
        name: 'DID',
        value: GStorage.szlmId,
      );
      CookieManager().setCookie(
        url: WebUri.uri(Uri.parse('.coolapk.com')),
        name: 'forward',
        value: 'https://www.coolapk.com',
      );
      CookieManager().setCookie(
        url: WebUri.uri(Uri.parse('.coolapk.com')),
        name: 'displayVersion',
        value: 'v14',
      );
      CookieManager().setCookie(
        url: WebUri.uri(Uri.parse('.coolapk.com')),
        name: 'uid',
        value: GlobalData().uid,
      );
      CookieManager().setCookie(
        url: WebUri.uri(Uri.parse('.coolapk.com')),
        name: 'username',
        value: GlobalData().username,
      );
      CookieManager().setCookie(
        url: WebUri.uri(Uri.parse('.coolapk.com')),
        name: 'token',
        value: GlobalData().token,
      );
    }
  }

  @override
  void dispose() {
    _titleStream.close();
    _progressStream.close();
    _webViewController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder(
          initialData: null,
          stream: _titleStream.stream,
          builder: (_, snapshot) => snapshot.data != null
              ? Text(
                  snapshot.data!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : const SizedBox.shrink(),
        ),
        bottom: PreferredSize(
          preferredSize: Size.zero,
          child: StreamBuilder(
            initialData: 0.0,
            stream: _progressStream.stream,
            builder: (_, snapshot) => snapshot.data as double < 1
                ? LinearProgressIndicator(
                    value: snapshot.data as double,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        actions: [
          PopupMenuButton(
            onSelected: (item) async {
              switch (item) {
                case WebviewMenuItem.Refresh:
                  _webViewController?.reload();
                  break;
                case WebviewMenuItem.Copy:
                  WebUri? uri = await _webViewController?.getUrl();
                  if (uri != null) {
                    Utils.copyText(uri.toString());
                  }
                  break;
                case WebviewMenuItem.Open_In_Browser:
                  WebUri? uri = await _webViewController?.getUrl();
                  if (uri != null) {
                    Utils.launchURL(uri.toString());
                  }
                  break;
                case WebviewMenuItem.Clear_Cache:
                  try {
                    await InAppWebViewController.clearAllCache();
                    await _webViewController?.clearHistory();
                    SmartDialog.showToast('已清理');
                  } catch (e) {
                    SmartDialog.showToast(e.toString());
                  }
                  break;
                case WebviewMenuItem.Go_Back:
                  if (await _webViewController?.canGoBack() == true) {
                    _webViewController?.goBack();
                  }
                  break;
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<WebviewMenuItem>>[
              ...WebviewMenuItem.values.sublist(0, 4).map(
                  (item) => PopupMenuItem(value: item, child: Text(MenuLabels.of(item)))),
              const PopupMenuDivider(),
              PopupMenuItem(
                  value: WebviewMenuItem.Go_Back,
                  child: Text(
                    MenuLabels.of(WebviewMenuItem.Go_Back),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  )),
            ],
          )
        ],
      ),
      body: InAppWebView(
        initialSettings: InAppWebViewSettings(
          useHybridComposition: false,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          useShouldOverrideUrlLoading: true,
          useOnDownloadStart: true,
          clearCache: true,
          userAgent: GStorage.userAgent,
          forceDark: ForceDark.AUTO,
          algorithmicDarkeningAllowed: true,
        ),
        initialUrlRequest:
            URLRequest(url: WebUri.uri(Uri.parse(_url)), headers: {
          'X-Requested-With': Constants.APP_ID,
        }),
        onWebViewCreated: (InAppWebViewController controller) {
          _webViewController = controller;
        },
        onProgressChanged: (controller, progress) {
          _progressStream.add(progress / 100);
        },
        onTitleChanged: (controller, title) {
          _titleStream.add(title);
        },
        onCloseWindow: (controller) => Get.back(),
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          var url = navigationAction.request.url!.toString();

          if (!url.startsWith('http')) {
            // 之前的 SnackBar 方案有两个坑：
            // 1) 点「打开」后 SnackBar 不主动收起，跳出 App 再回来仍挂在界面上；
            // 2) 网页连续触发多次跳转时会排队叠出好几条提示。
            // 改为模态对话框：点任意按钮立即 pop，且加门闩只允许一个实例。
            if (!_externalLinkDialogShowing) {
              _externalLinkDialogShowing = true;
              final bool? confirmed = await showDialog<bool>(
                context: context,
                barrierDismissible: true,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('打开外部链接'),
                  content: const Text('当前网页将要打开外部链接，是否打开'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('打开'),
                    ),
                  ],
                ),
              );
              _externalLinkDialogShowing = false;
              if (confirmed == true && mounted) {
                Utils.launchURL(url);
              }
            }
            return NavigationActionPolicy.CANCEL;
          }

          if (_isLogin && url == Constants.URL_COOLAPK) {
            String uid = (await CookieManager().getCookie(
              url: WebUri.uri(Uri.parse(Constants.URL_COOLAPK)),
              name: 'uid',
            ))
                ?.value;
            String username = (await CookieManager().getCookie(
              url: WebUri.uri(Uri.parse(Constants.URL_COOLAPK)),
              name: 'username',
            ))
                ?.value;
            String token = (await CookieManager().getCookie(
              url: WebUri.uri(Uri.parse(Constants.URL_COOLAPK)),
              name: 'token',
            ))
                ?.value;
            if (!uid.isNullOrEmpty &&
                !username.isNullOrEmpty &&
                !token.isNullOrEmpty) {
              GStorage.setUid(uid);
              GStorage.setUsername(username);
              GStorage.setToken(token);
              GStorage.setIsLogin(true);
              Get.back(result: true);
            } else {
              Get.back(result: false);
            }
            return NavigationActionPolicy.CANCEL;
          }

          return NavigationActionPolicy.ALLOW;
        },
        onDownloadStartRequest: (controller, request) {
          showDialog(
              context: context,
              builder: (context) {
                String suggestedFilename = request.suggestedFilename.toString();
                String fileSize =
                    CacheManage.formatSize(request.contentLength.toDouble());
                try {
                  suggestedFilename = Uri.decodeComponent(suggestedFilename);
                } catch (e) {
                  debugPrint(e.toString());
                }
                return AlertDialog(
                  title: Text(
                    '下载文件：$suggestedFilename ?',
                    style: const TextStyle(fontSize: 18),
                  ),
                  content: SelectableText(request.url.toString()),
                  actions: [
                    TextButton(
                        onPressed: () => Get.back(),
                        child: const Text('关闭')),
                    TextButton(
                        onPressed: () async {
                          Get.back();
                          Utils.onDownloadFile(
                            request.url.toString(),
                            suggestedFilename,
                          );
                        },
                        child: Text('确定（$fileSize）')),
                  ],
                );
              });
          _progressStream.add(1);
        },
      ),
    );
  }
}
