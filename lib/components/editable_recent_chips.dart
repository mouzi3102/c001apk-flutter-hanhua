import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../../utils/storage_util.dart';
import '../../utils/utils.dart';
import 'network_image.dart';

/// 一个“常去”词条
class RecentChip {
  const RecentChip({
    required this.title,
    required this.url,
    required this.logo,
    this.custom = false,
  });

  final String title;
  final String url;
  final String logo;
  final bool custom;

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'logo': logo,
      };

  factory RecentChip.fromJson(Map<String, dynamic> json) => RecentChip(
        title: (json['title'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
        logo: (json['logo'] ?? '').toString(),
        custom: true,
      );
}

/// 首页「我的常去」词条行：长按进入编辑，词条抖动 + 右上角删除角标，
/// 可左右拖动排序，也可新增自定义词条。顺序/隐藏/自定义项存在本地 Hive。
class EditableRecentChips extends StatefulWidget {
  const EditableRecentChips({
    super.key,
    required this.items,
    this.gap = 10,
    this.storageKey = 'myRecentChips',
  });

  /// 服务端下发的词条（url 作为唯一键）
  final List<RecentChip> items;
  final double gap;
  final String storageKey;

  @override
  State<EditableRecentChips> createState() => _EditableRecentChipsState();
}

class _EditableRecentChipsState extends State<EditableRecentChips>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _editing = false;
  late final AnimationController _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  List<String> _order = <String>[];
  List<String> _hidden = <String>[];
  List<RecentChip> _custom = <RecentChip>[];

  String get _orderKey => '${widget.storageKey}_order';
  String get _hiddenKey => '${widget.storageKey}_hidden';
  String get _customKey => '${widget.storageKey}_custom';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wiggle.dispose();
    super.dispose();
  }

  /// 退到后台 / 息屏时停掉抖动动画，省掉无意义的重绘
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_editing) return;
    if (state == AppLifecycleState.resumed) {
      _wiggle.repeat(reverse: true);
    } else {
      _wiggle.stop();
    }
  }

  void _load() {
    final rawOrder = GStorage.settings.get(_orderKey, defaultValue: <String>[]);
    final rawHidden = GStorage.settings.get(_hiddenKey, defaultValue: <String>[]);
    final rawCustom = GStorage.settings.get(_customKey, defaultValue: <String>[]);
    _order = List<String>.from(rawOrder as List);
    _hidden = List<String>.from(rawHidden as List);
    _custom = (rawCustom as List)
        .map((e) => RecentChip.fromJson(
            jsonDecode(e.toString()) as Map<String, dynamic>))
        .toList();
  }

  void _save() {
    GStorage.settings.put(_orderKey, _order);
    GStorage.settings.put(_hiddenKey, _hidden);
    GStorage.settings.put(
        _customKey, _custom.map((e) => jsonEncode(e.toJson())).toList());
  }

  List<RecentChip> _visibleChips() {
    final Map<String, RecentChip> pool = <String, RecentChip>{};
    for (final c in _custom) {
      if (!_hidden.contains(c.url) && c.url.isNotEmpty) pool[c.url] = c;
    }
    for (final c in widget.items) {
      if (!_hidden.contains(c.url) && c.url.isNotEmpty) pool[c.url] = c;
    }
    final List<RecentChip> out = <RecentChip>[];
    for (final url in _order) {
      final RecentChip? c = pool.remove(url);
      if (c != null) out.add(c);
    }
    out.addAll(pool.values);
    return out;
  }

  void _enterEdit() {
    if (_editing) return;
    setState(() => _editing = true);
    _wiggle.repeat(reverse: true);
  }

  void _exitEdit() {
    if (!_editing) return;
    _wiggle.stop();
    setState(() => _editing = false);
  }

  void _remove(RecentChip chip) {
    setState(() {
      if (chip.custom) {
        _custom.removeWhere((e) => e.url == chip.url);
      } else if (!_hidden.contains(chip.url)) {
        _hidden.add(chip.url);
      }
      _order.remove(chip.url);
      _save();
    });
  }

  void _reorder(List<RecentChip> list, int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final RecentChip moved = list.removeAt(oldIndex);
      list.insert(newIndex, moved);
      _order = list.map((e) => e.url).toList();
      _save();
    });
  }

  Future<void> _showAddDialog() async {
    final TextEditingController titleCtrl = TextEditingController();
    final TextEditingController urlCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加我的常去'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: '显示名称'),
            ),
            TextField(
              controller: urlCtrl,
              decoration: InputDecoration(
                labelText: '酷安链接',
                hintText: 'https://www.coolapk.com/...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste),
                  tooltip: '粘贴',
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) urlCtrl.text = data!.text!;
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('链接支持应用/话题/用户页面地址',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final String title = titleCtrl.text.trim();
              final String url = urlCtrl.text.trim();
              if (title.isEmpty || url.isEmpty) {
                SmartDialog.showToast('名称和链接都要填');
                return;
              }
              Navigator.pop(ctx);
              setState(() {
                final RecentChip chip =
                    RecentChip(title: title, url: url, logo: '', custom: true);
                _custom.add(chip);
                _order.add(chip.url);
                _hidden.remove(url);
                _save();
              });
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    titleCtrl.dispose();
    urlCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<RecentChip> chips = _visibleChips();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    if (chips.isEmpty && !_editing) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: GestureDetector(
          onLongPress: _enterEdit,
          child: Text('还没有常去内容，长按可添加',
              style: TextStyle(fontSize: 12, color: scheme.outline)),
        ),
      );
    }

    if (!_editing) {
      return GestureDetector(
        // 长按任意词条进入编辑
        onLongPress: _enterEdit,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            itemCount: chips.length,
            separatorBuilder: (_, __) => SizedBox(width: widget.gap),
            itemBuilder: (_, index) => Center(
              child: _chip(context, chips[index], editing: false),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, right: 4),
          child: Row(
            children: [
              Expanded(
                child: Text('拖动排序，点角标删除',
                    style: TextStyle(fontSize: 12, color: scheme.outline)),
              ),
              TextButton(
                onPressed: _exitEdit,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 46,
          child: Row(
            children: [
              Expanded(
                child: ReorderableListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  // ignore: deprecated_member_use
                  onReorder: (oldIndex, newIndex) =>
                      _reorder(chips, oldIndex, newIndex),
                  proxyDecorator: (child, index, animation) => Material(
                    color: Colors.transparent,
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: child,
                  ),
                  children: [
                    for (int i = 0; i < chips.length; i++)
                      Padding(
                        key: ValueKey<String>(chips[i].url),
                        padding: EdgeInsets.only(
                            right: i == chips.length - 1 ? 0 : widget.gap),
                        child: Center(
                          child: _wiggleItem(i, _chip(context, chips[i],
                              editing: true)),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Center(child: _addTile(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wiggleItem(int index, Widget child) {
    return AnimatedBuilder(
      animation: _wiggle,
      builder: (_, c) {
        final double angle =
            math.sin(_wiggle.value * 2 * math.pi + index * 0.7) * 0.02;
        return Transform.rotate(angle: angle, child: c);
      },
      child: RepaintBoundary(child: child),
    );
  }

  Widget _addTile(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _showAddDialog,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: scheme.primary),
            const SizedBox(width: 2),
            Text('添加', style: TextStyle(fontSize: 12, color: scheme.primary)),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, RecentChip chip, {required bool editing}) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget core = Material(
      color: scheme.onInverseSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: editing ? null : () => Utils.onOpenLink(chip.url, chip.title),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _logo(context, chip),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  chip.title,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!editing) return core;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        core,
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => _remove(chip),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: scheme.error,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 1.5),
              ),
              child: Icon(Icons.remove, size: 12, color: scheme.onError),
            ),
          ),
        ),
      ],
    );
  }

  Widget _logo(BuildContext context, RecentChip chip) {
    if (chip.logo.isNotEmpty) {
      return clipNetworkImage(
        chip.logo,
        radius: 4,
        height: 18,
        width: 18,
        fit: BoxFit.cover,
      );
    }
    // 自定义词条没有图标：用首字画个色块
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String first = chip.title.isNotEmpty ? chip.title.substring(0, 1) : '?';
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        first,
        style: TextStyle(fontSize: 10, color: scheme.onPrimaryContainer),
      ),
    );
  }
}
