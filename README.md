# c001apk-flutter

A new Flutter project.

## 版本 / Releases

- 最新：**16.8.2（versionCode 90）**，APK 见 [`releases/c001apk-flutter-16.8.2.apk`](releases/c001apk-flutter-16.8.2.apk)
- 16.8.2：补全中文本地化，文本选择菜单（复制/分享/全选）不再显示英文
- 16.8.1：长按帖子/评论的查看页表情显示成图片、排版改为左对齐限宽；编辑态抖动在后台暂停、表情图按物理像素解码降功耗
- 16.8.0：首页「我的常去」词条支持长按编辑：抖动动画 + 删除角标 + 拖动排序 + 自定义添加，顺序/删除/新增存本地
- 16.7.7：私信输入框表情改为图片占位（不再露出 [xx] 字面）；下拉刷新时丢弃在途的旧分页，通知列表按时间倒序，避免刷出几天前的回复
- 16.7.6：整页加载圆环改为贴顶显示，不再居中后跳到顶部
- 16.7.5：下拉刷新圆环不再浮在文字上（刷新时列表整体让出一条顶部空档）
- 16.7.4：统一顶部加载动画为纯圆弧细指示器并缩小尺寸（下拉刷新去掉白底药丸与阴影）
- 16.7.3：外部链接提示框不再显示原始 URL（超长 snssdk schema 会撑满屏幕）
- 16.7.2：修复网页「打开外部链接」提示不消失（改为模态对话框，点按钮即关闭）
- 16.7.0：修复回帖输入框插入表情后再打字被拆成文字、退格删不掉的问题
- 16.7.1：浏览历史支持 WebDAV 双向同步（每次进入历史记录页自动同步，支持删除/清空同步）

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Credits:
- [pilipala](https://github.com/guozhigq/pilipala)