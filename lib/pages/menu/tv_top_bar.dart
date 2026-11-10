import 'package:flutter/material.dart';

import 'package:kazumi/bean/widget/tv_focus_ring.dart';

/// 电视形态的顶部导航条。
///
/// 电视上把导航放在顶部横排是通行做法：视线本来就落在画面上沿，
/// 竖排 rail 会让「先往左跳、再往下找」的移动距离变长，也不符合大部分 TV 应用。
/// 顺带把当前 tab 自己的筛选入口（推荐页的「热门番组」）收进同一条，
/// 进页面后只有一个横向焦点带，方向键横着走即可。
class TvTopBar extends StatelessWidget {
  const TvTopBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.onSearch,
    required this.onHistory,
    this.navFocusNode,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onSearch;
  final VoidCallback onHistory;

  /// 选中 tab 那颗胶囊使用的焦点节点，由外层持有。
  ///
  /// 外层需要靠「是不是这个节点」来判断焦点在不在导航条里；用节点身份判断，
  /// 不去查祖先链——换 tab 时这个节点会被挂到另一颗胶囊上，祖先链会失效。
  final FocusNode? navFocusNode;

  static const _destinations = <_TvNavItem>[
    _TvNavItem('推荐', Icons.home_rounded, Icons.home_outlined),
    _TvNavItem('时间表', Icons.timeline_rounded, Icons.timeline_outlined),
    _TvNavItem('追番', Icons.favorite_rounded, Icons.favorite_border),
    _TvNavItem('我的', Icons.settings_rounded, Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        children: [
          _TvIconPill(
            icon: Icons.search_rounded,
            tooltip: '搜索',
            onTap: onSearch,
          ),
          const SizedBox(width: 16),
          for (var i = 0; i < _destinations.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _TvNavPill(
              item: _destinations[i],
              selected: i == selectedIndex,
              autofocus: i == selectedIndex,
              focusNode: i == selectedIndex ? navFocusNode : null,
              onTap: () => onSelect(i),
            ),
          ],
          // 番剧类型筛选不放在这里：它是「页面级筛选」，已经做成推荐页顶上
          // 常驻的类型条（见 popular_tv_tag_bar.dart）。放在导航条里只有一个
          // 好处——少按一下下键，代价是多一层弹窗和一堆焦点回不来的问题。
          const Spacer(),
          _TvIconPill(
            icon: Icons.history_rounded,
            tooltip: '历史记录',
            onTap: onHistory,
          ),
        ],
      ),
    );
  }
}

class _TvNavItem {
  const _TvNavItem(this.label, this.selectedIcon, this.icon);

  final String label;
  final IconData selectedIcon;
  final IconData icon;
}

class _TvNavPill extends StatefulWidget {
  const _TvNavPill({
    required this.item,
    required this.selected,
    required this.autofocus,
    required this.onTap,
    this.focusNode,
  });

  final _TvNavItem item;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  State<_TvNavPill> createState() => _TvNavPillState();
}

class _TvNavPillState extends State<_TvNavPill> {
  final FocusNode _ownNode = FocusNode(debugLabel: 'tv-nav-pill');

  FocusNode get _node => widget.focusNode ?? _ownNode;

  @override
  void dispose() {
    _ownNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final foreground = selected
        ? colors.onPrimaryContainer
        : colors.onSurfaceVariant;
    return TvFocusRing(
      borderRadius: 22,
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: _node,
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(22),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? widget.item.selectedIcon : widget.item.icon,
                  size: 20,
                  color: foreground,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.item.label,
                  style: TextStyle(
                    fontSize: 16,
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

class _TvIconPill extends StatelessWidget {
  const _TvIconPill({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TvFocusRing(
      borderRadius: 22,
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 22, color: colors.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
