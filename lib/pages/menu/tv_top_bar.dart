import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/tv_focus_ring.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/utils/constants.dart';

/// 电视形态的顶部导航条。
///
/// 电视上把导航放在顶部横排是通行做法：视线本来就落在画面上沿，
/// 竖排 rail 会让「先往左跳、再往下找」的移动距离变长，也不符合大部分 TV 应用。
/// 顺带把当前 tab 自己的筛选入口（推荐页的「热门番组」）收进同一条，
/// 进页面后只有一个横向焦点带，方向键横着走即可。
class TvTopBar extends StatefulWidget {
  const TvTopBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.onSearch,
    required this.onHistory,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onSearch;
  final VoidCallback onHistory;

  static const destinations = <_TvNavItem>[
    _TvNavItem('推荐', Icons.home_rounded, Icons.home_outlined),
    _TvNavItem('时间表', Icons.timeline_rounded, Icons.timeline_outlined),
    _TvNavItem('追番', Icons.favorite_rounded, Icons.favorite_border),
    _TvNavItem('我的', Icons.settings_rounded, Icons.settings_outlined),
  ];

  @override
  State<TvTopBar> createState() => TvTopBarState();
}

/// 导航条对外暴露的焦点能力。
///
/// 焦点节点必须**每个胶囊一个、且终生不换**：之前是「选中的那格用外层传进来的
/// 同一个节点」，换 tab 时这个节点会被重新挂到另一颗胶囊上，节点的祖先链当场失效，
/// 外层再判断「焦点在不在导航条里」就会得到错误答案，下键于是彻底失效。
class TvTopBarState extends State<TvTopBar> {
  late final List<FocusNode> _navNodes = List<FocusNode>.generate(
    TvTopBar.destinations.length,
    (i) => FocusNode(debugLabel: 'tv-nav-pill-$i'),
  );
  final FocusNode _searchNode = FocusNode(debugLabel: 'tv-nav-search');
  final FocusNode _historyNode = FocusNode(debugLabel: 'tv-nav-history');

  FocusNode get selectedNode => _navNodes[widget.selectedIndex];

  /// 该节点是否属于导航条。
  bool owns(FocusNode? node) {
    if (node == null) return false;
    if (node == _searchNode || node == _historyNode) return true;
    return _navNodes.contains(node);
  }

  void focusSelected() {
    if (mounted) selectedNode.requestFocus();
  }

  @override
  void dispose() {
    for (final node in _navNodes) {
      node.dispose();
    }
    _searchNode.dispose();
    _historyNode.dispose();
    super.dispose();
  }

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
            focusNode: _searchNode,
            onTap: widget.onSearch,
          ),
          const SizedBox(width: 16),
          for (var i = 0; i < TvTopBar.destinations.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _TvNavPill(
              item: TvTopBar.destinations[i],
              selected: i == widget.selectedIndex,
              focusNode: _navNodes[i],
              onTap: () => widget.onSelect(i),
            ),
          ],
          // 推荐页的「热门番组」筛选，和导航放在同一条上
          if (widget.selectedIndex == 0) ...[
            const SizedBox(width: 16),
            Container(
              width: 1,
              height: 24,
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 16),
            const _TvTagPicker(),
          ],
          const Spacer(),
          _TvIconPill(
            icon: Icons.history_rounded,
            tooltip: '历史记录',
            focusNode: _historyNode,
            onTap: widget.onHistory,
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

class _TvNavPill extends StatelessWidget {
  const _TvNavPill({
    required this.item,
    required this.selected,
    required this.focusNode,
    required this.onTap,
  });

  final _TvNavItem item;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground =
        selected ? colors.onPrimaryContainer : colors.onSurfaceVariant;
    return TvFocusRing(
      borderRadius: 22,
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: focusNode,
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 20,
                  color: foreground,
                ),
                const SizedBox(width: 8),
                Text(
                  item.label,
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
    required this.focusNode,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final FocusNode focusNode;
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
          focusNode: focusNode,
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

/// 「热门番组」标签选择。电视上用弹窗列表而不是下拉菜单：
/// 画中画菜单在遥控器上焦点容易跑飞，弹窗是一整屏内可控的焦点组。
class _TvTagPicker extends StatelessWidget {
  const _TvTagPicker();

  @override
  Widget build(BuildContext context) {
    final controller = inject<PopularController>();
    final colors = Theme.of(context).colorScheme;
    return Observer(
      builder: (_) {
        final isTrend = controller.currentTag.isEmpty;
        final label = isTrend ? '热门番组' : controller.currentTag;
        return TvFocusRing(
          borderRadius: 22,
          child: Material(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _pickTag(context, controller),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: colors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickTag(
      BuildContext context, PopularController controller) async {
    final tags = <String>['', ...defaultAnimeTags];
    final picked = await KazumiDialog.show<String>(
      context: context,
      builder: (_) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 520),
        title: const Text('选择番剧标签'),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: 420,
          height: 420,
          child: ListView.builder(
            itemCount: tags.length,
            itemBuilder: (context, index) {
              final tag = tags[index];
              final selected = tag == controller.currentTag;
              return ListTile(
                autofocus: selected,
                selected: selected,
                title: Text(tag.isEmpty ? '热门番组' : tag),
                trailing: selected
                    ? const Icon(Icons.check_rounded, size: 20)
                    : null,
                onTap: () => Navigator.of(context).pop(tag),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await controller.selectTag(picked);
  }
}
