import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/tv_focus_ring.dart';
import 'package:kazumi/modules/collect/collect_type.dart';

/// 电视形态的「追番状态」选择弹窗。
///
/// 贴边菜单（KazumiMenuButton）的选项挂在 Overlay 上，遥控器既走不到也点不中，
/// 所以电视上统一用这个列表弹窗：上下键走焦点，OK 才确认并关闭。
/// 返回 null 表示取消。
Future<CollectType?> showCollectTypePicker(
  BuildContext context, {
  required CollectType current,
}) {
  return KazumiDialog.show<CollectType>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('追番状态'),
      children: [
        for (final type in CollectType.values)
          TvFocusRing(
            borderRadius: 16,
            child: ListTile(
              autofocus: type == current,
              leading: Icon(
                type == current
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
              ),
              title: Text(type == CollectType.none ? '未追' : type.label),
              onTap: () => Navigator.of(context).pop(type),
            ),
          ),
      ],
    ),
  );
}

/// 电视形态的一组「操作」弹窗：列表项 + OK 触发，返回被选中项的 key。
Future<T?> showTvActionDialog<T>(
  BuildContext context, {
  required String title,
  required List<TvActionEntry<T>> entries,
}) {
  return KazumiDialog.show<T>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (var index = 0; index < entries.length; index++)
          TvFocusRing(
            borderRadius: 16,
            child: ListTile(
              autofocus: index == 0,
              leading: Icon(
                entries[index].icon,
                color: entries[index].destructive ? Colors.red.shade400 : null,
              ),
              title: Text(
                entries[index].label,
                style: entries[index].destructive
                    ? TextStyle(color: Colors.red.shade400)
                    : null,
              ),
              subtitle: entries[index].subtitle == null
                  ? null
                  : Text(entries[index].subtitle!),
              onTap: entries[index].enabled
                  ? () => Navigator.of(context).pop(entries[index].value)
                  : null,
            ),
          ),
      ],
    ),
  );
}

/// 电视形态的搜索弹窗：输入框拿到焦点、调系统输入法打字，
/// 按输入法的「搜索 / 完成」、遥控器回车，或点「搜索」确认，返回输入内容。
///
/// 单行输入框会吞掉上下键（EditableText 把上下当光标移动），
/// 所以这里给输入框挂一个只管上下键的 FocusNode：上下键照常走焦点、
/// 走到「取消 / 清空 / 搜索」这一排，左右键还是留给光标。
Future<String?> showTvSearchDialog(
  BuildContext context, {
  String initial = '',
  String hint = '请输入关键词',
  String title = '搜索',
}) {
  return KazumiDialog.show<String>(
    context: context,
    builder: (context) =>
        _TvSearchDialog(initial: initial, hint: hint, title: title),
  );
}

/// 弹窗本体做成 StatefulWidget：输入框的 controller / FocusNode 必须由它自己
/// 在 dispose 里释放。之前用 `.whenComplete()` 释放，弹窗还在退场动画里、
/// TextField 还挂在树上，FocusNode 被提前销毁直接抛
/// `'_dependents.isEmpty': is not true`，整个应用变红屏。
class _TvSearchDialog extends StatefulWidget {
  const _TvSearchDialog({
    required this.initial,
    required this.hint,
    required this.title,
  });

  final String initial;
  final String hint;
  final String title;

  @override
  State<_TvSearchDialog> createState() => _TvSearchDialogState();
}

class _TvSearchDialogState extends State<_TvSearchDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  late final FocusNode _node = FocusNode(
    debugLabel: 'tv-search-field',
    onKeyEvent: _handleKey,
  );

  @override
  void dispose() {
    _node.dispose();
    _controller.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      Navigator.of(context).pop(_controller.text);
      return KeyEventResult.handled;
    }
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final direction = key == LogicalKeyboardKey.arrowUp
        ? TraversalDirection.up
        : TraversalDirection.down;
    return node.focusInDirection(direction)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text(widget.title),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: TextField(
            controller: _controller,
            focusNode: _node,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TvFocusRing(
                borderRadius: 12,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 8),
              TvFocusRing(
                borderRadius: 12,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: const Text('清空'),
                ),
              ),
              const SizedBox(width: 8),
              TvFocusRing(
                borderRadius: 12,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_controller.text),
                  child: const Text('搜索'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class TvActionEntry<T> {
  const TvActionEntry({
    required this.value,
    required this.label,
    required this.icon,
    this.subtitle,
    this.destructive = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData icon;
  final String? subtitle;
  final bool destructive;
  final bool enabled;
}
