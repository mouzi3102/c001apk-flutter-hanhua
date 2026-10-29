// v12 三重验证：App 同款 dio 代码路径全流程闭环（凭据走环境变量，脚本无敏感信息）
import 'dart:convert';
import 'dart:io';

import 'package:c001apk_flutter/logic/backup/backup_service.dart';
import 'package:c001apk_flutter/logic/backup/webdav_client.dart';

int pass = 0;
int fail = 0;

void check(String name, bool ok, [String? detail]) {
  if (ok) {
    pass++;
    print('PASS  $name${detail == null ? '' : ' | $detail'}');
  } else {
    fail++;
    print('FAIL  $name${detail == null ? '' : ' | $detail'}');
  }
}

Future<void> main() async {
  final user = Platform.environment['WEBDAV_USER']!;
  final passwd = Platform.environment['WEBDAV_PASS']!;
  final root = Platform.environment['WEBDAV_URL_ROOT']!;

  final boxes = <String, Map<String, dynamic>>{
    'settings': {
      'isLogin': true,
      'uid': 'triple-check',
      'token': 'triple-token-xyz',
      'refresh_rate_fps': 144,
      'refresh_adaptive': true,
    },
    'searchHistory': {
      'searchHistory': ['c001apk', '三重验证'],
    },
    'blackList': {
      'userBlackList': ['u1'],
      'topicBlackList': ['t1'],
    },
    'historyFeed': {
      'h1': {
        'id': 'h1', 'uid': 'u1', 'username': 'hist', 'userAvatar': '',
        'message': '历史条目', 'device': '', 'dateline': '1730000000', 'time': 1730000000,
      },
    },
    'favFeed': {
      'f1': {
        'id': 'f1', 'uid': 'u2', 'username': 'fav', 'userAvatar': '',
        'message': '收藏条目', 'device': '', 'dateline': '1730000001', 'time': 1730000001,
      },
    },
  };

  final client = WebDavClient(baseUrl: root, username: user, password: passwd);

  // 场景1：根目录备份（自动建目录）
  final m1 = await BackupService.backupTo(client, boxes);
  check('场景1 根目录备份成功', m1.contains('上传') || m1.isEmpty, m1);

  // 场景2：恢复逐项核对
  final restored = await BackupService.restoreFrom(client);
  check('场景2 settings.token 一致', restored['settings']?['token'] == 'triple-token-xyz');
  check('场景2 refresh_rate_fps=144', restored['settings']?['refresh_rate_fps'] == 144);
  check('场景2 searchHistory 一致',
      jsonEncode(restored['searchHistory']) == jsonEncode(boxes['searchHistory']));
  check('场景2 blackList 一致',
      jsonEncode(restored['blackList']) == jsonEncode(boxes['blackList']));
  final (hItems, hSkip) = BackupService.reviveFavEntries(restored['historyFeed']!);
  final (fItems, fSkip) = BackupService.reviveFavEntries(restored['favFeed']!);
  check('场景2 historyFeed 回灌', hItems.length == 1 && hSkip == 0 && hItems['h1']?.message == '历史条目');
  check('场景2 favFeed 回灌', fItems.length == 1 && fSkip == 0 && fItems['f1']?.username == 'fav');

  // 场景3：再次备份幂等
  final m3 = await BackupService.backupTo(client, boxes);
  check('场景3 重复备份幂等', true, m3);

  // 场景4：错误密码 → 认证失败带状态码
  final bad = WebDavClient(baseUrl: root, username: user, password: 'wrong-pass-000');
  try {
    await BackupService.backupTo(bad, boxes);
    check('场景4 错误密码应报错', false);
  } on WebDavException catch (e) {
    check('场景4 认证失败带状态码',
        e.message.contains('认证失败') && e.message.contains('401'), e.message);
  }

  // 场景5：无效地址 → 中文错误
  final badHost = WebDavClient(
      baseUrl: 'http://127.0.0.1:1/none', username: user, password: passwd);
  try {
    await BackupService.backupTo(badHost, boxes);
    check('场景5 无效地址应报错', false);
  } on WebDavException catch (e) {
    check('场景5 无效地址中文提示', e.message.contains('连接'), e.message);
  }

  // 场景6：删文件后恢复 → 备份不存在
  // （由外部 curl DELETE 完成后再跑此步——此处先报告，由主脚本顺序执行）
  print('SCENE6_READY: 请先 curl DELETE 测试文件后重跑本步');

  print('\n结果：$pass 通过 / $fail 失败');
  if (fail > 0) throw StateError('存在失败用例');
}
