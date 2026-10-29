import 'dart:convert';

import '../model/fav_history/fav_history.dart';
import 'webdav_client.dart';

/// 备份/恢复纯逻辑层（不依赖 Flutter UI，可被 dart 脚本直接调用做集成测试）。
///
/// 备份 JSON 结构：
/// ```json
/// {
///   "app": "c001apk",
///   "version": 1,
///   "createdAt": 1730000000000,
///   "boxes": {
///     "settings": { ... },
///     "searchHistory": { ... },
///     "historyFeed": { ... },
///     "favFeed": { ... },
///     "blackList": { ... }
///   }
/// }
/// ```
///
/// 收集范围以 v10_备份范围清单.md 为准：5 个 hive box。
/// 排除键（settings box）：checkCount（死键）、custom_bg_enabled/path/blur
/// （v10 已删除自定义背景功能，数据作废）。SESSID 仅内存态不落盘，天然排除。
/// 注意：typed 对象（historyFeed/favFeed）由调用方先经 toJson/手工拍平为
/// 纯 JSON 值再传入；本层只做结构校验与往返一致性保证。
class BackupService {
  static const int backupVersion = 1;
  static const String appName = 'c001apk';

  /// 备份包含的 box 名（与 GStorage 中 openBox 名一致）
  static const List<String> backedBoxNames = [
    'settings',
    'searchHistory',
    'historyFeed',
    'favFeed',
    'blackList',
  ];

  /// settings box 内排除的键（死键 + 已删除功能的数据）
  static const Set<String> excludedSettingsKeys = {
    'checkCount',
    'custom_bg_enabled',
    'custom_bg_path',
    'custom_bg_blur',
  };

  /// 把已拍平为 JSON 安全值的各 box 内容收集为备份文档。
  /// [boxesData]：boxName -> (key -> JSON 安全值)。
  static Map<String, dynamic> collect(Map<String, Map<String, dynamic>> boxesData) {
    return {
      'app': appName,
      'version': backupVersion,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'boxes': boxesData,
    };
  }

  /// 序列化为 JSON 文本。
  static String encode(Map<String, dynamic> backupDoc) =>
      const JsonEncoder.withIndent('  ').convert(backupDoc);

  /// 校验下载到的字节是否合法备份，返回 boxes 子表（boxName -> key->value）。
  /// 失败抛 WebDavException（中文文案）。
  static Map<String, Map<String, dynamic>> decodeAndValidate(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw WebDavException('备份文件不是合法 JSON，请确认文件完整');
    }
    if (decoded is! Map<String, dynamic>) {
      throw WebDavException('备份文件结构不正确');
    }
    if (decoded['app'] != appName) {
      throw WebDavException('备份来源不匹配：不是本应用的备份文件');
    }
    final boxes = decoded['boxes'];
    if (boxes is! Map<String, dynamic> || boxes.isEmpty) {
      throw WebDavException('备份内容为空或结构不正确');
    }
    final out = <String, Map<String, dynamic>>{};
    boxes.forEach((boxName, value) {
      if (value is Map<String, dynamic>) out[boxName] = value;
    });
    if (out.isEmpty) {
      throw WebDavException('备份内容为空或结构不正确');
    }
    return out;
  }

  /// 远程备份：收集 [boxesData] → PUT 上传。
  static Future<String> backupTo(
    WebDavClient client,
    Map<String, Map<String, dynamic>> boxesData,
  ) async {
    final doc = collect(boxesData);
    final bytes = utf8.encode(encode(doc));
    return client.putBackup(bytes);
  }

  /// 远程恢复：GET 下载 → 校验 → 返回应写回 hive 的 boxes 键值表。
  static Future<Map<String, Map<String, dynamic>>> restoreFrom(
      WebDavClient client) async {
    final bytes = await client.getBackup();
    return decodeAndValidate(bytes);
  }

  /// typed box（historyFeed/favFeed 均存 FavHistoryItem）恢复回灌：
  /// 把 JSON 条目用 FavHistoryItem.fromJson 实例化。校验失败的条目跳过并计数，
  /// 不影响其余条目恢复。返回 (可写回 hive 的键值表, 跳过条数)。
  static (Map<String, FavHistoryItem>, int) reviveFavEntries(
      Map<String, dynamic> raw) {
    final out = <String, FavHistoryItem>{};
    var skipped = 0;
    raw.forEach((k, v) {
      try {
        if (v is Map<String, dynamic>) {
          out[k] = FavHistoryItem.fromJson(v);
        } else {
          skipped++;
        }
      } catch (_) {
        skipped++;
      }
    });
    return (out, skipped);
  }

  /// hive box 键值 → JSON 安全值（递归拍平 List/Map；其他自定义对象 toString 兜底，
  /// 恢复时不可反序列化回原类型——typed box 由调用方提前 toJson 避免走此路径）。
  static Map<String, dynamic> normalize(Map<dynamic, dynamic> raw) {
    final out = <String, dynamic>{};
    raw.forEach((k, v) => out['$k'] = _normalize(v));
    return out;
  }

  static dynamic _normalize(dynamic v) {
    if (v == null || v is num || v is bool || v is String) return v;
    if (v is List) return v.map(_normalize).toList();
    if (v is Map) {
      final m = <String, dynamic>{};
      v.forEach((kk, vv) => m['$kk'] = _normalize(vv));
      return m;
    }
    return v.toString();
  }
}
