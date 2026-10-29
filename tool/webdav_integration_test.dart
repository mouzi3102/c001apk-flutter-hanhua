// v10 WebDAV 备份集成测试（纯 Dart，可被 dart run 直接执行）
// 前置：python3 tools/webdav_test_server.py 已在 127.0.0.1:8765 运行
import 'dart:convert';

import 'package:c001apk_flutter/logic/backup/backup_service.dart';
import 'package:c001apk_flutter/logic/backup/webdav_client.dart';

int _passed = 0;
int _failed = 0;

void _check(String name, bool ok) {
  if (ok) {
    _passed++;
    print('PASS  $name');
  } else {
    _failed++;
    print('FAIL  $name');
  }
}

Future<void> main() async {
  const base = 'http://127.0.0.1:8765/dav';

  // 1) 正常往返：备份 → 恢复 → 断言键完整一致
  final boxes = <String, Map<String, dynamic>>{
    'settings': {
      'isLogin': true,
      'uid': '12345',
      'token': 'test-token-xyz',
      'userAvatar': 'https://example.com/a.png',
      'fontScale': 1.25,
      'refresh_rate_fps': 144,
      'refresh_adaptive': true,
    },
    'searchHistory': {
      'searchHistory': ['c001apk', '酷安'],
    },
    'blackList': {
      'userBlackList': ['u1', 'u2'],
      'topicBlackList': ['t1'],
    },
    'historyFeed': {
      '1001': {
        'id': '1001',
        'uid': 'u1',
        'username': 'alice',
        'userAvatar': 'https://example.com/a.png',
        'message': '历史动态一',
        'device': 'test',
        'dateline': '1730000000',
        'time': 1730000000,
      },
      '1002': {
        'id': '1002',
        'uid': 'u2',
        'username': 'bob',
        'userAvatar': '',
        'message': '历史动态二',
        'device': '',
        'dateline': '1730000100',
        'time': 1730000100,
      },
    },
    'favFeed': {
      '2001': {
        'id': '2001',
        'uid': 'u9',
        'username': 'carol',
        'userAvatar': 'https://example.com/c.png',
        'message': '收藏动态一',
        'device': 'dev',
        'dateline': '1730000200',
        'time': 1730000200,
      },
    },
  };

  final client = WebDavClient(baseUrl: base, username: 'user', password: 'pass');
  await BackupService.backupTo(client, boxes);
  final restored = await BackupService.restoreFrom(client);

  _check('往返后 settings 键数一致',
      jsonEncode(restored['settings']) == jsonEncode(boxes['settings']));
  _check('往返后 token 完整往返',
      restored['settings']?['token'] == 'test-token-xyz');
  _check('往返后 refresh_rate_fps=144 保持',
      restored['settings']?['refresh_rate_fps'] == 144);
  _check('往返后 searchHistory 列表完整',
      jsonEncode(restored['searchHistory']) ==
          jsonEncode(boxes['searchHistory']));
  _check('往返后 blackList 双列表完整',
      jsonEncode(restored['blackList']) == jsonEncode(boxes['blackList']));

  // typed box：fromJson 回灌实例化
  final (historyItems, historySkipped) =
      BackupService.reviveFavEntries(restored['historyFeed']!);
  _check('historyFeed 往返 2 条完整回灌',
      historyItems.length == 2 && historySkipped == 0);
  _check('historyFeed 条目字段一致',
      historyItems['1001']?.username == 'alice' &&
          historyItems['1001']?.message == '历史动态一' &&
          historyItems['1002']?.uid == 'u2');
  final (favItems, favSkipped) =
      BackupService.reviveFavEntries(restored['favFeed']!);
  _check('favFeed 往返 1 条完整回灌', favItems.length == 1 && favSkipped == 0);
  _check('favFeed 条目字段一致',
      favItems['2001']?.username == 'carol' &&
          favItems['2001']?.time == 1730000200);

  // 坏条目跳过：混入一条结构损坏的数据
  final badEntries = {
    '999': 'not-a-map',
    '1001': boxes['historyFeed']!['1001'],
  };
  final (fixedItems, fixedSkipped) = BackupService.reviveFavEntries(badEntries);
  _check('坏条目跳过计数正确', fixedItems.length == 1 && fixedSkipped == 1);

  // 2) 401 认证失败路径
  final badAuth =
      WebDavClient(baseUrl: base, username: 'user', password: 'wrong');
  try {
    await BackupService.restoreFrom(badAuth);
    _check('401 应抛认证失败', false);
  } on WebDavException catch (e) {
    _check('401 中文文案含认证失败', e.message.contains('认证失败'));
  }

  // 3) 404 未备份路径
  final missing = WebDavClient(
      baseUrl: 'http://127.0.0.1:8765/nonexistent',
      username: 'user',
      password: 'pass');
  try {
    await BackupService.restoreFrom(missing);
    _check('404 应抛备份不存在', false);
  } on WebDavException catch (e) {
    _check('404 中文文案含备份不存在', e.message.contains('备份不存在'));
  }

  // 4) JSON 结构校验：非法字节应抛中文错误
  try {
    BackupService.decodeAndValidate(utf8.encode('not-a-json'));
    _check('非法 JSON 应抛错', false);
  } on WebDavException catch (e) {
    _check('非法 JSON 中文文案', e.message.contains('不是合法 JSON'));
  }

  print('\n结果：$_passed 通过 / $_failed 失败');
  if (_failed > 0) {
    throw StateError('存在失败用例');
  }
}
