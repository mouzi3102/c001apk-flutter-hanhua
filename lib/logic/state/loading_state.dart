import '../../utils/error_util.dart';

abstract class LoadingState<T> {
  const LoadingState();

  factory LoadingState.loading() = Loading;
  factory LoadingState.empty() = Empty;
  factory LoadingState.success(T response) = Success<T>;

  /// 错误文案统一收敛：底层异常（DioException / SocketException 等）
  /// 在进入状态机前就转换成用户能看懂的提示。
  factory LoadingState.error(String errMsg) = Error.withRawMsg;
}

class Loading extends LoadingState<Never> {
  const Loading();
}

class Empty extends LoadingState<Never> {
  const Empty();
}

class Success<T> extends LoadingState<T> {
  final T response;
  const Success(this.response);
}

class Error extends LoadingState<Never> {
  final String errMsg;
  const Error(this.errMsg);

  /// 供 `LoadingState.error` 使用：先做文案归一化，再构造实例
  factory Error.withRawMsg(String errMsg) => Error(friendlyError(errMsg));
}
