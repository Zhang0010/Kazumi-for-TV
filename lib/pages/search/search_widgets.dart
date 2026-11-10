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
  });

  final List<BangumiItem> items;
  final double width;
  final bool showRating;

  /// 电视形态由页面统一持有每张卡的焦点节点（按番剧 id），
  /// 分页 / 重排之后焦点仍然落在同一部番剧上，不会掉到别处或消失。
  final FocusNode Function(BangumiItem item)? focusNodeFor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final titleStyle = textTheme.titleSmall!.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.4,
    );

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
      _SearchResultCard.ratingIconSize,
      textHeight('0.0 0000', textTheme.labelMedium!),
    );
    final columns = math.max(2, (width / 180).floor());
    final cardWidth = (width - (columns - 1) * 12) / columns;

    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 20,
        mainAxisExtent:
            cardWidth / _SearchResultCard.coverAspectRatio +
            titleHeight +
            metadataHeight +
            _SearchResultCard.titleSpacing +
            _SearchResultCard.metadataSpacing +
            6,
      ),
      itemCount: items.length,
      itemBuilder: (_, index) => _SearchResultCard(
        item: items[index],
        showRating: showRating,
        titleHeight: titleHeight,
        titleStyle: titleStyle,
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
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    final year = item.airDate.length >= 4 ? item.airDate.substring(0, 4) : '';
    // 包一层 TvFocusRing：焦点框由卡片自己画（手机形态是零开销直通），
    // 不再依赖全局指示层那圈通用描边。
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
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: coverAspectRatio,
                  child: LayoutBuilder(
                    builder: (_, constraints) => NetworkImgLayer(
                      src: item.images['large'] ?? item.images['common'] ?? '',
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: titleSpacing),
              SizedBox(
                height: titleHeight,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              const SizedBox(height: metadataSpacing),
              Row(
                children: [
                  if (showRating && item.ratingScore > 0) ...[
                    Icon(
                      Icons.star_rounded,
                      size: ratingIconSize,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      item.ratingScore.toStringAsFixed(1),
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      year,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: highlighted
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
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
