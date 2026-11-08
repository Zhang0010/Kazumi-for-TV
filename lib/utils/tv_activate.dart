import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 电视遥控器 OK 键的激活逻辑。
///
/// Android TV 上 DPAD 中心键映射成 [LogicalKeyboardKey.select]，而 Flutter 默认
/// 只把 enter / space 绑到 [ActivateIntent]，所以「按 OK 没反应」在电视上非常常见。
/// 外层已经把 select 统一映射成 [ActivateIntent]，这里兜底处理那些没有绑定
/// ActivateIntent 的自绘可聚焦控件（InkWell / GestureDetector / ListTile 等）：
/// 从当前焦点往上找到第一个带 onTap 的控件，直接触发它。
///
/// 有绑定 ActivateIntent 的控件（FilledButton / TextButton / IconButton）会在
/// 更近的一层就消费掉这个 Intent，轮不到这里，不会重复触发。
bool tvActivateFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  var handled = false;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is InkWell) {
      final onTap = widget.onTap;
      if (onTap != null) {
        onTap();
        handled = true;
        return false;
      }
    } else if (widget is InkResponse) {
      final onTap = widget.onTap;
      if (onTap != null) {
        onTap();
        handled = true;
        return false;
      }
    } else if (widget is ListTile) {
      final onTap = widget.onTap;
      if (onTap != null) {
        onTap();
        handled = true;
        return false;
      }
    } else if (widget is GestureDetector) {
      final onTap = widget.onTap;
      if (onTap != null) {
        onTap();
        handled = true;
        return false;
      }
    }
    return true;
  });
  if (!handled) {
    Actions.maybeInvoke(context, const ActivateIntent());
  }
  return true;
}

/// 电视形态的「OK 键 = 激活」快捷键表。
///
/// 同时收 enter / space / 手柄 A 键：外接键盘和蓝牙手柄在电视上都很常见，
/// 统一成一种语义，避免同一台设备上按键行为分裂。
const Map<ShortcutActivator, Intent> tvActivateShortcuts =
    <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
};
