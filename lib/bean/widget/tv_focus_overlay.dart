import 'package:flutter/material.dart';

/// 电视形态下的全局焦点指示层。
///
/// 逐控件包 `TvFocusRing` 永远包不全：标签 chip、文字按钮、「加载更多」这类
/// 零散控件总有漏网的，漏掉的那个就是「能走焦但屏幕上毫无变化」——
/// 用户只会说「根本不知道选中没选中」。
///
/// 这里在整棵树的顶层挂一层不接收事件的画布：监听焦点变化，直接取
/// `primaryFocus` 的渲染盒算出屏幕矩形，在上面描一圈白框 + 深色外环。
/// 已经用 [TvFocusRing] 包过的控件由它自己画，这里靠祖先链识别后跳过，
/// 避免出现两层框。
class TvFocusOverlay extends StatefulWidget {
  const TvFocusOverlay({super.key});

  @override
  State<TvFocusOverlay> createState() => _TvFocusOverlayState();
}

/// 现场诊断开关：打开后焦点框下方会画出「焦点节点类型 / 控件类型 / 尺寸」，
/// 用来确认「框住了一个空块」到底是哪个控件。投影仪 logcat 是空的，
/// 这类问题只能画在屏幕上看。
const bool _diagnose = false;

class _TvFocusOverlayState extends State<TvFocusOverlay> {
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() {});
  }

  /// 从焦点节点往上找，看它是不是已经被 `TvFocusRing` 接管了描边。
  bool _handledByRing(BuildContext context) {
    var handled = false;
    context.visitAncestorElements((element) {
      if (element.widget is TvFocusRingMarker) {
        handled = true;
        return false;
      }
      return true;
    });
    return handled;
  }

  Rect? _focusedRect() {
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (context == null || focus is FocusScopeNode) return null;
    if (_handledByRing(context)) return null;

    final nodeBox = context.findRenderObject();
    final canvasBox = _canvasKey.currentContext?.findRenderObject();
    if (nodeBox is! RenderBox || canvasBox is! RenderBox) return null;
    if (!nodeBox.hasSize || !canvasBox.hasSize) return null;
    if (nodeBox.size.width < 16 || nodeBox.size.height < 16) return null;

    // 满屏容器（页面根节点、整页 Focus 之类）不画：它们不是「可选项」
    if (nodeBox.size.width * nodeBox.size.height >
        canvasBox.size.width * canvasBox.size.height * 0.4) {
      return null;
    }

    final topLeft = nodeBox.localToGlobal(Offset.zero);
    final local = canvasBox.globalToLocal(topLeft);
    return local & nodeBox.size;
  }

  /// 临时诊断：把焦点节点的类型画在框下方，用来确认「框住了一个空块」到底是哪个控件。
  String? _debugLabel() {
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (context == null) return focus == null ? 'null' : focus.runtimeType.toString();
    final widget = context.widget;
    final box = context.findRenderObject();
    final size = box is RenderBox && box.hasSize ? '${box.size.width.toStringAsFixed(0)}x${box.size.height.toStringAsFixed(0)}' : '?';
    return '${focus.runtimeType} / ${widget.runtimeType} / $size';
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        key: _canvasKey,
        painter: _FocusRingPainter(
          _focusedRect,
          _diagnose ? _debugLabel : null,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// 给 `TvFocusRing` 打的标记，让全局指示层知道这颗控件不需要重复描边。
///
/// 单独做成一个 Invisible 的 widget 而不是靠 `is TvFocusRing` 判断：
/// 包的层级可能被其它透明 wrapper 隔开，按类型链判断容易漏。
class TvFocusRingMarker extends StatelessWidget {
  const TvFocusRingMarker({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter(this.locate, [this.label]);

  final Rect? Function() locate;
  final String? Function()? label;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = locate();
    if (rect == null || rect.isEmpty) return;

    final radius = Radius.circular(
      (rect.shortestSide * 0.22).clamp(10.0, 24.0),
    );
    final rrect = RRect.fromRectAndRadius(rect, radius);

    // 外圈深色：客厅灯光下浅底 + 白框会糊成一片
    canvas.drawRRect(
      rrect.inflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = Colors.black.withValues(alpha: 0.75),
    );
    // 内圈白线
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white,
    );

    final text = label?.call();
    if (text != null) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.red,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 600);
      painter.paint(canvas, rect.bottomLeft + const Offset(0, 4));
    }
  }

  @override
  bool shouldRepaint(_FocusRingPainter oldDelegate) => true;
}
