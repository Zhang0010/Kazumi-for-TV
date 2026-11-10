import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/pages/popular/popular_tv_tag_bar.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/platform/desktop_window_config.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/app_mode.dart';

class PopularPage extends StatefulWidget {
  const PopularPage({super.key, required this.controller});

  final PopularController controller;

  @override
  State<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends State<PopularPage> {
  late final ScrollController scrollController;
  PopularController get popularController => widget.controller;

  /// 右下角「快速回顶」按钮的焦点节点：网格走到最右一列再按右键就落到它上面。
  final FocusNode _backToTopFocus = FocusNode(
    debugLabel: 'popular-back-to-top',
  );

  /// 电视形态：类型条，外壳需要把焦点精确送回「当前那一颗」。
  final GlobalKey<TvTagBarState> _tagBarKey = GlobalKey<TvTagBarState>();

  /// 每张海报一个独立焦点节点：下键要能确定地落到第一张，
  /// 而不是靠方向遍历在懒构建的网格里猜。
  final Map<int, FocusNode> _cardNodes = {};

  /// 用户按过 ↓ 但网格还在拉取：等列表回来再兑现这次下键。
  bool _pendingDescent = false;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      initialScrollOffset: popularController.scrollOffset,
    );
    scrollController.addListener(scrollListener);
    if (popularController.trendList.isEmpty) {
      popularController.queryBangumiByTrend();
    }
  }

  @override
  void dispose() {
    scrollController.removeListener(scrollListener);
    scrollController.dispose();
    _backToTopFocus.dispose();
    for (final node in _cardNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// 电视形态的页内按键：只补两条「默认遍历做不到」的桥。
  ///
  /// 「类型条 ⇄ 网格」这一段必须自己搭：网格是 Sliver 懒构建的，
  /// 一行都还没布局出来时（刚换类型、列表还在拉）方向遍历找不到任何候选，
  /// 按 ↓ 就原地不动 —— 这正是「选完类型焦点下不去」的来源。
  /// 其余方向一律放行给默认遍历和外层外壳（导航条那条桥在外壳里）。
  KeyEventResult _handleTvKeys(FocusNode node, KeyEvent event) {
    if (!AppMode.isTv) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || !_isFirstRowCard(primary)) {
      return KeyEventResult.ignored;
    }
    // 网格第一行按上：回到类型条当前选中的那一颗。
    _tagBarKey.currentState?.focusCurrent();
    return KeyEventResult.handled;
  }

  /// 焦点是否在网格第一行某张卡上（按列数判断，不看 y 坐标——
  /// 卡片用了 1.07 缩放，坐标会随焦点状态跳）。
  bool _isFirstRowCard(FocusNode node) {
    final list = _currentList;
    for (var i = 0; i < list.length && i < _crossCount; i++) {
      if (identical(_cardNodes[list[i].id], node)) return true;
    }
    return false;
  }

  /// ↓ 进网格：有卡片就落第一张；没有（还在拉取）就记住，等它出来再落。
  void _descendToGrid() {
    if (_focusCardAt(0)) return;
    _pendingDescent = true;
  }

  bool _focusCardAt(int index) {
    final list = _currentList;
    if (index < 0 || index >= list.length) return false;
    final node = _cardNode(list[index]);
    // 还没挂到树上（被 Sliver 回收 / 还没布局）时 requestFocus 是空操作，
    // 直接说没落上，交给调用方重试。
    if (node.context == null || !node.canRequestFocus) return false;
    node.requestFocus();
    return true;
  }

  /// 数据回来之后兑现「用户刚才按过 ↓」。
  void _consumePendingDescent(List<BangumiItem> list) {
    if (!_pendingDescent || list.isEmpty) return;
    _pendingDescent = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusCardAt(0);
    });
  }

  /// 电视形态下当前要显示的列表（热门 / 指定类型）。
  List<BangumiItem> get _currentList => popularController.currentTag.isEmpty
      ? popularController.trendList
      : popularController.bangumiList;

  int get _crossCount {
    final width = MediaQuery.sizeOf(context).width;
    if (width > LayoutBreakpoint.medium['width']!) return 6;
    if (width > LayoutBreakpoint.compact['width']!) return 5;
    return 3;
  }

  FocusNode _cardNode(BangumiItem item) => _cardNodes.putIfAbsent(
    item.id,
    () => FocusNode(debugLabel: 'tv-popular-card:${item.id}'),
  );

  void scrollListener() {
    popularController.scrollOffset = scrollController.offset;
    if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 200 &&
        !popularController.isLoadingMore) {
      KazumiLogger().i(
        'PopularPageController: Fetching next recommendation batch',
      );
      if (popularController.currentTag != '') {
        popularController.queryBangumiByTag();
      } else {
        popularController.queryBangumiByTrend();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleTvKeys,
        child: AppMode.isTv
            ? Column(
                children: [
                  // 类型条常驻页顶：电视上「换类型」是高频动作，不该藏在弹窗里。
                  Observer(builder: (_) => _buildTagBar()),
                  Expanded(child: _buildContent()),
                ],
              )
            : _buildContent(),
      ),
      floatingActionButton: _buildBackToTop(),
    );
  }

  /// 电视形态的番剧类型条。选择逻辑仍然是 PopularController.selectTag，
  /// 这里只负责「类型条在页顶、下键能进网格」。
  Widget _buildTagBar() => TvTagBar(
    key: _tagBarKey,
    tags: ['', ...defaultAnimeTags],
    currentTag: popularController.currentTag,
    onSelect: _selectTag,
    onDown: _descendToGrid,
  );

  Widget _buildBackToTop() {
    // 电视上这颗「回到顶部」不参与焦点：它在右下角，一旦焦点落到这里，
    // 下键/右键就全都没反应了（下面和右边都没东西）。
    return ExcludeFocus(
      excluding: AppMode.isTv,
      child: FloatingActionButton(
        focusNode: _backToTopFocus,
        onPressed: () => scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        ),
        child: const Icon(Icons.arrow_upward),
      ),
    );
  }

  Widget _buildContent() {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        // 电视形态的标题与类型筛选已经在页顶（类型条），
        // 这里不再重复一层 120px 的展开标题。
        if (!AppMode.isTv) buildSliverAppBar(),
        SliverToBoxAdapter(
          child: Observer(
            builder: (_) => AnimatedOpacity(
              opacity: popularController.isLoadingMore ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: popularController.isLoadingMore
                  ? const LinearProgressIndicator(minHeight: 4)
                  : const SizedBox(height: 4),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            StyleString.cardSpace,
            0,
            StyleString.cardSpace,
            0,
          ),
          sliver: Observer(
            builder: (_) {
              if (popularController.isTimeOut) {
                return SliverToBoxAdapter(
                  child: SizedBox(
                    height: 400,
                    child: BangumiMirrorErrorWidget(
                      onRetry: () {
                        if (popularController.trendList.isEmpty) {
                          popularController.queryBangumiByTrend();
                        } else {
                          popularController.queryBangumiByTag();
                        }
                      },
                      onSettingsReturned: () {
                        if (mounted) {
                          setState(() {});
                        }
                      },
                    ),
                  ),
                );
              }
              final list = _currentList;
              // 用户按过 ↓ 但当时还没有卡片：数据一回来就把焦点送下去。
              _consumePendingDescent(list);
              return contentGrid(list);
            },
          ),
        ),
        // 换类型之后列表还在拉取：给一个明确的「正在加载」，
        // 而不是留一屏空白（空网格会让人以为方向键彻底失灵）。
        if (AppMode.isTv)
          SliverToBoxAdapter(
            child: Observer(
              builder: (_) =>
                  AppMode.isTv &&
                      _currentList.isEmpty &&
                      popularController.isLoadingMore
                  ? const Padding(
                      padding: EdgeInsets.only(top: 120),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }

  Widget contentGrid(List<BangumiItem> bangumiList) {
    final crossCount = _crossCount;
    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          // 行间距
          mainAxisSpacing: StyleString.cardSpace - 2,
          // 列间距
          crossAxisSpacing: StyleString.cardSpace,
          // 列数
          crossAxisCount: crossCount,
          mainAxisExtent:
              MediaQuery.of(context).size.width / crossCount / 0.65 +
              MediaQuery.textScalerOf(context).scale(32.0),
        ),
        delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
          return bangumiList.isNotEmpty
              // 每张卡单独成层：焦点框缩放 / 图片淡入只重绘这一格，
              // 不带着整个网格一起重绘（弱 GPU 上滚动掉帧的主要来源）。
              ? RepaintBoundary(
                  child: BangumiCardV(
                    bangumiItem: bangumiList[index],
                    focusNode: _cardNode(bangumiList[index]),
                  ),
                )
              : null;
        }, childCount: bangumiList.isNotEmpty ? bangumiList.length : 10),
      ),
    );
  }

  Widget buildSliverAppBar() {
    final theme = Theme.of(context);
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 120,
      elevation: 0,
      titleSpacing: 0,
      centerTitle: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      actions: buildActions(),
      title: null,
      flexibleSpace: SafeArea(
        child: dtb.DragToMoveArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double maxExtent = 120 - MediaQuery.of(context).padding.top;
              final t =
                  (1 -
                  ((constraints.maxHeight - kToolbarHeight) /
                          (maxExtent - kToolbarHeight))
                      .clamp(0.0, 1.0));
              // 字重收缩后为 w500，展开时为 w700
              final fontWeight = t < 0.5 ? FontWeight.w700 : FontWeight.w500;
              final fontSize = lerpDouble(28, 20, t)!;
              return Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    top: 8,
                    bottom: 8,
                    right: 60,
                  ),
                  child: SizedBox(
                    height: 44,
                    child: Observer(
                      builder: (_) {
                        final bool isTrend = popularController.currentTag == '';
                        return KazumiMenuButton(
                          animated: true,
                          style: const MenuStyle(
                            maximumSize: WidgetStatePropertyAll(Size(240, 350)),
                          ),
                          menuChildren: [
                            for (final tag in ['', ...defaultAnimeTags])
                              KazumiMenuItem(
                                label: tag.isEmpty ? '热门番组' : tag,
                                selected: tag == popularController.currentTag,
                                onPressed: () => _selectTag(tag),
                              ),
                          ],
                          builder: (context, toggle) => InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: toggle,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isTrend
                                      ? '热门番组'
                                      : popularController.currentTag,
                                  style: theme.textTheme.headlineMedium!
                                      .copyWith(
                                        fontWeight: fontWeight,
                                        fontSize: fontSize,
                                      ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.keyboard_arrow_down,
                                  size: fontSize,
                                  color: theme.iconTheme.color,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> buildActions() {
    return <Widget>[
      if (MediaQuery.of(context).orientation == Orientation.portrait)
        IconButton(
          tooltip: '搜索',
          onPressed: () => context.pushNamed('/search/'),
          icon: const Icon(Icons.search),
        ),
      IconButton(
        tooltip: '历史记录',
        onPressed: () => context.pushNamed('/settings/history/'),
        icon: const Icon(Icons.history),
      ),
      if (isDesktop() && !DesktopWindowConfig.showWindowButton)
        IconButton(
          tooltip: '退出',
          onPressed: () => windowManager.close(),
          icon: const Icon(Icons.close),
        ),
    ];
  }

  Future<void> _selectTag(String selected) async {
    if (!mounted || selected == popularController.currentTag) return;
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    await popularController.selectTag(selected);
  }
}
