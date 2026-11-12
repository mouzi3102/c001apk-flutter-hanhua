import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../logic/model/fav_history/fav_history.dart';
import '../../logic/model/feed/datum.dart';
import '../../logic/model/feed/user_info.dart';
import '../../pages/history/history_page.dart' show HistoryType;
import '../../utils/storage_util.dart';

class HistoryController extends GetxController {
  HistoryController({required this.type});
  final HistoryType type;

  late final Box favFeed = GStorage.favFeed;
  late final Box historyFeed = GStorage.historyFeed;

  RxList<Datum> dataList = <Datum>[].obs;

  /// 是否处于搜索状态（AppBar 换成输入框、正文换成搜索面板）
  RxBool searching = false.obs;

  /// 当前关键词（输入即过滤，无需点搜索）
  RxString query = ''.obs;

  /// 本页搜索记录（收藏页 / 浏览历史页各存一份）
  RxList<String> records = <String>[].obs;

  /// 单页记录条数上限
  static const int maxRecords = 20;

  /// 记录所在的 hive key（同一个 searchHistory box，随全量备份走 WebDAV）
  String get recordsKey =>
      type == HistoryType.Favorite ? 'favSearchHistory' : 'historySearchHistory';

  /// 当前展示的列表：有关键词时按关键词过滤，否则原样
  List<Datum> get visibleList {
    final keyword = query.value.trim().toLowerCase();
    if (keyword.isEmpty) return dataList;
    return dataList.where((data) {
      final fields = <String?>[
        data.message,
        data.deviceTitle,
        data.userInfo?.username,
        data.id?.toString(),
        data.uid?.toString(),
      ];
      for (final field in fields) {
        if (field != null && field.toLowerCase().contains(keyword)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  Future<void> _getData() async {
    List<dynamic> list = type == HistoryType.Favorite
        ? favFeed.values.toList()
        : historyFeed.values.toList();
    if (list.isNotEmpty) {
      list.sort((a, b) =>
          (a as FavHistoryItem).time!.compareTo((b as FavHistoryItem).time!));
      list = list.reversed.toList();
    }
    dataList.value = list.isNotEmpty
        ? list
            .map((item) => Datum(
                  id: (item as FavHistoryItem).id,
                  uid: item.uid,
                  userInfo: UserInfo(username: (item).username),
                  userAvatar: item.userAvatar,
                  message: item.message,
                  deviceTitle: item.device,
                  dateline: item.dateline,
                ))
            .toList()
        : <Datum>[];
  }

  void _loadRecords() {
    final raw =
        GStorage.searchHistory.get(recordsKey, defaultValue: const <String>[]);
    records.value = raw is List
        ? raw
            .map((e) => '$e'.trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];
  }

  @override
  void onInit() {
    super.onInit();
    _getData();
    _loadRecords();
  }

  @override
  void refresh() => _getData();

  void startSearch() {
    searching.value = true;
    query.value = '';
    _loadRecords();
  }

  void stopSearch() {
    searching.value = false;
    query.value = '';
  }

  void setQuery(String value) => query.value = value;

  /// 记一条搜索记录：去重（忽略大小写与首尾空格）、置顶、截断上限
  Future<void> addRecord(String value) async {
    final text = value.trim();
    if (text.isEmpty) return;
    final lower = text.toLowerCase();
    final list = records.where((e) => e.trim().toLowerCase() != lower).toList()
      ..insert(0, text);
    if (list.length > maxRecords) {
      list.removeRange(maxRecords, list.length);
    }
    records.value = list;
    await GStorage.searchHistory.put(recordsKey, list);
  }

  Future<void> removeRecord(String value) async {
    records.value = records.where((e) => e != value).toList();
    await GStorage.searchHistory.put(recordsKey, records.toList());
  }

  Future<void> clearRecords() async {
    records.value = <String>[];
    await GStorage.searchHistory.put(recordsKey, <String>[]);
  }

  /// WebDAV 同步完成后刷新本地记录（同步模块已写回 hive）
  void reloadRecords() => _loadRecords();

  void clearAll() async {
    if (type == HistoryType.Favorite) {
      favFeed.clear();
    } else {
      historyFeed.clear();
    }
    dataList.value = <Datum>[];
    query.value = '';
  }

  void onDeleteFeed(dynamic id) {
    GStorage.onDeleteFeed(
      id.toString(),
      isHistory: type == HistoryType.History,
    );
    dataList.value = dataList.where((data) => data.id != id).toList();
  }
}
