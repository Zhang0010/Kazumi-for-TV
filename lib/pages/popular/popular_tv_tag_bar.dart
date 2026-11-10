import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:kazumi/bean/widget/tv_focus_ring.dart';

/// 电视形态的番剧类型条（热门番组 / 日常 / 原创 / …）。
///
/// 手机上这层是标题栏里的下拉菜单，遥控器上「下拉菜单」是不可靠的控件
/// （弹层里的项能不能走焦、OK 会不会穿透都不稳定），所以电视形态把它换成
/// 常驻的一行胶囊：
///
///   顶部导航 ↓ → 类型条 → ←→ 换类型 → OK 立即生效 → ↓ 进海报网格
///
/// 好处是整个筛选动作只有一条竖线加横移，不需要弹窗、也不会出现
/// 「弹窗关掉之后焦点回不到页面、下键按不动」这类问题。
/// 类型的选择逻辑（PopularController.selectTag）完全不动，这里只负责
/// 焦点顺序：横移归方向遍历，下键交给页面搭桥（[onDown]）。
class TvTagBar extends StatefulWidget {
  const TvTagBar({
    super.key,
    required this.tags,
    required this.currentTag,
    required this.onSelect,
    required this.onDown,
  });

  /// 完整类型列表，首个空串代表「热门番组」。
  final List<String> tags;

  /// 当前选中的类型（空串 = 热门番组）。
  final String currentTag;

  /// OK：切换类型。
  final ValueChanged<String> onSelect;

  /// ↓：往网格里走。网格还在加载时要由页面记住这次意图，等卡片挂上来再落焦。
  final VoidCallback onDown;

  @override
  State<TvTagBar> createState() => TvTagBarState();
}

class TvTagBarState extends State<TvTagBar> {
  /// 每个胶囊一个独立节点：换选中态时要能精确地把焦点送回「当前那一颗」。
  final Map<String, FocusNode> _nodes = {};

  FocusNode _nodeFor(String tag) => _nodes.putIfAbsent(
    tag,
    () => FocusNode(debugLabel: 'tv-tag:${tag.isEmpty ? '热门番组' : tag}'),
  );

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// 把焦点交给当前选中的那颗胶囊（网格第一行按上、或从别处回到类型条）。
  void focusCurrent() {
    if (!mounted) return;
    final node = _nodeFor(widget.currentTag);
    if (node.context == null) return;
    node.requestFocus();
  }

  /// 焦点是不是长在本条里。
  bool owns(FocusNode? node) {
    if (node == null) return false;
    return _nodes.values.any((n) => identical(n, node));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Focus(
        // 只做下键搭桥，本身不参与焦点。
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            widget.onDown();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // 一行到底，不允许换行：换行会让 ↓ 的落点变得不可预测。
          child: Row(
            children: [
              for (final tag in widget.tags)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _bar(tag),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(String tag) {
    final colors = Theme.of(context).colorScheme;
    final selected = tag == widget.currentTag;
    final label = tag.isEmpty ? '热门番组' : tag;
    return TvFocusRing(
      borderRadius: 20,
      child: Material(
        color: selected ? colors.primary : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: _nodeFor(tag),
          borderRadius: BorderRadius.circular(20),
          onTap: () => widget.onSelect(tag),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                // 选中项用填充色区分，焦点框只负责「焦点在哪」，
                // 两套语义不要混在一起。
                color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
