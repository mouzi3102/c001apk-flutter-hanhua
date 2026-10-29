import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../components/dialog.dart';
import '../../components/settings/drop_down_menu_item.dart';
import '../../components/settings/edittext_item.dart';
import '../../components/settings/item_title.dart';
import '../../components/settings/switch_item.dart';
import '../../constants/constants.dart';
import '../../logic/backup/backup_service.dart';
import '../../logic/backup/webdav_client.dart';
import '../../logic/model/fav_history/fav_history.dart';
import '../../pages/blacklist/black_list_page.dart' show BlackListType;
import '../../utils/cache_util.dart';
import '../../utils/menu_labels.dart';
import '../../utils/app_theme.dart';
import '../../utils/storage_util.dart';
import '../../utils/utils.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

// ignore: constant_identifier_names
enum SettingsMenuItem { Feedback, About }

// ignore: constant_identifier_names
enum FollowType { ALL, USER, TOPIC, PRODUCT, APP }

// ignore: constant_identifier_names
enum ImageQuality { AUTO, ORIGIN, THUMBNAIL }

/// 自定义刷新率（144Hz）：hive settings box 持久化键
const String _kRefreshRateFpsKey = 'refresh_rate_fps';

/// 省电自适应开关：无操作 2 秒自动降至 60Hz，交互恢复所选档位
const String _kRefreshAdaptiveKey = 'refresh_adaptive';

/// WebDAV 备份：服务器地址 / 用户名 / 密码（密码明文存本机，对话框已提示）
const String _kWebdavUrlKey = 'webdav_url';
const String _kWebdavUserKey = 'webdav_user';
const String _kWebdavPassKey = 'webdav_pass';

