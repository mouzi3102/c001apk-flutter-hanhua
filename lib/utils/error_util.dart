/// 把底层异常文本转换成用户能看懂的提示语。
///
/// 典型场景：断网时 Dio 抛出
/// `DioException [connection error]: ... Failed host lookup:
/// 'api2.coolapk.com' ... SocketException: ... errno = 7`
/// 直接展示给用户既难读也没法操作，这里统一收敛成一句提示，
/// 具体重试动作交给列表页的「下拉刷新」。
String friendlyError(Object? raw) {
  final String text = (raw ?? '').toString();
  if (text.isEmpty) {
    return '加载失败，请下拉刷新重试';
  }

  final String lower = text.toLowerCase();
  if (lower.contains('failed host lookup') ||
      lower.contains('no address associated with hostname') ||
      lower.contains('errno = 7') ||
      lower.contains('socketexception') ||
      lower.contains('connection error') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('failed to connect')) {
    return '网络未连接，请检查网络后下拉刷新';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return '网络连接超时，请下拉刷新重试';
  }
  if (lower.contains('certificate') || lower.contains('handshake')) {
    return '安全连接建立失败，请下拉刷新重试';
  }
  if (lower.contains('dioexception') || lower.contains('socket')) {
    return '网络请求失败，请下拉刷新重试';
  }
  return text;
}
