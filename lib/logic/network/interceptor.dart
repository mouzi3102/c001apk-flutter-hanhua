import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../../constants/constants.dart';
import '../../utils/global_data.dart';
import '../../utils/storage_util.dart';
import '../../utils/token_util.dart';

class ApiInterceptor extends Interceptor {
  ApiInterceptor(this.client);

  /// 同一个 Dio 实例，用于 token 失效后原样重放请求
  final Dio client;

  String? _xAppDevice;
  String? _userAgent;
  String? _sdkInt;
  String? _versionName;
  String? _versionCode;
  String? _apiVersion;

  String get apiVersion {
    return _apiVersion ??= GStorage.apiVersion;
  }

  String get versionCode {
    return _versionCode ??= GStorage.versionCode;
  }

  String get versionName {
    return _versionName ??= GStorage.versionName;
  }

  String get sdkInt {
    return _sdkInt ??= GStorage.sdkInt;
  }

  String get xAppDevice {
    return _xAppDevice ??= GStorage.xAppDevice;
  }

  String get userAgent {
    return _userAgent ??= GStorage.userAgent;
  }

  String get token {
    return TokenUtils.getTokenV2Cached(xAppDevice);
  }

  @override
  void onRequest(options, handler) async {
    if (TokenUtils.isPreGetLoginParam) {
      options.headers.clear();
      TokenUtils.isPreGetLoginParam = false;

      options.headers['sec-ch-ua'] =
          '"Android WebView";v="117", "Not;A=Brand";v="8", "Chromium";v="117"';
      options.headers['sec-ch-ua-mobile'] = '?1';
      options.headers['sec-ch-ua-platform'] = 'Android';
      options.headers['Upgrade-Insecure-Requests'] = '1';
      options.headers['User-Agent'] = userAgent;
      options.headers['Accept'] =
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7';
      options.headers['X-Requested-With'] = Constants.APP_ID;
    } else if (TokenUtils.isGetLoginParam) {
      options.headers.clear();
      TokenUtils.isGetLoginParam = false;

      options.headers['sec-ch-ua'] =
          '"Android WebView";v="117", "Not;A=Brand";v="8", "Chromium";v="117"';
      options.headers['sec-ch-ua-mobile'] = '?1';
      options.headers['sec-ch-ua-platform'] = 'Android';
      options.headers['Upgrade-Insecure-Requests'] = '1';
      options.headers['User-Agent'] = userAgent;
      options.headers['Accept'] =
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7';
      options.headers['X-Requested-With'] = Constants.APP_ID;
      options.headers['Cookie'] = GlobalData().SESSID;
    } else if (TokenUtils.isGetCaptcha) {
      options.headers.clear();
      TokenUtils.isGetCaptcha = false;

      options.headers['User-Agent'] = userAgent;
      options.headers['sec-ch-ua'] =
          '"Android WebView";v="117", "Not;A=Brand";v="8", "Chromium";v="117"';
      options.headers['sec-ch-ua-mobile'] = '?1';
      options.headers['sec-ch-ua-platform'] = 'Android';
      options.headers['Accept'] =
          'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8';
      options.headers['X-Requested-With'] = Constants.APP_ID;
      options.headers['Sec-Fetch-Site'] = 'same-origin';
      options.headers['Sec-Fetch-Site'] = 'same-origin';
      options.headers['Sec-Fetch-Mode'] = 'no-cors';
      options.headers['Sec-Fetch-Dest'] = 'image';
      options.headers['Referer'] =
          'https://account.coolapk.com/auth/loginByCoolapk';
      options.headers['Cookie'] =
          '${GlobalData().SESSID}; forward=https://www.coolapk.com';
    } else if (TokenUtils.isOnLogin) {
      options.headers.clear();
      TokenUtils.isOnLogin = false;

      options.headers['User-Agent'] = userAgent;
      options.headers['Cookie'] =
          '${GlobalData().SESSID}; forward=https://www.coolapk.com';
      options.headers['X-Requested-With'] = Constants.REQUEST_WITH;
      options.headers['Content-Type'] = Constants.REQUEST_WITH;
    } else {
      options.headers['User-Agent'] = userAgent;
      options.headers['X-Requested-With'] = Constants.REQUEST_WITH;
      options.headers['X-Sdk-Int'] = sdkInt;
      options.headers['X-Sdk-Locale'] = Constants.LOCALE;
      options.headers['X-App-Id'] = Constants.APP_ID;
      options.headers['X-App-Token'] = token;
      options.headers['X-App-Version'] = versionName;
      options.headers['X-App-Code'] = versionCode;
      options.headers['X-Api-Version'] = apiVersion;
      options.headers['X-App-Device'] = xAppDevice;
      options.headers['X-Dark-Mode'] = '0';
      options.headers['X-App-Channel'] = Constants.CHANNEL;
      options.headers['X-App-Mode'] = Constants.MODE;
      options.headers['X-App-Supported'] = versionCode;
      options.headers['Cookie'] = GlobalData().isLogin
          ? 'uid=${GlobalData().uid}; username=${GlobalData().username}; token=${GlobalData().token}'
          : GlobalData().SESSID;
    }

    handler.next(options);
  }