class _SettingsPageState extends State<SettingsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final _settingsController = Get.put(SettingsController());
  String _version = '1.0.0(1)';

  /// 当前选中的刷新率档位；0 = 系统默认/自动
  int _refreshRateFps = 0;

  /// 省电自适应开关（默认开启）
  bool _refreshAdaptive = true;

  Future<void> _getVersionInfo() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    _version = '${packageInfo.version}(${packageInfo.buildNumber})';
  }

  /// 通过 MethodChannel 下发目标刷新率（0 = 自动/系统默认）
  Future<void> _applyRefreshRate(int fps) async {
    try {
      await Utils.platform.invokeMethod('setFrameRate', {'fps': fps});
    } catch (_) {}
  }

  /// 弹出档位选择 bottomSheet：自动 + 原生动态返回的档位列表
  Future<void> _onRefreshRateTap() async {
    List<int> rates = [];
    try {
      final res = await Utils.platform
          .invokeMethod<List<dynamic>>('getSupportedRefreshRates');
      rates = (res ?? const []).cast<int>();
    } catch (_) {}
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('系统默认'),
                trailing: _refreshRateFps == 0
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => _pickRefreshRate(0),
              ),
              for (final rate in rates)
                ListTile(
                  title: Text('$rate Hz'),
                  trailing: _refreshRateFps == rate
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => _pickRefreshRate(rate),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickRefreshRate(int fps) async {
    Get.back();
    setState(() => _refreshRateFps = fps);
    GStorage.settings.put(_kRefreshRateFpsKey, fps);
    await _applyRefreshRate(fps);
  }

  // ==================== WebDAV 备份/恢复 ====================

  late final TextEditingController _webdavUrlCtrl = TextEditingController(
    text: GStorage.settings.get(_kWebdavUrlKey, defaultValue: ''),
  );
  late final TextEditingController _webdavUserCtrl = TextEditingController(
    text: GStorage.settings.get(_kWebdavUserKey, defaultValue: ''),
  );
  late final TextEditingController _webdavPassCtrl = TextEditingController(
    text: GStorage.settings.get(_kWebdavPassKey, defaultValue: ''),
  );
  bool _webdavPassObscure = true;

  WebDavClient? _buildClient() {
    final url = _webdavUrlCtrl.text.trim();
    if (url.isEmpty) {
      SmartDialog.showToast('请填写 WebDAV 服务器地址');
      return null;
    }
    return WebDavClient(
      baseUrl: url,
      username: _webdavUserCtrl.text.trim(),
      password: _webdavPassCtrl.text,
    );
  }

  void _saveWebDavConfig() {
    GStorage.settings.put(_kWebdavUrlKey, _webdavUrlCtrl.text.trim());
    GStorage.settings.put(_kWebdavUserKey, _webdavUserCtrl.text.trim());
    GStorage.settings.put(_kWebdavPassKey, _webdavPassCtrl.text);
  }

  Future<void> _showWebDavDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('WebDAV 备份'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '备份文件含账号 token 等敏感信息，请谨慎保管；密码以明文保存在本机。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _webdavUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://your-server.com/dav/',
                  ),
                ),
                TextField(
                  controller: _webdavUserCtrl,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
                StatefulBuilder(
                  builder: (context, setSheetState) {
                    return TextField(
                      controller: _webdavPassCtrl,
                      obscureText: _webdavPassObscure,
                      decoration: InputDecoration(
                        labelText: '密码',
                        suffixIcon: IconButton(
                          icon: Icon(_webdavPassObscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          tooltip: _webdavPassObscure ? '显示密码' : '隐藏密码',
                          onPressed: () => setSheetState(() =>
                              _webdavPassObscure = !_webdavPassObscure),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                GStorage.settings.delete(_kWebdavUrlKey);
                GStorage.settings.delete(_kWebdavUserKey);
                GStorage.settings.delete(_kWebdavPassKey);
                _webdavUrlCtrl.clear();
                _webdavUserCtrl.clear();
                _webdavPassCtrl.clear();
                Get.back();
                SmartDialog.showToast('已清除已存配置');
              },
              child: const Text('清除已存配置'),
            ),
            TextButton(
              onPressed: () async {
                Get.back();
                await _doWebDavBackup();
              },
              child: const Text('备份'),
            ),
            TextButton(
              onPressed: () async {
                Get.back();
                await _doWebDavRestore();
              },
              child: const Text('恢复'),
            ),
          ],
        );
      },
    );
  }

  /// 收集 5 个 hive box 为 JSON 安全结构（按 v10 备份范围清单；settings 排除死键与已删除功能键）
  Map<String, Map<String, dynamic>> _collectBoxes() {
    final settings = BackupService.normalize(GStorage.settings.toMap())
      ..removeWhere((k, v) => BackupService.excludedSettingsKeys.contains(k));
    // typed box（historyFeed/favFeed 均存 FavHistoryItem）显式拍平为 JSON
    Map<String, dynamic> typedToJson(Box box) {
      final out = <String, dynamic>{};
      box.toMap().forEach((k, v) {
        if (v is FavHistoryItem) {
          out['$k'] = {
            'id': v.id,
            'uid': v.uid,
            'username': v.username,
            'userAvatar': v.userAvatar,
            'message': v.message,
            'device': v.device,
            'dateline': v.dateline,
            'time': v.time,
          };
        }
      });
      return out;
    }

    return {
      'settings': settings,
      'searchHistory': BackupService.normalize(GStorage.searchHistory.toMap()),
      'historyFeed': typedToJson(GStorage.historyFeed),
      'favFeed': typedToJson(GStorage.favFeed),
      'blackList': BackupService.normalize(GStorage.blackList.toMap()),
    };
  }

  Future<void> _doWebDavBackup() async {
    final client = _buildClient();
    if (client == null) return;
    _saveWebDavConfig();
    try {
      final msg = await BackupService.backupTo(client, _collectBoxes());
      SmartDialog.showToast(msg.isEmpty ? '备份成功' : '$msg，上传完成');
    } on WebDavException catch (e) {
      SmartDialog.showToast(e.message);
    } catch (e) {
      SmartDialog.showToast('备份失败：$e');
    }
  }

  Future<void> _doWebDavRestore() async {
    final client = _buildClient();
    if (client == null) return;
    _saveWebDavConfig();
    try {
      final boxes = await BackupService.restoreFrom(client);
      boxes.forEach((boxName, entries) {
        switch (boxName) {
          case 'settings':
            GStorage.settings.putAll(entries);
          case 'searchHistory':
            GStorage.searchHistory.putAll(entries);
          case 'blackList':
            GStorage.blackList.putAll(entries);
          case 'historyFeed':
          case 'favFeed':
            // typed box：fromJson 实例化 FavHistoryItem 后回灌；坏条目自动跳过
            final (items, skipped) = BackupService.reviveFavEntries(entries);
            if (boxName == 'historyFeed') {
              GStorage.historyFeed.putAll(items);
            } else {
              GStorage.favFeed.putAll(items);
            }
            if (skipped > 0) {
              SmartDialog.showToast('$boxName：$skipped 条数据损坏已跳过');
            }
        }
      });
      SmartDialog.showToast('恢复成功，建议重启应用');
    } on WebDavException catch (e) {
      SmartDialog.showToast(e.message);
    } catch (e) {
      SmartDialog.showToast('恢复失败：$e');
    }
  }

  @override
  void dispose() {
    _webdavUrlCtrl.dispose();
    _webdavUserCtrl.dispose();
    _webdavPassCtrl.dispose();
    Get.delete<SettingsController>();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _getVersionInfo();
    // 回读持久化的刷新率选择并重放（原生 onWindowFocusChanged 也会持续重放）
    if (Platform.isAndroid) {
      _refreshRateFps =
          GStorage.settings.get(_kRefreshRateFpsKey, defaultValue: 0);
      if (_refreshRateFps > 0) {
        _applyRefreshRate(_refreshRateFps);
      }
    }
    // 回读省电自适应状态
    _refreshAdaptive =
        GStorage.settings.get(_kRefreshAdaptiveKey, defaultValue: true);
    _webdavUrlCtrl.text = GStorage.settings.get(_kWebdavUrlKey, defaultValue: '');
    _webdavUserCtrl.text = GStorage.settings.get(_kWebdavUserKey, defaultValue: '');
    _webdavPassCtrl.text = GStorage.settings.get(_kWebdavPassKey, defaultValue: '');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppTheme.gradientAppBar(
        context: context,
        title: const Text('设置'),
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          PopupMenuButton(
            onSelected: (SettingsMenuItem item) {
              switch (item) {
                case SettingsMenuItem.Feedback:
                  Utils.launchURL(Constants.URL_SOURCE_CODE);
                  break;
                case SettingsMenuItem.About:
                  showDialog<void>(
                    context: context,
                    builder: (context) {
                      return MAboutDialog(version: _version);
                    },
                  );
                  break;
              }
            },
            itemBuilder: (context) => SettingsMenuItem.values
                .map((item) => PopupMenuItem<SettingsMenuItem>(
                      value: item,
                      child: Text(MenuLabels.of(item)),
                    ))
                .toList(),
          )
        ],
      ),
      body: Builder(
        builder: (context) {
          final brightness = Theme.of(context).brightness;
          final items = <Widget>[
          const ItemTitle(title: Constants.APP_NAME),
          const EdittextItem(
            icon: Icons.smartphone,
            title: '数字联盟ID',
            boxKey: SettingsBoxKey.szlmId,
            needUpdateXAppDevice: true,
          ),
          ListTile(
            leading: const Icon(Icons.developer_mode),
            title: const Text('参数'),
            onTap: () => Get.toNamed('/params'),
          ),
          // Theme
          ListTile(
            title: Text(
              '主题',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const DropDownMenuItem(
            icon: Icons.dark_mode_outlined,
            title: '夜间模式',
            boxKey: SettingsBoxKey.selectedTheme,
            items: [
              DropdownMenuItem<int>(
                value: 1,
                child: Text('关闭'),
              ),
              DropdownMenuItem<int>(
                value: 2,
                child: Text('开启'),
              ),
              DropdownMenuItem<int>(
                value: 0,
                child: Text('跟随系统'),
              ),
            ],
            forceAppUpdate: true,
          ),
          // Display
          ListTile(
            title: Text(
              '显示',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            title: const Text('用户黑名单'),
            leading: const Icon(Icons.block),
            onTap: () => Get.toNamed(
              '/blacklist/',
              arguments: {'type': BlackListType.user},
            ),
          ),
          ListTile(
            title: const Text('话题黑名单'),
            leading: const Icon(Icons.block),
            onTap: () => Get.toNamed(
              '/blacklist/',
              arguments: {'type': BlackListType.topic},
            ),
          ),
          ListTile(
            title: const Text('自定义刷新率'),
            subtitle: Text(
                _refreshRateFps == 0 ? '系统默认' : '$_refreshRateFps Hz'),
            leading: const Icon(Icons.speed),
            onTap: () => _onRefreshRateTap(),
          ),
          SwitchListTile(
            title: const Text('省电自适应'),
            subtitle: const Text('无操作 2 秒后自动降至 60Hz，交互恢复所选档位'),
            secondary: const Icon(Icons.battery_saver),
            value: _refreshAdaptive,
            onChanged: (v) {
              GStorage.settings.put(_kRefreshAdaptiveKey, v);
              setState(() => _refreshAdaptive = v);
            },
          ),
          ListTile(
            title: const Text('WebDAV 备份'),
            subtitle: const Text('服务器配置 / 手动备份与恢复'),
            leading: const Icon(Icons.storage_outlined),
            onTap: () => _showWebDavDialog(),
          ),
          ListTile(
            title: const Text('字体比例'),
            subtitle: Text('${GStorage.fontScale.toStringAsFixed(2)} 倍'),
            leading: const Icon(Icons.text_fields),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => SliderDialog(
                fontScale: GStorage.fontScale,
                setData: (newValue) {
                  GStorage.setFontScale(newValue);
                  Get.forceAppUpdate();
                },
              ),
            ),
          ),
          DropDownMenuItem(
            icon: Icons.add_circle_outline_outlined,
            title: '关注类型',
            boxKey: SettingsBoxKey.followType,
            items: FollowType.values
                .map((type) => DropdownMenuItem<int>(
                      value: FollowType.values.indexOf(type),
                      child: Text(switch (type) {
                        FollowType.ALL => '全部',
                        FollowType.USER => '用户',
                        FollowType.TOPIC => '话题',
                        FollowType.PRODUCT => '产品',
                        FollowType.APP => '应用',
                      }),
                    ))
                .toList(),
          ),
          /*
          DropDownMenuItem(
            icon: Icons.image_outlined,
            title: 'Image Quality',
            boxKey: SettingsBoxKey.imageQuality,
            items: ImageQuality.values
                .map((type) => DropdownMenuItem<int>(
                      value: ImageQuality.values.indexOf(type),
                      child: Text(type.name),
                    ))
                .toList(),
          ),
          const SwitchItem(
            icon: Icons.image_outlined,
            title: 'Image Dim',
            boxKey: SettingsBoxKey.imageDim,
            defaultValue: true,
          ),
          */
          const SwitchItem(
            icon: Icons.travel_explore,
            title: '外部浏览器打开',
            boxKey: SettingsBoxKey.openInBrowser,
            defaultValue: false,
          ),
          /*
          const SwitchItem(
            icon: Icons.feed_outlined,
            title: 'Show Square',
            boxKey: SettingsBoxKey.showSquare,
            defaultValue: true,
          ),
          */
          const SwitchItem(
            icon: Icons.history,
            title: '历史记录',
            boxKey: SettingsBoxKey.recordHistory,
            defaultValue: true,
          ),
          const SwitchItem(
            icon: Icons.emoji_emotions_outlined,
            title: '显示表情',
            boxKey: SettingsBoxKey.showEmoji,
            defaultValue: true,
          ),
          if (Platform.isAndroid)
            const SwitchItem(
              icon: Icons.system_update,
              title: '检查更新',
              boxKey: SettingsBoxKey.checkUpdate,
              defaultValue: true,
            ),
          // Others
          ListTile(
            title: Text(
              '其它',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            title: const Text('关于'),
            subtitle: Text(_version),
            leading: const Icon(Icons.all_inclusive),
            onTap: () =>
                Get.toNamed('/about', parameters: {'version': _version}),
          ),
          Obx(
            () => ListTile(
              title: const Text('清除缓存'),
              subtitle: _settingsController.cacheSize.value.isNotEmpty
                  ? Text(_settingsController.cacheSize.value)
                  : null,
              leading: const Icon(Icons.cleaning_services_outlined),
              onTap: () async {
                await _settingsController.getCacheSize();
                if (context.mounted) {
                  showDialog<void>(
                    context: context,
                    builder: (context) => ClearDialog(
                      cacheSize: _settingsController.cacheSize.value,
                      onClearCache: () async {
                        if (await CacheManage().clearCacheAll()) {
                          _settingsController.getCacheSize();
                        }
                      },
                    ),
                  );
                }
              },
            ),
          ),
          ];
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item is ItemTitle) {
                return item;
              }
              return Container(
                decoration: AppTheme.cardDecoration(brightness),
                child: item,
              );
            },
            separatorBuilder: (context, index) => const SizedBox(height: 8),
          );
        },
      ),
    );
  }
}

class SettingsController extends GetxController {
  RxString cacheSize = ''.obs;

  Future<void> getCacheSize() async {
    final res = await CacheManage().loadApplicationCache();
    cacheSize.value = res;
  }

  @override
  void onInit() {
    super.onInit();
    getCacheSize();
  }
}
