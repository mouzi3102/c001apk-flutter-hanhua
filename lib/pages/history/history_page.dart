import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../../components/cards/feed_card.dart';
import '../../components/cards/search_history_card.dart';
import '../../logic/backup/fav_cloud_sync.dart';
import '../../logic/backup/search_history_sync.dart';
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

  /// 搜索输入框（与 AppBar 标题区共用）
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  String get _pageTitle => _type == HistoryType.Favorite ? '收藏' : '历史记录';

  String get _searchHint =>
      _type == HistoryType.Favorite ? '搜索收藏内容' : '搜索浏览历史';

  @override
  void initState() {
    super.initState();
    // 进入「本地收藏」即静默做一次双向同步（云端∪本地 → 写回本地 & 云端）
    if (_type == HistoryType.Favorite) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoSyncFav());
    }
  }

  /// 进入收藏页时的静默同步：未配置 WebDAV 就跳过，不弹提示
  Future<void> _autoSyncFav() async {
    final client = FavCloudSync.clientFromSettings();
    if (client == null) return;
    try {
      final r = await FavCloudSync.restoreFav(client);
      if (r != null && mounted) {
        _controller.refresh();
      }
    } catch (e) {
      debugPrint('[fav auto sync] failed: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
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
    if (url.toString().isEmpty ||
        user.toString().isEmpty ||
        pass.toString().isEmpty) {
      SmartDialog.showToast('请先在设置中配置 WebDAV');
      return null;
    }
    return WebDavClient(
      baseUrl: url.toString(),
      username: user.toString(),
      password: pass.toString(),
    );
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

  /// 同步搜索记录：云端∪本地 → 写回本地 & 云端
  Future<void> _syncSearchRecords() async {
    final client = _buildClient();
    if (client == null) return;
    SmartDialog.showLoading(msg: '正在同步搜索记录…');
    try {
      final total = await SearchHistorySync.sync(client);
      _controller.reloadRecords();
      SmartDialog.dismiss();
      SmartDialog.showToast('搜索记录已同步：共 $total 条');
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('搜索记录同步失败：$e');
    }
  }

  void _startSearch() {
    _controller.startSearch();
    _searchController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _stopSearch() {
    // 退出搜索时把当前关键词记入搜索记录，避免「输入后直接点条目」漏记
    final keyword = _controller.query.value.trim();
    if (keyword.isNotEmpty) _controller.addRecord(keyword);
    _searchController.clear();
    _controller.stopSearch();
  }

  Future<void> _confirmClearRecords() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确定清空全部搜索记录？'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _controller.clearRecords();
      SmartDialog.showToast('搜索记录已清空');
    }
  }

  /// 搜索记录面板：记录 chip + 同步 / 清空入口
  Widget _buildSearchHistoryPanel(BuildContext context) {
    final records = _controller.records;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '搜索记录',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                '${records.length}/${HistoryController.maxRecords}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _syncSearchRecords,
                icon: const Icon(Icons.cloud_sync_outlined),
                tooltip: '通过 WebDAV 同步搜索记录',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: records.isEmpty ? null : _confirmClearRecords,
                icon: const Icon(Icons.delete_outline),
                tooltip: '清空搜索记录',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '暂无搜索记录，输入关键词即可搜索$_pageTitle',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: records
                  .map(
                    (text) => SearchHistoryCard(
                      text: text,
                      onTap: () {
                        _searchController.text = text;
                        _searchController
                            .selection = TextSelection.fromPosition(
                          TextPosition(offset: text.length),
                        );
                        _controller.setQuery(text);
                        _searchFocus.requestFocus();
                      },
                      onLongPress: () async {
                        await _controller.removeRecord(text);
                        SmartDialog.showToast('已删除搜索记录「$text」');
                      },
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 16),
          Text(
            '提示：长按记录可删除；记录保存在本地，也可通过 WebDAV 同步到其他设备。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// 结果数量提示条
  Widget _buildResultBar(BuildContext context, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '找到 $count 条相关${_type == HistoryType.Favorite ? '收藏' : '历史'}',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }

  List<Widget>? _buildActions(BuildContext context) {
    if (_controller.searching.value) {
      return [
        IconButton(
          onPressed: _stopSearch,
          icon: const Icon(Icons.close),
          tooltip: '退出搜索',
        ),
      ];
    }

    final baseActions = <Widget>[
      IconButton(
        onPressed: _startSearch,
        icon: const Icon(Icons.search),
        tooltip: '搜索',
      ),
    ];

    if (_type == HistoryType.Favorite) {
      baseActions.addAll([
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
      ]);
    } else if (_controller.dataList.isNotEmpty) {
      baseActions.add(
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
        ),
      );
    }
    return baseActions;
  }

  Widget _buildTitle(BuildContext context) {
    if (!_controller.searching.value) {
      return Text(_pageTitle);
    }
    final fg = AppTheme.appBarForeground(Theme.of(context).brightness);
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      autofocus: true,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: 16, color: fg),
      cursorColor: fg,
      decoration: InputDecoration(
        isDense: true,
        hintText: _searchHint,
        hintStyle: TextStyle(fontSize: 15, color: fg.withValues(alpha: 0.6)),
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: _controller.setQuery,
      onSubmitted: (value) => _controller.addRecord(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        final searching = _controller.searching.value;
        final visible = _controller.visibleList;
        final keywordEmpty = _controller.query.value.trim().isEmpty;

        Widget body;
        if (searching && keywordEmpty) {
          body = _buildSearchHistoryPanel(context);
        } else if (visible.isEmpty) {
          body = Center(
            child: Text(
              searching ? '未找到相关内容' : '暂无数据',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          );
        } else {
          body = Column(
            children: [
              if (searching) _buildResultBar(context, visible.length),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.only(
                    left: 10,
                    right: 10,
                    top: 10,
                    bottom: 10 + MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (_, index) => FeedCard(
                    isHistory: true,
                    data: visible[index],
                    onDelete: (id) {
                      _controller.onDeleteFeed(visible[index].id);
                    },
                  ),
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                ),
              ),
            ],
          );
        }

        return Scaffold(
          appBar: AppTheme.gradientAppBar(
            context: context,
            title: _buildTitle(context),
            actions: _buildActions(context),
            bottom: const PreferredSize(
                preferredSize: Size.zero, child: Divider(height: 1)),
          ),
          body: body,
        );
      },
    );
  }
}
