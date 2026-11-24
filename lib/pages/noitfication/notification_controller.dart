import '../../logic/model/feed/datum.dart';
import '../../logic/network/network_repo.dart';
import '../../logic/state/loading_state.dart';
import '../../pages/common/common_controller.dart';
import '../../utils/extensions.dart';

class NotificationController extends CommonController {
  NotificationController({
    required this.url,
  });

  final String url;

  @override
  List<Datum>? handleUnique(List<Datum> dataList) {
    // 按消息 id 去重（不同页可能重复下发同一条）
    final List<Datum> list = dataList.unique((d) => '${d.id ?? d.entityId}');
    // 合并分页后统一按时间倒序：避免刷新/加载更多时把几天前的回复混到顶部
    list.sort((a, b) => _timeOf(b).compareTo(_timeOf(a)));
    return list;
  }

  /// dateline 可能是秒或毫秒，统一成毫秒；没有时间就排到最后
  static int _timeOf(Datum d) {
    final dynamic v = d.dateline;
    int? n;
    if (v is int) {
      n = v;
    } else if (v is num) {
      n = v.toInt();
    } else if (v is String) {
      n = int.tryParse(v);
    }
    if (n == null) {
      return 0;
    }
    return n > 100000000000 ? n : n * 1000;
  }

  @override
  Future<LoadingState> customGetData() {
    return NetworkRepo.getDataListFromUrl(
      url: url,
      data: {
        'page': page,
        if (firstItem != null) 'firstItem': firstItem,
        if (lastItem != null) 'lastItem': lastItem,
      },
    );
  }

  @override
  void onInit() {
    super.onInit();
    onGetData();
  }
}
