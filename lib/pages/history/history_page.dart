import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../../components/cards/feed_card.dart';
import '../../logic/backup/fav_cloud_sync.dart';
import '../../logic/backup/webdav_client.dart';
import '../../pages/history/history_controller.dart';
import '../../utils/app_theme.dart';
import '../../utils/storage_util.dart';

// ignore: constant_identifier_names
enum HistoryType { Favorite, History }

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final HistoryType _type = Get.arguments['type'];

  late final _controller = Get.put(
    HistoryController(type: _type),
    tag: _type.name,
  );

  @override
  void dispose() {
    Get.delete<HistoryController>(
      tag: _type.name,
    );
    super.dispose();
  }

  /// 读取 WebDAV 配置；未配置返回 null
  WebDavClient? _buildClient() {
    final url = GStorage.settings.get('webdav_url', defaultValue: '');
    final user = GStorage.settings.get('webdav_user', defaultValue: '');
    final pass = GStorage.settings.get('webdav_pass', defaultValue: '');
    if (url.toString().isEmpty || user.toString().isEmpty || pass.toString().isEmpty) {
      SmartDialog.showToast('请先在设置中配置 WebDAV');
      return null;
    }
    return WebDavClient(baseUrl: url.toString(), username: user.toString(), password: pass.toString());
  }

  /// 备份收藏：云端∪本地 → 回传云端
  Future<void> _backupFav() async {
    final client = _buildClient();
    if (client == null) return;
    SmartDialog.showLoading(msg: '正在备份收藏…');
    try {
      final r = await FavCloudSync.backupFav(client);
      SmartDialog.dismiss();
      SmartDialog.showToast(
          '备份完成：云端 ${r.cloudCount} / 本地 ${r.localCount} / 合并后 ${r.mergedCount} 条，新增 ${r.added}');
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('备份失败：$e');
    }
  }

  /// 同步收藏：云端∪本地 → 写回本地 → 刷新列表
  Future<void> _restoreFav() async {
    final client = _buildClient();
    if (client == null) return;
    SmartDialog.showLoading(msg: '正在同步收藏…');
    try {
      final r = await FavCloudSync.restoreFav(client);
      SmartDialog.dismiss();
      if (r == null) {
        SmartDialog.showToast('云端无收藏备份');
      } else {
        _controller.refresh();
        SmartDialog.showToast(
            '同步完成：云端 ${r.cloudCount} / 本地 ${r.localCount} / 合并后 ${r.mergedCount} 条，新增 ${r.added}');
      }
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('同步失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        appBar: AppTheme.gradientAppBar(
          context: context,
          title: Text(_type == HistoryType.Favorite ? '收藏' : '历史记录'),
          actions: _type == HistoryType.Favorite
              ? [
                  IconButton(
                    onPressed: _backupFav,
                    icon: const Icon(Icons.backup_outlined),
                    tooltip: '备份收藏',
                  ),
                  IconButton(
                    onPressed: _restoreFav,
                    icon: const Icon(Icons.sync_outlined),
                    tooltip: '同步收藏',
                  ),
                ]
              : _controller.dataList.isNotEmpty
                  ? [
                      IconButton(
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('确定清除全部浏览历史？'),
                            actions: [
                              TextButton(
                                onPressed: () => Get.back(),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Get.back();
                                  _controller.clearAll();
                                },
                                child: const Text('确定'),
                              ),
                            ],
                          ),
                        ),
                        icon: const Icon(Icons.clear_all),
                        tooltip: '清空全部',
                      )
                    ]
                  : null,
          bottom: const PreferredSize(
              preferredSize: Size.zero, child: Divider(height: 1)),
        ),
        body: _controller.dataList.isNotEmpty
            ? ListView.separated(
                padding: EdgeInsets.only(
                  left: 10,
                  right: 10,
                  top: 10,
                  bottom: 10 + MediaQuery.of(context).padding.bottom,
                ),
                itemCount: _controller.dataList.length,
                itemBuilder: (_, index) => FeedCard(
                  isHistory: true,
                  data: _controller.dataList[index],
                  onDelete: (id) {
                    _controller.onDeleteFeed(_controller.dataList[index].id);
                  },
                ),
                separatorBuilder: (_, index) => const SizedBox(height: 10),
              )
            : const Center(
                child: Text('暂无数据'),
              ),
      ),
    );
  }
}
