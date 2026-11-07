import 'package:flutter/material.dart';
import 'package:kazumi/utils/app_mode.dart';

/// 电视形态下的焦点框装饰器。
///
/// 把任意「内部自带可聚焦控件（InkWell / IconButton 等）」的卡片包一层：
/// 3px 描边 + 1.05 缩放 + 焦点自动滚动跟随。手机形态下直接返回 [child]，
/// 不产生任何额外节点与布局变化。
class TvFocusRing extends StatefulWidget {
  const TvFocusRing({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.scale = 1.05,
    this.borderColor = Colors.white,
    this.padding = EdgeInsets.zero,
    this.scrollIntoView = true,
  });

  final Widget child;
  final double borderRadius;
  final double scale;
  final Color borderColor;
  final EdgeInsets padding;
  final bool scrollIntoView;

  @override
  State<TvFocusRing> createState() => _TvFocusRingState();
}

class _TvFocusRingState extends State<TvFocusRing> {
  bool _focused = false;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _enabled = AppMode.isTv;
  }

  void _handleFocusChange(bool focused) {
    if (focused == _focused) return;
    setState(() => _focused = focused);
    if (!focused || !widget.scrollIntoView) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scrollable = Scrollable.maybeOf(context);
      final renderObject = context.findRenderObject();
      if (scrollable == null || renderObject == null) return;
      scrollable.position.ensureVisible(
        renderObject,
        alignment: 0.5,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _handleFocusChange,
      child: AnimatedScale(
        scale: _focused ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Padding(
          padding: widget.padding,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              widget.child,
              if (_focused)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(widget.borderRadius),
                        border: Border.all(
                          color: widget.borderColor,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.borderColor.withValues(alpha: 0.35),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