  /// 登录态失效的服务端提示（HTTP 200 + message 形式）
  static final RegExp _loginExpiredPattern = RegExp(
    r'(请先登录|请登录后|登录已?失[效败]|登录状态.{0,4}失效|登录过期|重新登录|token.{0,6}失效|账号.{0,4}异常)',
    caseSensitive: false,
  );
  static int _lastExpiredNoticeAt = 0;

  /// 只对普通 API 请求做 token 重算重放；登录页、验证码、下载、图片流等特殊请求跳过
  bool _isRetryable(RequestOptions options) {
    final String path = options.uri.path;
    if (path.contains('/auth/') || path.contains('/v6/apk/download')) {
      return false;
    }
    if (path.contains('/v6/message/showImage')) return false;
    if (options.method != 'GET' && options.method != 'POST') return false;
    return options.uri.host.contains('coolapk.com');
  }

  @override
  void onResponse(response, handler) {
    _checkLoginExpired(response);
    handler.next(response);
  }

  /// 统一拦截「登录态已失效」：清掉本地登录标记，退回匿名 Cookie，
  /// 并做节流提示（1 分钟内只提示一次，避免刷列表时连环弹）。
  void _checkLoginExpired(Response<dynamic> response) {
    if (!GlobalData().isLogin) return;
    final dynamic data = response.data;
    if (data is! Map) return;
    final String message =
        (data['message'] ?? data['messageStatus'] ?? '').toString();
    if (message.isEmpty) return;
    // 「密码错误」等是登录表单场景，不属于登录态失效
    if (message.contains('密码')) return;
    if (!_loginExpiredPattern.hasMatch(message)) return;

    _markLoginExpired();
  }

  /// 清掉本地登录标记并节流提示：1 分钟内只提示一次，避免刷列表时连环弹
  void _markLoginExpired() {
    GStorage.setIsLogin(false);
    TokenUtils.invalidateToken();

    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastExpiredNoticeAt < 60 * 1000) return;
    _lastExpiredNoticeAt = now;
    SmartDialog.showToast('登录状态已失效，请重新登录');
  }

  @override
  void onError(err, handler) async {
    final RequestOptions options = err.requestOptions;
    final int? statusCode = err.response?.statusCode;
    final bool isAuthError = statusCode == 401 || statusCode == 403;
    final bool retried = options.extra['tokenRetried'] == true;

    // 带 Cookie 的请求被拒（401/403）：cookie 已失效，直接退回匿名态
    if (isAuthError && GlobalData().isLogin) {
      _markLoginExpired();
    }

    // 匿名 token 过期/被风控时重算一次 token 并原样重放，成功就直接返回
    if (isAuthError &&
        !retried &&
        _isRetryable(options) &&
        GlobalData().isLogin == false) {
      TokenUtils.invalidateToken();
      options.extra = {...options.extra, 'tokenRetried': true};
      try {
        final Response<dynamic> response = await client.fetch(options);
        return handler.resolve(response);
      } catch (_) {
        // 重放失败，走下面的统一错误提示
      }
    }

    String url = options.uri.toString();
    if (!url.contains('/v6/apk/download') &&
        !url.contains('/v6/message/showImage')) {
      SmartDialog.showToast(
        await dioError(err),
        displayType: SmartToastType.onlyRefresh,
      );
    }
    super.onError(err, handler);
  }

  static Future<String> dioError(DioException error) async {
    switch (error.type) {
      case DioExceptionType.badCertificate:
        return '证书有误！';
      case DioExceptionType.badResponse:
        final dynamic body = error.response?.data;
        if (body is Map) {
          final String msg = (body['message'] ?? '').toString();
          if (msg.isNotEmpty) return msg;
        }
        final int? statusCode = error.response?.statusCode;
        if (statusCode == 401 || statusCode == 403) {
          return '登录状态已失效，请重新登录';
        }
        return '服务器异常，请稍后重试！';
      case DioExceptionType.cancel:
        return '请求已被取消，请重新请求';
      case DioExceptionType.connectionError:
        return '连接错误，请检查网络设置';
      case DioExceptionType.connectionTimeout:
        return '网络连接超时，请检查网络设置';
      case DioExceptionType.receiveTimeout:
        return '响应超时，请稍后重试！';
      case DioExceptionType.sendTimeout:
        return '发送请求超时，请检查网络设置';
      case DioExceptionType.transformTimeout:
        return '请求转换超时，请稍后重试！';
      case DioExceptionType.unknown:
        final String res = await checkConnect();
        return '$res，网络异常！';
    }
  }

  static Future<String> checkConnect() async {
    final List<ConnectivityResult> connectivityResult =
        await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.mobile)) {
      return '正在使用移动流量';
    } else if (connectivityResult.contains(ConnectivityResult.wifi)) {
      return '正在使用wifi';
    } else if (connectivityResult.contains(ConnectivityResult.ethernet)) {
      return '正在使用局域网';
    } else if (connectivityResult.contains(ConnectivityResult.vpn)) {
      return '正在使用代理网络';
    } else if (connectivityResult.contains(ConnectivityResult.bluetooth)) {
      return '正在使用蓝牙网络';
    } else if (connectivityResult.contains(ConnectivityResult.other)) {
      return '正在使用其他网络';
    } else if (connectivityResult.contains(ConnectivityResult.none)) {
      return '未连接到任何网络';
    } else {
      return '';
    }
  }
}
