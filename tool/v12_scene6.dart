// v12 场景6：删除测试文件后恢复，应提示「备份不存在」
import 'dart:io';

import 'package:c001apk_flutter/logic/backup/backup_service.dart';
import 'package:c001apk_flutter/logic/backup/webdav_client.dart';

Future<void> main() async {
  final client = WebDavClient(
    baseUrl: Platform.environment['WEBDAV_URL_ROOT']!,
    username: Platform.environment['WEBDAV_USER']!,
    password: Platform.environment['WEBDAV_PASS']!,
  );
  try {
    await BackupService.restoreFrom(client);
    print('FAIL  场景6 意外成功');
  } on WebDavException catch (e) {
    final ok = e.message.contains('备份不存在');
    print('${ok ? 'PASS' : 'FAIL'}  场景6 | ${e.message}');
  }
}
