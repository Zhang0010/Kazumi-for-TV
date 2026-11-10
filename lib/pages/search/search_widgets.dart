part of 'search_page.dart';

const _searchSortLabels = {
  'heat': '热度',
  'rank': '排名',
  'score': '评分',
  'match': '匹配',
};

String _sortLabel(String sort) => _searchSortLabels[sort] ?? '热度';

String _filterSummary(SearchFilterState state) => [
  ...state.tags,
  if (state.season.isNotEmpty) state.season,
  if (state.season.isEmpty && state.dateRange != null)
    '${state.dateRange!.start} 至 ${state.dateRange!.end}',
  if (state.scoreRange?.isValid == true) '评分 ${state.scoreRange!.toToken()}',
  if (state.rankRange?.isValid == true) '排名 ${state.rankRange!.toToken()}',
  if (state.weekdays.isNotEmpty)
    '周${state.weekdays.map((day) => '一二三四五六日'[day - 1]).join('、')}',
].join(' · ');

String _readableQuery(String query) {
  final state = SearchParser(query).toFilterState();
  final summary = _filterSummary(state);
  return [
    if (state.keyword.isNotEmpty) state.keyword,
    if (state.id.isNotEmpty) '条目 ${state.id}',
    if (summary.isNotEmpty) summary,
    if (state.sort != 'heat') '${_sortLabel(state.sort)}排序',
  ].join(' · ');
}

class _SearchSortMenu extends StatelessWidget {
  const _SearchSortMenu({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KazumiMenuButton(
      animated: true,
      menuChildren: [
        for (final sort in _searchSortLabels.entries)
          KazumiMenuItem(
            label: '按${sort.value}排序',
            selected: sort.key == value,
            onPressed: () => onChanged(sort.key),
          ),
      ],
      builder: (context, toggle) => Tooltip(
        message: '排序方式',
        child: TextButton.icon(
          onPressed: toggle,
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          label: Text(_sortLabel(value)),
        ),
      ),
    );
  }
}

class _SearchResultGrid extends StatelessWidget {
  const _SearchResultGrid({
    required this.items,
    required this.width,
    required this.showRating,
    this.focusNodeFor,
    this.columns,
    this.rowExtent,
  });

  final List<BangumiItem> items;
  final double width;
  final bool showRating;

  /// 电视形态由页面统一持有每张卡的焦点节点（按番剧 id），
  /// 分页 / 重排之后焦点仍然落在同一部番剧上，不会掉到别处或消失。
  final FocusNode Function(BangumiItem item)? focusNodeFor;

  /// 电视形态固定列数（主页是 6 列，搜索结果也用 6 列对齐）。
  final int? columns;

  /// 电视形态的固定行高：由页面按可视高度算「两行整 + 半行」，
  /// 卡片海报用 `Expanded` 吃掉剩下高度，所以行高可以小于海报原始比例。
  final double? rowExtent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // 电视形态 6 列、一屏要放下两行半，卡片被压矮了；
    // 标题和元信息跟着收一档，把高度还给封面。
    final compact = columns != null;
    final titleStyle = textTheme.titleSmall!.copyWith(
      fontWeight: FontWeight.w600,
      height: compact ? 1.18 : 1.4,
      fontSize: compact ? 13 : null,
    );
    final metaStyle = compact ? textTheme.labelSmall : textTheme.labelMedium;

    double textHeight(String text, TextStyle style) {
      // Measure with nonlinear accessibility scaling.
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout();
      final height = painter.height.ceilToDouble();
      painter.dispose();
      return height;
    }

    final titleHeight = textHeight('番剧\n番剧', titleStyle);
    final metadataHeight = math.max(
      compact ? 12.0 : _SearchResultCard.ratingIconSize,
      textHeight('0.0 0000', metaStyle!),
    );
    final crossCount = this.columns ?? math.max(2, (width / 180).floor());
    final cardWidth = (width - (crossCount - 1) * 12) / crossCount;
    final textExtent =
        titleHeight +
        metadataHeight +
        _SearchResultCard.titleSpacing +
        _SearchResultCard.metadataSpacing +
        6;
    // 没有指定行高就按海报原始比例算；指定了就以页面给的为准，
    // 但不低于「一行字 + 一张小海报」的下限，避免 Column 溢出。
    final extent = rowExtent == null
        ? cardWidth / _SearchResultCard.coverAspectRatio + textExtent
        : math.max(rowExtent!, textExtent + 84);

    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 20,
        mainAxisExtent: extent,
      ),
      itemCount: items.length,
      itemBuilder: (_, index) => _SearchResultCard(
        item: items[index],
        showRating: showRating,
        titleHeight: titleHeight,
        titleStyle: titleStyle,
        metaStyle: metaStyle,
        metaHeight: metadataHeight,
        compact: compact,
        focusNode: focusNodeFor?.call(items[index]),
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.item,
    required this.showRating,
    required this.titleHeight,
    required this.titleStyle,
    this.metaStyle,
    this.metaHeight = 16,
    this.compact = false,
    this.focusNode,
  });

  static const coverAspectRatio = 0.7;
  static const titleSpacing = 10.0;
  static const metadataSpacing = 4.0;
  static const ratingIconSize = 14.0;

  final BangumiItem item;
  final bool showRating;
  final double titleHeight;
  final TextStyle titleStyle;
  final TextStyle? metaStyle;
  final double metaHeight;
  final bool compact;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    final year = item.airDate.length >= 4 ? item.airDate.substring(0, 4) : '';
    // 包一层 TvFocusRing：焦点框由卡片自己画（手机形态是零开销直通），
    // 不再依赖全局指示层那圈通用描边。
    final meta = (metaStyle ?? theme.textTheme.labelMedium)!;
    final ratingIcon = compact ? 12.0 : ratingIconSize;
    return TvFocusRing(
      borderRadius: 16,
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          focusNode: focusNode,
          onTap: () => context.pushNamed('/info/', arguments: item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 海报吃掉行高里剩下的空间（电视形态行高是算出来的，
              // 不一定是 0.7 的原始比例），裁切交给 cover。
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LayoutBuilder(
                    builder: (_, constraints) => NetworkImgLayer(
                      src: item.images['large'] ?? item.images['common'] ?? '',
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      // 卡片被压矮时要裁竖版海报：对齐到上方，
                      // 留下人物的头脸，而不是腰。
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
              ),
              SizedBox(height: compact ? 4 : titleSpacing),
              // 标题固定在「两行」的框里、内容底部对齐：
              // 一行标题就贴在评分行上方 3px，不会因为预留的第二行空着
              // 而在标题和评分之间撑出一道大缝。
              SizedBox(
                height: titleHeight + 3 + metaHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: metaHeight,
                      child: Row(
                        children: [
                          if (showRating && item.ratingScore > 0) ...[
                            Icon(
                              Icons.star_rounded,
                              size: ratingIcon,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              item.ratingScore.toStringAsFixed(1),
                              style: meta,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              year,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: meta.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 电视形态结果工具栏上的一颗胶囊（排序 / 筛选）。
class _SearchToolbarPill extends StatelessWidget {
  const _SearchToolbarPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.focusNode,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TvFocusRing(
      borderRadius: 20,
      child: Material(
        color: highlighted
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: focusNode,
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: highlighted
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: highlighted
                        ? colors.onPrimaryContainer
                        : colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchLoadingState extends StatelessWidget {
  const _SearchLoadingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          const LoadingIndicator(size: 40),
          const SizedBox(height: 20),
          Semantics(
            liveRegion: true,
            child: Text(
              '正在搜索番剧',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}
