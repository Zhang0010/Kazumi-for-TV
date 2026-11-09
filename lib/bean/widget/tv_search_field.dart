import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/tv_action_dialog.dart';
import 'package:kazumi/bean/widget/tv_focus_ring.dart';
import 'package:kazumi/utils/app_mode.dart';

/// 搜索框：手机/桌面就是一个普通输入框，电视上换成「胶囊按钮 + 弹窗输入」。
///
/// 为什么电视不能直接放输入框：聚焦在 `TextField` 上时，`EditableText`
/// 会把上下左右都当作光标移动吃掉，方向键再也走不出这个输入框 ——
/// 屏幕上焦点框卡在搜索框里，用户会认为「遥控器根本没法用」。
/// 换成按钮以后方向键照常遍历，OK 才唤起弹窗和系统输入法打字。
///
/// 全应用统一用它承载搜索类输入（搜索页、追番页、历史记录、弹幕源、
/// 规则管理/规则仓库、插件关键词测试），保证电视上「焦点不会掉进输入框」。
class TvSearchField extends StatelessWidget {
  const TvSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.decoration,
    this.dialogTitle = '搜索',
    this.minHeight = 56,
    this.dense = false,
  });

  final TextEditingController controller;
  final String hint;

  /// 文本变化（手机上是逐字，电视上是弹窗确认后一次性）。
  final ValueChanged<String> onChanged;

  /// 电视形态弹窗确认后触发；手机形态等价于输入框的 `onSubmitted`。
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool enabled;

  /// 非电视形态下沿用的输入框装饰，电视形态只取其中的前缀图标。
  final InputDecoration? decoration;
  final String dialogTitle;
  final double minHeight;

  /// 紧凑形态：给抽屉/工具条里那一行用，高度更贴近原来的 46。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (!AppMode.isTv) {
      return TextField(
        controller: controller,
        autofocus: autofocus,
        enabled: enabled,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: decoration,
      );
    }
    final colors = Theme.of(context).colorScheme;
    final text = controller.text.trim();
    return TvFocusRing(
      borderRadius: 16,
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: autofocus,
          canRequestFocus: enabled,
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? () => _openDialog(context) : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: dense ? 14 : 20,
                vertical: dense ? 8 : 16,
              ),
              child: Row(
                children: [
                  decoration?.prefixIcon ??
                      Icon(
                        Icons.search_rounded,
                        size: dense ? 18 : 24,
                        color: colors.onSurfaceVariant,
                      ),
                  SizedBox(width: dense ? 8 : 12),
                  Expanded(
                    child: Text(
                      text.isEmpty ? hint : text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: text.isEmpty
                            ? colors.onSurfaceVariant
                            : colors.onSurface,
                      ),
                    ),
                  ),
                  if (text.isNotEmpty)
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openDialog(BuildContext context) async {
    final result = await showTvSearchDialog(
      context,
      initial: controller.text,
      hint: hint,
      title: dialogTitle,
    );
    if (result == null) return;
    controller.text = result;
    onChanged(result);
    onSubmitted?.call(result);
  }
}
