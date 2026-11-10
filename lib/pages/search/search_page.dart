import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/bean/widget/tv_focus_ring.dart';
import 'package:kazumi/bean/widget/tv_action_dialog.dart';
import 'package:kazumi/bean/widget/tv_search_field.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/app_mode.dart';
import 'package:kazumi/utils/date_time.dart';
import 'package:kazumi/utils/search_parser.dart';

part 'search_filter_sheet.dart';
part 'search_widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.controller,
    this.initialQuery = '',
  });

  final SearchPageController controller;
  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const bool _kDbg = bool.fromEnvironment('FOCUS_DEBUG');

  void _dbg(String msg) {
    if (!_kDbg) return;
    final p = FocusManager.instance.primaryFocus;
    debugPrint(
      '[SDBG] $msg primary=${p?.runtimeType}/${p?.debugLabel}'
      '/${p?.context?.widget.runtimeType}',
    );
  }

  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  // Preserve the input subtree when the header moves in or out of the scroll view.
  final _searchHeaderKey = GlobalKey();
  String? _submittedQuery;
  bool _managingHistory = false;

  /// 电视形态：每张结果卡一个独立焦点节点。列表分页、重建、上下遍历都靠它
  /// 保持「焦点跟着同一部番剧走」，不至于一刷新就掉到别处或干脆没有焦点。
  final Map<int, FocusNode> _cardNodes = {};

  /// 网格当前列数（每行几张卡），由 `_resultSlivers` 布局时写回。
  /// 「第一行」判定用它算序号，不靠读第一张卡的 rect。
  int _gridColumns = 5;

  /// 结果工具栏的两颗胶囊（排序 / 筛选），用于给网格第一行按上键搭桥。
  final FocusNode _sortFocus = FocusNode(debugLabel: 'tv-search-sort');
  final FocusNode _filterFocus = FocusNode(debugLabel: 'tv-search-filter');

  SearchPageController get _controller => widget.controller;
  bool get _hasSearched => _submittedQuery != null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadMoreOnScroll);
    _controller.loadSearchHistories();
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit(widget.initialQuery);
      });
    }
    // 电视形态不用在这里抢焦点：搜索框本身是 TvSearchField 的胶囊按钮，
    // 进页由它的 autofocus 落地，OK 才弹窗唤起系统输入法。
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    _sortFocus.dispose();
    _filterFocus.dispose();
    for (final node in _cardNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _writeInput(String value) {
    _input.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _submit(String value) async {
    final filters = SearchParser(value).toFilterState();
    final query = SearchParser.fromFilterState(filters);
    _inputFocus.unfocus();
    _dbg('after unfocus');
    _writeInput(query);
    setState(() => _submittedQuery = query);
    final request = _controller.searchBangumi(query, type: 'init');
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await request;
    if (!AppMode.isTv || !mounted) return;
    // 结果回来就把焦点送进网格：电视上「搜完直接浏览结果」是主路径，
    // 焦点停在搜索胶囊上会让下键先落到排序按钮，多按一次才到卡片。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusCardAt(0);
    });
  }

  Future<void> _applyFilters(SearchFilterState filters) =>
      _submit(SearchParser.fromFilterState(filters));

  void _loadMoreOnScroll() {
    if (!_scroll.hasClients || _scroll.position.extentAfter > 360) return;
    _loadMore();
  }

  void _loadMore() {
    final query = _submittedQuery;
    if (query == null) return;
    _dbg('loadMore items=${_controller.bangumiList.length}');
    _controller.searchBangumi(query);
  }

  List<BangumiItem> _filteredResults() {
    final watched = _controller.notShowWatchedBangumis
        ? _controller.loadWatchedBangumiIds()
        : <int>{};
    final abandoned = _controller.notShowAbandonedBangumis
        ? _controller.loadAbandonedBangumiIds()
        : <int>{};
    return _controller.bangumiList
        .where(
          (item) => !watched.contains(item.id) && !abandoned.contains(item.id),
        )
        .toList();
  }

  FocusNode _cardNode(BangumiItem item) => _cardNodes.putIfAbsent(
    item.id,
    () => FocusNode(debugLabel: 'search-result:${item.id}'),
  );

  /// 焦点节点是否真的还挂在控件树上。
  ///
  /// `FocusNode.detach()` 不会清空 `context`，只看 `context != null` 会踩空指针：
  /// `rect` 内部是 `context!.findRenderObject()!`，控件已被回收时直接抛。
  bool _isNodeAlive(FocusNode? node) {
    final ctx = node?.context;
    return ctx != null && ctx.mounted;
  }

  bool _focusCardAt(int index) {
    final items = _filteredResults();
    if (index < 0 || index >= items.length) return false;
    final node = _cardNode(items[index]);
    if (!_isNodeAlive(node)) return false;
    node.requestFocus();
    return true;
  }

  /// 焦点是否还在搜索框那一行（工具栏上方）。
  bool _isAboveToolbar(FocusNode node) {
    if (!_isNodeAlive(node) || !_isNodeAlive(_sortFocus)) return false;
    try {
      return node.rect.bottom <= _sortFocus.rect.top + 2;
    } catch (_) {
      return false;
    }
  }

  /// 焦点是否在第一行结果卡上——按序号判定（index < 列数）。
  ///
  /// 不能拿第一张卡片的 rect 当基准：网格是懒构建的，滚到很下面时第一张卡
  /// 早就被回收了，读它的 `rect` 会在按键处理第一行抛异常，
  /// 于是整个 ↑ 分支静默中断，表现就是「往下选了很多张之后按 ↑ 上不去」。
  bool _isFirstRowCard(FocusNode node) {
    final items = _filteredResults();
    final limit = math.min(items.length, _gridColumns);
    for (var i = 0; i < limit; i++) {
      if (identical(_cardNodes[items[i].id], node)) return true;
    }
    return false;
  }

  /// 电视形态的页内按键：补齐「工具栏 ⇄ 网格」这一段。
  ///
  /// 默认方向遍历在这页很难用：第一行按上会一路窜到 AppBar 的返回箭头
  /// （那个白框在左上角，用户会当成「焦点框丢了」），结果还没回来时按 ↓
  /// 又没有任何候选。所以两条边界自己搭。
  KeyEventResult _handleTvKeys(FocusNode node, KeyEvent event) {
    if (!AppMode.isTv) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_hasSearched) return KeyEventResult.ignored;
    // 兜底：这里一旦抛异常，KeyEventResult 就返回不了，方向键会静默失效。
    // 出任何问题都退回默认遍历，绝不让按键变哑。
    try {
      return _handleTvKeysInner(event);
    } catch (e) {
      _dbg('key handler failed: $e');
      return KeyEventResult.ignored;
    }
  }

  KeyEventResult _handleTvKeysInner(KeyEvent event) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        (identical(primary, _sortFocus) ||
            identical(primary, _filterFocus) ||
            _isAboveToolbar(primary))) {
      if (_focusCardAt(0)) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        _isFirstRowCard(primary)) {
      _sortFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _showSortPicker() async {
    final current = SearchParser(
      _submittedQuery ?? _input.text,
    ).toFilterState();
    final picked = await showTvActionDialog<String>(
      context,
      title: '排序方式',
      entries: [
        for (final entry in _searchSortLabels.entries)
          TvActionEntry(
            value: entry.key,
            label: '按${entry.value}排序',
            icon: entry.key == current.sort
                ? Icons.check_circle_rounded
                : Icons.circle_outlined,
          ),
      ],
    );
    if (!mounted || picked == null || picked == current.sort) return;
    await _applyFilters(current.copyWith(sort: picked));
  }

  /// 电视形态的结果工具栏：计数 + 排序 + 筛选，固定在搜索框下面。
  Widget _tvToolbar() {
    return Observer(
      builder: (_) {
        final items = _filteredResults();
        final busy = _controller.isLoading;
        final current = SearchParser(_submittedQuery ?? '').toFilterState();
        return Padding(
          padding: const EdgeInsets.only(top: 0, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  busy ? '正在搜索…' : '${items.length} 部番剧',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              _SearchToolbarPill(
                icon: Icons.swap_vert_rounded,
                label: '按${_sortLabel(current.sort)}',
                focusNode: _sortFocus,
                onTap: _showSortPicker,
              ),
              const SizedBox(width: 10),
              _SearchToolbarPill(
                icon: Icons.tune_rounded,
                label: '筛选',
                focusNode: _filterFocus,
                onTap: _showFilters,
                highlighted:
                    current.hasAdvancedFilters ||
                    _controller.notShowWatchedBangumis ||
                    _controller.notShowAbandonedBangumis,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showFilters() async {
    _inputFocus.unfocus();
    final result = await showAdaptiveBottomSheet<_SearchFilterResult>(
      context: context,
      maxHeightFactor: 0.9,
      builder: (_) => _SearchFilterSheet(
        initialState: SearchParser(_input.text).toFilterState(),
        initialNotShowWatched: _controller.notShowWatchedBangumis,
        initialNotShowAbandoned: _controller.notShowAbandonedBangumis,
      ),
    );
    if (!mounted || result == null) return;
    await _controller.setNotShowWatchedBangumis(result.notShowWatched);
    await _controller.setNotShowAbandonedBangumis(result.notShowAbandoned);
    if (!mounted) return;
    await _applyFilters(result.filterState);
  }

  Future<void> _imageSearch() async {
    _inputFocus.unfocus();
    final result = await context.pushNamed('/search/image');
    if (!mounted || result is! String || result.isEmpty) return;
    await _submit(result);
  }

  void _clearSearch() {
    _inputFocus.unfocus();
    _writeInput('');
    setState(() {
      _submittedQuery = null;
      _managingHistory = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _searchField() {
    final colors = Theme.of(context).colorScheme;
    if (AppMode.isTv) {
      // 电视上不能放真输入框：方向键会被 EditableText 当光标移动吃掉，
      // 焦点出不去。胶囊按钮 + 弹窗输入，方向键照常遍历。
      return Row(
        children: [
          Expanded(
            child: TvSearchField(
              controller: _input,
              hint: '搜索番剧名称',
              dialogTitle: '搜索番剧',
              autofocus: true,
              minHeight: 52,
              dense: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: _submit,
            ),
          ),
          const SizedBox(width: 12),
          TvFocusRing(
            borderRadius: 16,
            child: Material(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                tooltip: '以图搜番',
                onPressed: _imageSearch,
                icon: const Icon(Icons.image_search_rounded),
                padding: const EdgeInsets.all(20),
              ),
            ),
          ),
        ],
      );
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _input,
      builder: (context, value, child) => SearchBar(
        controller: _input,
        focusNode: _inputFocus,
        hintText: '搜索番剧名称',
        textInputAction: TextInputAction.search,
        constraints: const BoxConstraints(minHeight: 64),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
        leading: IconButton(
          tooltip: '搜索',
          onPressed: () => _submit(_input.text),
          icon: const Icon(Icons.search_rounded),
        ),
        trailing: [
          if (value.text.isNotEmpty || _hasSearched)
            IconButton(
              tooltip: '清空搜索',
              onPressed: _clearSearch,
              icon: const Icon(Icons.close_rounded),
            ),
          IconButton(
            tooltip: '以图搜番',
            onPressed: _imageSearch,
            icon: const Icon(Icons.image_search_rounded),
          ),
        ],
        onSubmitted: _submit,
      ),
    );
  }

  Widget _header() => Padding(
    key: _searchHeaderKey,
    padding: EdgeInsets.only(
      top: _hasSearched ? 10 : 24,
      bottom: _hasSearched ? 8 : 16,
    ),
    child: _searchField(),
  );

  Widget _discovery() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          type: MaterialType.transparency,
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: const Icon(Icons.tune_rounded),
            title: const Text('按条件查找'),
            subtitle: const Text('题材、放送时间与评分'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showFilters,
          ),
        ),
        const SizedBox(height: 28),
        Observer(
          builder: (_) {
            final histories = _controller.searchHistories.toList();
            if (histories.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '最近搜索',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (_managingHistory)
                        TextButton(
                          onPressed: () async {
                            await _controller.clearSearchHistory();
                            if (mounted) {
                              setState(() => _managingHistory = false);
                            }
                          },
                          child: const Text('清空'),
                        ),
                      TextButton(
                        onPressed: () => setState(
                          () => _managingHistory = !_managingHistory,
                        ),
                        child: Text(_managingHistory ? '完成' : '管理'),
                      ),
                    ],
                  ),
                ),
                for (final history in histories.take(10))
                  Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      leading: Icon(
                        Icons.history_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                        size: 22,
                      ),
                      title: Text(
                        _readableQuery(history.keyword),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: _managingHistory
                          ? IconButton(
                              tooltip: '删除这条搜索记录',
                              onPressed: () =>
                                  _controller.deleteSearchHistory(history),
                              icon: const Icon(Icons.close_rounded, size: 20),
                            )
                          : Icon(
                              Icons.north_west_rounded,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                      onTap: () => _submit(history.keyword),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<Widget> _resultSlivers(
    double width, {
    bool withHeader = true,
    double? viewportHeight,
  }) {
    final allItems = _controller.bangumiList.toList();
    final items = _filteredResults();
    // 电视形态和主页一样 6 列；行高按可视高度算成「两行整 + 半行」，
    // 让下面永远露出一点内容，同时每屏能看满两排。
    const tvColumns = 6;
    _gridColumns = AppMode.isTv
        ? tvColumns
        : math.max(2, (width / 180).floor());
    // 2.1 行：两行整卡 + 底下露出一点点，再往下就要把封面压扁了
    // （6 列时卡片只有 176 宽，行高再小封面就变成横条）。
    final double? tvRowExtent = AppMode.isTv && viewportHeight != null
        ? math.max(0, (viewportHeight - 2 * 20) / 2.05)
        : null;
    final busy = _controller.isLoading;
    final failed = _controller.isTimeOut;
    final submitted = SearchParser(_submittedQuery!).toFilterState();
    final summary = _filterSummary(submitted);

    return [
      if (withHeader)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '搜索结果',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (!submitted.isIdSearch)
                      _SearchSortMenu(
                        value: submitted.sort,
                        onChanged: (sort) =>
                            _applyFilters(submitted.copyWith(sort: sort)),
                      ),
                    IconButton(
                      tooltip: '筛选番剧',
                      onPressed: _showFilters,
                      icon: Badge(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        isLabelVisible:
                            submitted.hasAdvancedFilters ||
                            _controller.notShowWatchedBangumis ||
                            _controller.notShowAbandonedBangumis,
                        smallSize: 6,
                        child: const Icon(Icons.tune_rounded),
                      ),
                    ),
                  ],
                ),
                Text(
                  busy
                      ? '正在搜索…'
                      : '${items.length} 部番剧${items.length < allItems.length ? ' · 隐藏 ${allItems.length - items.length} 部' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      if (busy && allItems.isEmpty)
        const SliverToBoxAdapter(child: _SearchLoadingState())
      else if (allItems.isEmpty)
        const SliverToBoxAdapter(
          child: GeneralEmptyState(
            icon: Icons.search_off_rounded,
            title: '没有找到番剧',
          ),
        )
      else if (items.isEmpty)
        SliverToBoxAdapter(
          child: GeneralEmptyState(
            icon: Icons.filter_alt_off_rounded,
            title: '这些番剧被筛选隐藏了',
            actions: [
              StateActionButton.tonal(
                onPressed: () async {
                  await _controller.setNotShowWatchedBangumis(false);
                  await _controller.setNotShowAbandonedBangumis(false);
                },
                icon: Icons.visibility_outlined,
                text: '显示全部',
              ),
            ],
          ),
        )
      else
        _SearchResultGrid(
          items: items,
          width: width,
          showRating: GStorage.getSetting(SettingsKeys.showRating),
          focusNodeFor: _cardNode,
          columns: AppMode.isTv ? tvColumns : null,
          rowExtent: tvRowExtent,
        ),
      // 电视形态不放「加载更多」按钮：滚到底自动续拉，
      // 按钮本身还成了「一按就消失的焦点目标」（加载中它被换成指示器）。
      if (AppMode.isTv)
        if (allItems.isNotEmpty && !busy && !_controller.hasMoreSearchResults)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '已经看到全部结果',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )
        else if (allItems.isNotEmpty || !failed)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: busy
                    ? (allItems.isEmpty
                          ? const SizedBox.shrink()
                          : const LoadingIndicator(size: 32))
                    : _controller.hasMoreSearchResults
                    ? TextButton.icon(
                        onPressed: _loadMore,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('加载更多'),
                      )
                    : Text(
                        '已经看到全部结果',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 电视出结果后不要顶部标题栏：那一条「番剧搜索 + 返回箭头」白占
      // 五十多像素，网格被压得只剩两行半还特别扁。返回用遥控器 BACK 键。
      appBar: AppMode.isTv && _hasSearched
          ? null
          : const SysAppBar(
              backgroundColor: Colors.transparent,
              title: Text('番剧搜索'),
            ),
      body: SafeArea(
        top: false,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _handleTvKeys,
          onFocusChange: (f) => _dbg('page focusChange=$f'),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = constraints.maxWidth >= 700 ? 32.0 : 20.0;
              final width = math.min(
                _hasSearched ? 1120.0 : 760.0,
                constraints.maxWidth - horizontal * 2,
              );
              final inset = (constraints.maxWidth - width) / 2;
              final pinSearch =
                  _hasSearched &&
                  constraints.maxHeight >= 420 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 24;
              Widget scrollView(List<Widget> slivers) => CustomScrollView(
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, 0, inset, 24),
                    sliver: SliverMainAxisGroup(slivers: slivers),
                  ),
                ],
              );
              // 电视形态的结果页：搜索框和结果工具栏都固定，只有网格滚动。
              // 纵向顺序因此永远确定——搜索框 → 工具栏 → 网格，
              // 遥控器不会因为「滚到哪儿了」而落到别的地方去。
              if (AppMode.isTv && _hasSearched) {
                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      child: _header(),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      child: _tvToolbar(),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (_, gridBox) => Observer(
                          builder: (_) => scrollView(
                            _resultSlivers(
                              width,
                              withHeader: false,
                              viewportHeight: gridBox.maxHeight,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  if (pinSearch)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      child: _header(),
                    ),
                  Expanded(
                    child: _hasSearched
                        ? Observer(
                            builder: (_) => scrollView([
                              if (!pinSearch)
                                SliverToBoxAdapter(child: _header()),
                              ..._resultSlivers(width),
                            ]),
                          )
                        : scrollView([
                            SliverToBoxAdapter(child: _header()),
                            SliverToBoxAdapter(child: _discovery()),
                          ]),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
