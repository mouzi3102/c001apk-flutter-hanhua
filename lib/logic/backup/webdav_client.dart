import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// WebDAV 备份异常——全部携带对用户友好的中文文案，UI 层直接 Toast。
class WebDavException implements Exception {
  WebDavException(this.message);

  /// 用户可见的中文错误描述
  final String message;

  @override
  String toString() => message;
}

/// 手写标准 WebDAV PUT/GET + Basic Auth 客户端（纯 Dart，不依赖 Flutter UI）。
///
/// 独立 Dio 实例（不复用 Request.dio）：避免 ApiInterceptor 强塞酷安
/// X-App-* 头与 SESSID Cookie 污染 WebDAV 请求。
///
/// 上传/下载路径固定：{baseUrl}/c001apk_backup_v10.json
/// - PUT（备份）：上传 JSON 字节；GET（恢复）：下载 JSON 字节。
/// https 自签证书：[allowBadCertificate] 为 true 时忽略校验；
/// false 时证书异常抛出含「证书异常」文案。
class WebDavClient {
  WebDavClient({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.allowBadCertificate = false,
    // 坚果云等公网 WebDAV 响应偏慢：连接 15s，收发 60s
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 60),
    this.sendTimeout = const Duration(seconds: 60),
  });

  /// 服务器地址，含目录路径（尾部斜杠兼容）
  final String baseUrl;
  final String username;
  final String password;
  final bool allowBadCertificate;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;

  static const String backupFileName = 'c001apk_backup_v10.json';

  /// 根目录下自动创建的备份子目录名（PUT 遇 404 时兜底创建）
  static const String autoDirName = 'c001apk_backups';

  String get _base =>
      baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';

  Uri get _backupUri => Uri.parse('$_base$backupFileName');

  /// 自动建目录后的上传地址
  Uri get _autoDirUri => Uri.parse('$_base$autoDirName/');

  Uri get _autoBackupUri => Uri.parse('$_base$autoDirName/$backupFileName');

  String get _basicAuthHeader =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  Dio _newDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      headers: {HttpHeaders.authorizationHeader: _basicAuthHeader},
      // 手动处理所有状态码，避免 dio 抛异常时丢失状态信息
      validateStatus: (_) => true,
    ));
    if (allowBadCertificate) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        },
      );
    }
    return dio;
  }

  /// 备份：PUT 上传 [bytes]。先直写目标文件；遇 404（父目录不允许建文件）→
  /// 自动 MKCOL 子目录 {base}/c001apk_backups/ 后重试。
  /// 返回提示文案（自动建目录成功时附带说明，供 UI Toast）。
  Future<String> putBackup(List<int> bytes) async {
    final dio = _newDio();
    try {
      // 不声明泛型：错误响应（4xx XML 错误体）不是 List<int>，
      // 带泛型会在赋值时类型转换崩溃——这正是用户实机「请求错误」根因
      var resp = await dio.putUri(
        _backupUri,
        data: bytes,
        options: Options(
          responseType: ResponseType.plain,
          contentType: ContentType.json.toString(),
          headers: {Headers.contentLengthHeader: bytes.length},
        ),
      );
      var code = resp.statusCode ?? 0;
      // 404 或 409 均视为「父目录不允许/不存在」→ 自动建子目录后重试
      if (code == 404 || code == 409) {
        // 根目录不允许直接建文件 → 自动建子目录后重试一次
        final created = await _mkcolBackupDir(dio);
        if (!created) {
          throw WebDavException(
              '目录不存在（404）：服务器不允许自动创建目录，请手动指到一个已存在的目录');
        }
        resp = await dio.putUri(
          _autoBackupUri,
          data: bytes,
          options: Options(
            responseType: ResponseType.plain,
            contentType: ContentType.json.toString(),
            headers: {Headers.contentLengthHeader: bytes.length},
          ),
        );
        code = resp.statusCode ?? 0;
        _checkStatus(resp, action: '备份');
        return '已自动创建目录 $autoDirName 并上传';
      }
      _checkStatus(resp, action: '备份');
      return '';
    } on DioException catch (e) {
      throw _toChinese(e);
    }
  }

  /// MKCOL 自动备份子目录。2xx（含目录已存在的 405/409/412）视为成功；
  /// 403 等明确拒绝返回 false。
  Future<bool> _mkcolBackupDir(Dio dio) async {
    try {
      final resp = await dio.requestUri<Object>(
        _autoDirUri,
        data: '',
        options: Options(method: 'MKCOL', responseType: ResponseType.plain),
      );
      final code = resp.statusCode ?? 0;
      // 409 = 目录已存在/冲突，幂等重试上传即可，不视为错误
      return (code >= 200 && code < 300) ||
          code == 405 ||
          code == 409 ||
          code == 412;
    } on DioException {
      return false;
    }
  }

  /// 恢复：GET 下载备份 JSON 字节。先查目标文件；404 再查自动目录。
  Future<List<int>> getBackup() async {
    final dio = _newDio();
    try {
      var resp = await dio.getUri<List<int>>(
        _backupUri,
        options: Options(responseType: ResponseType.bytes),
      );
      if (resp.statusCode == 404) {
        // 可能在自动创建的子目录里
        resp = await dio.getUri<List<int>>(
          _autoBackupUri,
          options: Options(responseType: ResponseType.bytes),
        );
      }
      _checkStatus(resp, action: '恢复');
      return List<int>.from(resp.data ?? const []);
    } on DioException catch (e) {
      throw _toChinese(e);
    }
  }

  WebDavException _toChinese(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return WebDavException('连接超时，请检查服务器或网络');
      case DioExceptionType.connectionError:
        return WebDavException('连接服务器失败，请检查网络与地址');
      case DioExceptionType.badCertificate:
        return WebDavException(
            '证书异常：当前服务器证书未通过校验，可在设置中勾选「忽略证书校验」');
      default:
        return WebDavException('请求失败：${e.message ?? '未知错误'}');
    }
  }

  void _checkStatus(Response resp, {required String action}) {
    final code = resp.statusCode ?? 0;
    // 2xx 成功范围（PUT 新建资源为 201，覆盖 200/201/204）
    if (code >= 200 && code < 300) return;
    // 响应正文摘要：真机排障时用户反馈信息足够定位
    String body = '';
    final d = resp.data;
    if (d is List<int>) {
      body = utf8.decode(d, allowMalformed: true);
    } else if (d != null) {
      body = d.toString();
    }
    var snippet = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (snippet.length > 120) snippet = '${snippet.substring(0, 120)}…';
    final tail = snippet.isEmpty ? '' : '，响应：$snippet';
    switch (code) {
      case 401:
      case 403:
        throw WebDavException('认证失败：用户名或密码错误（$code）$tail');
      case 404:
        if (action == '备份') {
          // 写入失败的 404 = 父目录不允许建文件（如坚果云根目录），
          // 自动建目录兜底见 putBackup；此处仅当 MKCOL 被拒后到达
          throw WebDavException(
              '目录不存在（404）：服务器不允许自动创建目录，请手动指到一个已存在的目录$tail');
        }
        throw WebDavException('备份不存在，请先备份$tail');
      default:
        throw WebDavException('$action失败：服务器返回状态码 $code$tail');
    }
  }
}
