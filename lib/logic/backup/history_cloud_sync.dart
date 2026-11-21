import 'dart:convert';

import 'package:c001apk_flutter/logic/backup/webdav_client.dart';
import 'package:c001apk_flutter/logic/model/fav_history/fav_history.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';

/// 浏览历史云备份独立文件名（只含 historyFeed，不碰全量备份与收藏备份）
const String historyBackupFileName = 'c001apk_history_backup.json';

/// 历史云同步结果
class HistorySyncResult {
  HistorySyncResult({
    required this.cloudCount,
    required this.localCount,
    required this.mergedCount,
    required this.added,
    required this.skipped,
  });

  final int cloudCount;
  final int localCount;
  final int mergedCount;

  /// 本次从云端补进本地的条数
  final int added;

  /// 本地解析失败的坏条目数
  final int skipped;
}

/// 浏览历史 WebDAV 双向同步：按键(id)并集合并，云端与本机互相补齐。
///
/// - 不覆盖、不删除任何一方独有的记录；
/// - 同一条记录两边都有时保留本机（本机即最新一次浏览写入）；
/// - 合并结果回写本机与云端，因此多设备来回打开历史页即可互相同步；
/// - 合并后按浏览时间倒序裁剪到 [maxItems]，避免云端文件无限膨胀。
class HistoryCloudSync {
  /// 云端最多保留的历史条数
  static const int maxItems = 2000;

  /// 删除墓碑上限（防止设置里无限增长）
  static const int maxTombstones = 500;

  static const String _tombstoneKey = 'historyDeletedAt';

  /// 防止连续点击历史入口时并发同步
  static bool _running = false;

  /// 从设置读取 WebDAV 配置；未配置返回 null（与收藏同步共用同一份配置）
  static WebDavClient? clientFromSettings() {
    final url = GStorage.settings.get('webdav_url', defaultValue: '');
    final user = GStorage.settings.get('webdav_user', defaultValue: '');
    final pass = GStorage.settings.get('webdav_pass', defaultValue: '');
    final u = url.toString().trim();
    final n = user.toString().trim();
    final p = pass.toString().trim();
    if (u.isEmpty || n.isEmpty || p.isEmpty) return null;
    if (!u.startsWith('http')) return null;
    return WebDavClient(baseUrl: u, username: n, password: p);
  }

  /// 把本机 historyFeed 拍平成 {key: json}
  static Map<String, Map<String, dynamic>> collectLocal() {
    final out = <String, Map<String, dynamic>>{};
    GStorage.historyFeed.toMap().forEach((k, v) {
      if (v is! FavHistoryItem) return;
      final key = (v.id ?? '$k').toString();
      out[key] = {
        'id': v.id,
        'uid': v.uid,
        'username': v.username,
        'userAvatar': v.userAvatar,
        'message': v.message,
        'device': v.device,
        'dateline': v.dateline,
        'time': v.time,
      };
    });
    return out;
  }

  /// 并集：云端在前、本机覆盖同名键
  static Map<String, Map<String, dynamic>> union(
    Map<String, Map<String, dynamic>> local,
    Map<String, Map<String, dynamic>> cloud,
  ) {
    final merged = Map<String, Map<String, dynamic>>.from(cloud);
    merged.addAll(local);
    return merged;
  }

