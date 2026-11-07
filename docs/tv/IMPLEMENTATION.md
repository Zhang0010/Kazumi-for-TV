# Kazumi for TV —— 实现进度（v1.1 落地）

对应设计稿：`docs/tv/DESIGN.md` v1.1。本文记录「已实现 / 已验证 / 待补」，避免设计和代码走散。

## 一、已实现

### 形态判定
- `lib/utils/app_mode.dart`：`AppMode.isTv`
  - 优先级：`--dart-define=KAZUMI_TV=true` → 设置项 `interfaceMode` → 平台通道探测
  - 探测口径：`LEANBACK` 特性 / `UiMode=TELEVISION` / 无触摸屏，三者取或
  - 兜底：通道缺失或异常一律按手机形态处理
- `MainActivity.kt`：`com.predidit.kazumi/intent` 通道新增 `isTvDevice`
- 设置 → 界面设置 → 显示形态 → 界面模式（自动 / 电视 / 手机，重启生效）
- TV 形态启动：强制横屏 + `immersiveSticky`

### Android 清单
- `LEANBACK_LAUNCHER` 入口类别（电视桌面显示图标）
- `android:banner`：`drawable-xhdpi/tv_banner.png` 320×180、`drawable-xxhdpi` 480×270
- `android.software.leanback` 与 `android.hardware.touchscreen` 均 `required=false`
- **minSdk 保持 24，`build.gradle` 未改动**

### 焦点体系
- `MaterialApp.builder` 在 TV 形态注入 `MediaQuery.navigationMode = traditional`
  （这是 InkWell / 按钮出现焦点高亮的前提），同时关掉 splash 与 hover
- `lib/bean/widget/tv_focus_ring.dart`：3px 白框 + 1.05 缩放 + `ensureVisible` 滚动跟随，
  非 TV 形态直接返回 child，零额外节点
- 已套用：番剧卡片（`BangumiCardV`）
- 左 rail：数字键 1–4 直接切 tab（推荐 / 时间表 / 追番 / 我的）

### 播放器（电视）
- `lib/pages/player/tv/player_tv_osd.dart` 独立 OSD，TV 形态下替换原 `PlayerItemPanel`
- 键位（`PlayerTvOsd._handleKeyEvent`）：
  - OSD 隐藏：`OK` 播放/暂停，长按 `OK`（550ms）选集抽屉，`←/→` ±`arrowKeySkipTime`，`↑/↓` 呼出 OSD 并落焦点
  - OSD 显示：方向键走焦点遍历；`BACK` 先收 OSD，再退播放页；进度条聚焦时 `←/→` 直接 seek
  - `MENU`：选集抽屉；`媒体播放/上一集/下一集` 键直通
- OSD 组件：顶部（返回 / 标题 / 选集 / 弹幕 / 全屏 / 倍速 / 跳过片头），底部（播放暂停 / 上一集 / 下一集 / 可聚焦进度条 / 时间），居中 HUD（seek 提示、播放暂停图标闪烁）
- 倍速：弹窗列表（`defaultPlaySpeedList`），OK 选中，BACK 关闭
- 选集抽屉：线路 chips + 集数网格，当前集高亮并自动聚焦，OK 切集后自动关闭
- 触摸清理（TV 形态下这些子树根本不挂载）：
  - `player_item.dart`：`Listener.onPointerSignal`（滚轮）直接返回、`GestureDetector`（单击/双击/长按倍速）、`PlayerGestureDetector`（横向 seek / 竖向亮度音量）、`PlayerKeyboardShortcuts`
  - 原 OSD 面板 `PlayerItemPanel` 在 TV 下不构建

### 搜索
- TV 形态进页即聚焦搜索框，OK 调起系统默认输入法（不自绘键盘）

## 二、已在 Android TV 上验证（AVD `kazumi_tv`，API 34，1920×1080，arm64）

| 验证点 | 结果 |
| --- | --- |
| 安装 + 启动（`am start` / LEANBACK 入口存在） | 通过，无崩溃、无 `E/flutter` |
| 引导页 4 步可完成 | 通过（OK 键与触摸均可推进） |
| 主界面为 TV 形态（左 rail + 卡片网格，非底部 tab） | 通过 |
| 卡片焦点框（白边 + 放大）出现并可移动 | 通过 |
| 数字键 1–4 切 tab（4 → 我的） | 通过 |
| 弹窗 / 设置页方向键可达、OK 可激活 | 通过 |
| BACK 逐级返回 | 通过 |

**未能在模拟器上运行时验证**：播放器 OSD 全流程。
原因：模拟器网络无法访问番剧源与图床（截图里封面普遍 404、TLS 握手被重置），装规则 / 取流都会失败，
失败原因无法与代码问题区分。播放器留给真机（海信投影）验收。

## 三、待补（P2/P3）

1. TV OSD 里还没有入口：**画面比例 / 超分辨率 / 锁屏 / 截图 / 播放信息 / 弹幕样式**（原面板里有，TV 面板未接）
2. 弹幕发送、同步播放面板未接 TV
3. 首页卡片只包了 `BangumiCardV`；时间表卡片、追番卡片仍靠全局焦点色，没有白框 + 缩放
4. 设置页列表在 TV 下的焦点可见度尚未逐页核对
5. `playerController.panel.lockPanel` 在 TV 下没有入口（锁屏后 OSD 不可呼出）
