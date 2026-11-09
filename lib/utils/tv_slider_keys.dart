import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 电视形态下，滑块（Slider / RangeSlider）会把 ↑↓ 也当成「调值」：
/// Flutter 的 Slider 默认把 arrowUp/arrowDown 一起绑到 increase/decrease 上，
/// 于是焦点一旦落到那条滑块上就再也走不出去（按上下键只改数值）。
///
/// 这里装一个早期按键拦截（在焦点系统分发之前执行）：
/// - 焦点在滑块内部时，↑↓ 改成跨控件移动，和页面里其他控件的走焦一致；
/// - ←→ 不拦，仍交给滑块调参数。
class TvSliderKeys {
  TvSliderKeys._();

  static bool _installed = false;

  static void install() {
    if (_installed) return;
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
    _installed = true;
  }

  static void uninstall() {
    if (!_installed) return;
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    _installed = false;
  }

  static KeyEventResult _handleKey(KeyEvent event) {
    final key = event.logicalKey;
    final up = key == LogicalKeyboardKey.arrowUp;
    final down = key == LogicalKeyboardKey.arrowDown;
    if (!up && !down) return KeyEventResult.ignored;

    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || !_focusInsideSlider(primary)) {
      return KeyEventResult.ignored;
    }

    if (event is KeyUpEvent) {
      // 按下时已经把键吃掉了，抬起也一并吞掉，别让滑块收到半套事件。
      return KeyEventResult.handled;
    }
    primary.focusInDirection(
      up ? TraversalDirection.up : TraversalDirection.down,
    );
    return KeyEventResult.handled;
  }

  static bool _focusInsideSlider(FocusNode node) {
    final context = node.context;
    if (context == null) return false;
    var inside = false;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is Slider || widget is RangeSlider) {
        inside = true;
        return false;
      }
      return true;
    });
    return inside;
  }
}