  /// 记录本地删除墓碑（单条删除用，避免下次同步从云端又拉回来）
  static Future<void> markDeleted(String id) async {
    final raw = GStorage.settings.get(_tombstoneKey, defaultValue: null);
    final map = <String, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final t = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
        map['$k'] = t;
      });
    }
    map[id] = DateTime.now().millisecondsSinceEpoch;
    if (map.length > maxTombstones) {
      final entries = map.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      map
        ..clear()
        ..addEntries(entries.take(maxTombstones));
    }
    await GStorage.settings.put(_tombstoneKey, map);
  }

  static Map<String, int> _localTombstones() {
    final raw = GStorage.settings.get(_tombstoneKey, defaultValue: null);
    if (raw is! Map) return <String, int>{};
    final out = <String, int>{};
    raw.forEach((k, v) {
      final t = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      out['$k'] = t;
    });
    return out;
  }

  /// 按 time 倒序截断
  static Map<String, Map<String, dynamic>> trim(
      Map<String, Map<String, dynamic>> merged) {
    if (merged.length <= maxItems) return merged;
    final entries = merged.entries.toList()
      ..sort((a, b) {
        final ta = (a.value['time'] as num?)?.toInt() ?? 0;
        final tb = (b.value['time'] as num?)?.toInt() ?? 0;
        return tb.compareTo(ta);
      });
    return Map<String, Map<String, dynamic>>.fromEntries(
      entries.take(maxItems),
    );
  }

  /// 进入历史页时的自动同步：云端有文件就双向合并；没有就先建一份。
  /// 未配置 WebDAV 时返回 null。
  static Future<HistorySyncResult?> autoSync(WebDavClient client) async {
    if (_running) return null;
    _running = true;
    try {
      final local = collectLocal();
      Map<String, Map<String, dynamic>> cloud = {};
      Map<String, int> cloudDeleted = {};
      final raw = await client.getBackupOrNull(fileName: historyBackupFileName);
      if (raw != null && raw.isNotEmpty) {
        final parsed = _parse(raw);
        cloud = parsed.$1;
        cloudDeleted = parsed.$2;
      }

      // 墓碑：本机与云端的删除记录合并，删得比浏览时间晚的条目一律剔除
      final deleted = <String, int>{...cloudDeleted, ..._localTombstones()};
      var merged = trim(union(local, cloud));
      merged.removeWhere((key, value) {
        final int tomb = deleted[key] ?? 0;
        if (tomb == 0) return false;
        final int seen = (value['time'] as num?)?.toInt() ?? 0;
        return tomb >= seen;
      });
      // 已剔除的墓碑在云端也不再需要（对应条目已从文件里删掉）
      deleted.removeWhere((key, _) => !merged.containsKey(key));

      // 回写本机：只补缺失条目，已有条目保持本机版本
      int added = 0;
      int skipped = 0;
      for (final e in merged.entries) {
        if (GStorage.historyFeed.containsKey(e.key)) continue;
        try {
          await GStorage.historyFeed.put(e.key, FavHistoryItem.fromJson(e.value));
          added++;
        } catch (_) {
          skipped++;
        }
      }
      // 本机也按墓碑清一遍（其他设备删掉的条目）
      for (final key in deleted.keys) {
        if (GStorage.historyFeed.containsKey(key)) {
          await GStorage.historyFeed.delete(key);
        }
      }
      await GStorage.settings.put(_tombstoneKey, deleted);

      await client.putBackup(
        utf8.encode(jsonEncode({
          'app': 'c001apk',
          'type': 'history',
          'version': 1,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
          'history': merged,
          'deleted': deleted,
        })),
        fileName: historyBackupFileName,
      );

      return HistorySyncResult(
        cloudCount: cloud.length,
        localCount: local.length,
        mergedCount: merged.length,
        added: added,
        skipped: skipped,
      );
    } finally {
      _running = false;
    }
  }

  /// 清空云端历史文件（用户主动「清空全部」时调用，避免下一次进页面
  /// 又把旧记录从云端拉回来）
  static Future<void> clearRemote(WebDavClient client) async {
    await GStorage.settings.put(_tombstoneKey, <String, int>{});
    await client.putBackup(
      utf8.encode(jsonEncode({
        'app': 'c001apk',
        'type': 'history',
        'version': 1,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'history': <String, dynamic>{},
        'deleted': <String, dynamic>{},
      })),
      fileName: historyBackupFileName,
    );
  }

  static (Map<String, Map<String, dynamic>>, Map<String, int>) _parse(
      List<int> raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(raw));
    } on FormatException {
      throw WebDavException('云端历史记录文件不是合法 JSON，请检查文件是否完整');
    }
    if (decoded is! Map<String, dynamic>) {
      throw WebDavException('云端历史记录文件结构不正确');
    }
    if (decoded['app'] != 'c001apk') {
      throw WebDavException('云端历史记录来源不匹配：不是本应用的同步文件');
    }
    final history = decoded['history'];
    final deletedRaw = decoded['deleted'];
    final historyMap = <String, Map<String, dynamic>>{};
    if (history is Map) {
      history.forEach((k, v) {
        if (v is Map) {
          historyMap[k.toString()] = Map<String, dynamic>.from(v);
        }
      });
    }
    final deleted = <String, int>{};
    if (deletedRaw is Map) {
      deletedRaw.forEach((k, v) {
        deleted[k.toString()] =
            (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      });
    }
    return (historyMap, deleted);
  }
}
