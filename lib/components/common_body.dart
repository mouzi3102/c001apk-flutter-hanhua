import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../components/footer.dart';
import '../components/item_card.dart';
import '../logic/model/feed/datum.dart';
import '../logic/state/loading_state.dart';
import '../pages/common/common_controller.dart';

/// 空态 / 错误态占位：自身可滚动，所以列表页即使加载失败也能下拉刷新
Widget _bodyState(
  String text,
  Function() onTap, {
  IconData? icon,
  String? hint,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 32.0,
                vertical: 24.0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 56,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onTap,
                    child: const Text('点击重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

Widget commonBody(
  CommonController commonController, {
  bool isHomeCard = false,
  bool isReply2Reply = false,
  dynamic uid,
}) {
  return Obx(
    () => RefreshIndicator(
      key: commonController.refreshKey,
      onRefresh: () async {
        commonController.onReset();
        await commonController.onGetData();
        // 刷新完成后恢复胶囊导航为展开态
        commonController.returnTopController?.setNavExpanded(true);
      },
      child: buildBody(
        commonController,
        isHomeCard: isHomeCard,
        isReply2Reply: isReply2Reply,
        uid: uid,
      ),
    ),
  );
}

Widget buildBody(
  CommonController commonController, {
  bool isHomeCard = false,
  bool isReply2Reply = false,
  dynamic uid,
  Function(
    dynamic id,
    dynamic uname,
    dynamic fid,
  )? onReply,
}) {
  switch (commonController.loadingState.value) {
    case Empty():
      return _bodyState(
        '暂无数据',
        () {
          commonController.isEnd = false;
          commonController.setLoadingState(LoadingState.loading());
          commonController.onGetData(true);
        },
        icon: Icons.inbox_outlined,
        hint: '下拉可刷新',
      );
    case Error():
      return _bodyState(
        (commonController.loadingState.value as Error).errMsg,
        () {
          commonController.isEnd = false;
          commonController.setLoadingState(LoadingState.loading());
          commonController.onGetData(true);
        },
        icon: Icons.wifi_off_rounded,
        hint: '下拉可重新加载',
      );
    case Success():
      var dataList = (commonController.loadingState.value as Success).response
          as List<Datum>;

      var bottomPadding = MediaQuery.of(Get.context!).padding.bottom;
      return ListView.separated(
        controller: commonController.scrollController,
        physics: AlwaysScrollableScrollPhysics(
          parent: isReply2Reply
              ? const ClampingScrollPhysics()
              : const BouncingScrollPhysics(),
        ),
        padding: isReply2Reply
            ? EdgeInsets.only(bottom: bottomPadding)
            : EdgeInsets.only(
                left: 8, top: 8, right: 8, bottom: 8 + bottomPadding),
        itemCount: dataList.length + 1,
        itemBuilder: (_, index) {
          if (index == dataList.length) {
            if (!commonController.isEnd && !commonController.isLoading) {
              commonController.setFooterState(LoadingState.loading());
              commonController.onGetData(false);
            }
            return Obx(
                () => footerWidget(commonController.footerState.value, () {
                      commonController.isEnd = false;
                      commonController.setFooterState(LoadingState.loading());
                      commonController.onGetData(false);
                    }));
          } else {
            return itemCard(
              dataList[index],
              isHomeCard: isHomeCard,
              isReply2Reply: isReply2Reply,
              isTopReply: isReply2Reply && index == 0,
              uid: uid,
              onBlock: commonController.onBlock,
              onReply: onReply,
              onDelete: commonController.postLikeDeleteFollow,
              onLike: commonController.onLike,
              onPM: commonController.onPM,
            );
          }
        },
        separatorBuilder: (_, index) => isReply2Reply
            ? const Divider(height: 1)
            : const SizedBox(height: 10),
      );
  }
  return Container(
    height: 80,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(10.0),
    child: const CircularProgressIndicator(),
  );
}
