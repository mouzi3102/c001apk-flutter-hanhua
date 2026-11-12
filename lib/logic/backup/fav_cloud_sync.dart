import 'dart:convert';

import 'package:c001apk_flutter/logic/backup/webdav_client.dart';
import 'package:c001apk_flutter/logic/model/fav_history/fav_history.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';

/// 收藏云备份独立文件名（只含 favFeed，不碰全量备份 c001apk_backup_v10.json）
const String favBackupFileName = 'c001apk_fav_backup.json';

/// 收藏云备份结果
class FavBackupResult {
  FavBackupResult({
    required this.cloudCount,
    required this.localCount,
    required this.mergedCount,
    required this.added,
    required this.skipped,
    required this.cloudExisted,
  });

  final int cloudCount;
  final int localCount;
  final int mergedCount;
  final int added;
  final int skipped;
  final bool cloudExisted;
}

/// 收藏备份/同步：id 并集合并（任何方向都不覆盖/删除对方独有收藏）。
/// 纯逻辑，favFeed 数据结构沿用 FavHistoryItem。
class FavCloudSync {
  /// 从设置读取 WebDAV 配置；未配置（或用默认占位值）返回 null。
  /// 供「收藏后自动上传」「进入收藏页自动同步」这类静默流程使用，
  /// 与手动按钮不同，这里不弹任何提示。
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

  /// 把本地 favFeed 拍平成 {id: json}
  static Map<String, Map<String, dynamic>> collectLocalFav() {
    final out = <String, Map<String, dynamic>>{};
    for (final entry in GStorage.favFeed.toMap().entries) {
      final item = entry.value;
      if (item is FavHistoryItem && item.id != null) {
        out[item.id!] = {
          'id': item.id,
          'uid': item.uid,
          'username': item.username,
          'userAvatar': item.userAvatar,
          'message': item.message,
          'device': item.device,
          'dateline': item.dateline,
          'time': item.time,
        };
      }
    }
    return out;
  }

  /// 并集合并：id 去重，冲突保留本地（本地为最新写入）
  static Map<String, Map<String, dynamic>> unionFav(
    Map<String, Map<String, dynamic>> local,
    Map<String, Map<String, dynamic>> cloud,
  ) {
    final merged = Map<String, Map<String, dynamic>>.from(cloud);
    merged.addAll(local);
    return merged;
  }

  /// 备份收藏：GET 云端（若有）→ 云端∪本地 → PUT 回云端
  static Future<FavBackupResult> backupFav(WebDavClient client) async {
    final local = collectLocalFav();
    int cloudCount = 0;
    bool cloudExisted = true;
    Map<String, Map<String, dynamic>> cloud = {};

    final raw = await client.getBackupOrNull(fileName: favBackupFileName);
    if (raw == null) {
      cloudExisted = false;
    } else {
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is Map && decoded['fav'] is Map) {
        final rawMap = Map.from(decoded['fav'] as Map);
        cloud = rawMap.map((k, v) =>
            MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
        cloudCount = cloud.length;
      }
    }

    final merged = unionFav(local, cloud);
    final body = jsonEncode({'fav': merged});
    await client.putBackup(utf8.encode(body), fileName: favBackupFileName);

    return FavBackupResult(
      cloudCount: cloudCount,
      localCount: local.length,
      mergedCount: merged.length,
      added: merged.length - cloudCount,
      skipped: cloudCount,
      cloudExisted: cloudExisted,
    );
  }

  /// 同步收藏：GET 云端 → 云端∪本地 → 写回本地 → 回传 PUT 合并集（双向对齐）
  /// 返回 null = 云端无收藏备份
  static Future<FavBackupResult?> restoreFav(WebDavClient client) async {
    final raw = await client.getBackupOrNull(fileName: favBackupFileName);
    if (raw == null) return null;

    Map<String, Map<String, dynamic>> cloud = {};
    final decoded = jsonDecode(utf8.decode(raw));
    if (decoded is Map && decoded['fav'] is Map) {
      final rawMap = Map.from(decoded['fav'] as Map);
      cloud = rawMap.map((k, v) =>
          MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
    }
    final local = collectLocalFav();
    final merged = unionFav(local, cloud);

    // 写回本地（合并集；缺 id 跳过并计数）
    int skipped = 0;
    for (final e in merged.entries) {
      final id = e.key;
      if (GStorage.favFeed.keys.contains(id)) continue;
      try {
        await GStorage.favFeed.put(id, FavHistoryItem.fromJson(e.value));
      } catch (_) {
        skipped++;
      }
    }

    // 回传合并集（双向对齐）
    final body = jsonEncode({'fav': merged});
    await client.putBackup(utf8.encode(body), fileName: favBackupFileName);

    return FavBackupResult(
      cloudCount: cloud.length,
      localCount: local.length,
      mergedCount: merged.length,
      added: merged.length - local.length,
      skipped: skipped,
      cloudExisted: true,
    );
  }
}
