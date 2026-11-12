import 'dart:convert';

import '../../utils/storage_util.dart';
import 'webdav_client.dart';

/// 收藏 / 浏览历史页内搜索记录的 WebDAV 同步。
///
/// 独立文件 `c001apk_search_history_v1.json`，不写全量备份文件
/// `c001apk_backup_v10.json`，避免「只同步搜索记录」时把用户的全量备份覆盖掉。
///
/// 记录按页面分开存：
/// - `favSearchHistory`   → 收藏页搜索记录
/// - `historySearchHistory` → 浏览历史页搜索记录
///
/// 同步策略：云端 ∪ 本地（保留各自顺序、按上限截断），合并结果同时写回
/// 本地 hive 与云端，因此多设备之间可以互相补齐，不会丢记录。
class SearchHistorySync {
  static const String appName = 'c001apk';
  static const String remoteFileName = 'c001apk_search_history_v1.json';
  static const int version = 1;

  /// 每条记录上限（与页面内一致）
  static const int maxPerKey = 20;

  static const List<String> boxKeys = [
    'favSearchHistory',
    'historySearchHistory',
  ];

  /// 读取本地记录（box 内为 `List<String>`，异常数据一律容错为空表）
  static Map<String, List<String>> localRecords() {
    final out = <String, List<String>>{};
    for (final key in boxKeys) {
      out[key] = _toStringList(
        GStorage.searchHistory.get(key, defaultValue: const <String>[]),
      );
    }
    return out;
  }

  /// 本地记录总数
  static int localCount() =>
      localRecords().values.fold<int>(0, (sum, list) => sum + list.length);

  /// 同步：拉取云端 → 与本地合并 → 写回本地与云端。返回合并后总条数。
  static Future<int> sync(WebDavClient client) async {
    final local = localRecords();
    final remote = await _fetchRemote(client);
    final merged = <String, List<String>>{};
    for (final key in boxKeys) {
      merged[key] = _mergeList(local[key] ?? const [], remote[key] ?? const []);
    }

    final bytes = utf8.encode(jsonEncode({
      'app': appName,
      'type': 'searchHistory',
      'version': version,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'records': merged,
    }));

    await client.putBackup(bytes, fileName: remoteFileName);

    for (final key in boxKeys) {
      await GStorage.searchHistory.put(key, merged[key]);
    }

    return merged.values.fold<int>(0, (sum, list) => sum + list.length);
  }

  static Future<Map<String, List<String>>> _fetchRemote(
      WebDavClient client) async {
    final raw = await client.getBackupOrNull(fileName: remoteFileName);
    if (raw == null || raw.isEmpty) return <String, List<String>>{};
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(raw));
    } on FormatException {
      throw WebDavException('云端搜索记录文件不是合法 JSON，请检查文件是否完整');
    }
    if (decoded is! Map<String, dynamic>) {
      throw WebDavException('云端搜索记录文件结构不正确');
    }
    if (decoded['app'] != appName) {
      throw WebDavException('云端搜索记录来源不匹配：不是本应用的同步文件');
    }
    final records = decoded['records'];
    if (records is! Map<String, dynamic>) return <String, List<String>>{};
    final out = <String, List<String>>{};
    for (final key in boxKeys) {
      out[key] = _toStringList(records[key]);
    }
    return out;
  }

  /// 合并：云端在前、本地补后，去重（忽略空白差异），截断到 [maxPerKey]
  static List<String> _mergeList(List<String> remote, List<String> local) {
    final out = <String>[];
    final seen = <String>{};
    for (final list in [remote, local]) {
      for (final item in list) {
        final text = item.trim();
        if (text.isEmpty) continue;
        if (seen.add(text.toLowerCase())) out.add(text);
        if (out.length >= maxPerKey) return out;
      }
    }
    return out;
  }

  static List<String> _toStringList(Object? value) {
    if (value is List) {
      return value
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    return <String>[];
  }
}
