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
class TvSearchField extends StatelessWidget {
  const TvSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.autofocus = false,
    this.decoration,
    this.dialogTitle = '搜索',
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  /// 非电视形态下沿用的输入框装饰，电视形态只取其中的前缀图标。
  final InputDecoration? decoration;
  final String dialogTitle;

  @override
  Widget build(BuildContext context) {
    if (!AppMode.isTv) {
      return TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
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
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final result = await showTvSearchDialog(
              context,
              initial: controller.text,
              hint: hint,
              title: dialogTitle,
            );
            if (result == null) return;
            controller.text = result;
            onChanged(result);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                decoration?.prefixIcon ??
                    Icon(Icons.search_rounded, color: colors.onSurfaceVariant),
                const SizedBox(width: 12),
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
    );
  }
}
