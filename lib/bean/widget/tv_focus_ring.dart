import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/tv_focus_overlay.dart';
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
    this.scale = 1.07,
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
              // 打个标记给全局指示层：这颗控件自己会描边，别重复画
              TvFocusRingMarker(child: widget.child),
              if (_focused) ...[
                // 里圈白色实线：焦点本身
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          widget.borderRadius,
                        ),
                        border: Border.all(color: widget.borderColor, width: 5),
                        boxShadow: [
                          // 外发光，让白框在浅色背景上也能跳出来
                          BoxShadow(
                            color: widget.borderColor.withValues(alpha: 0.5),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 外圈暗影：客厅灯光下浅底 + 白框会糊成一片，垫一圈深色才分得清
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          widget.borderRadius + 4,
                        ),
                        // 浅灰底上白线会糊掉，外面这圈深色才是「看得见」的关键：
                        // 加宽到 3.5 并加深，白框才有对比
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.75),
                          width: 3.5,
                        ),
                      ),
                    ),
                  ),
                ),
                // 一层极淡的白色提亮，让「选中」和「没选中」整体亮度也拉开
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          widget.borderRadius,
                        ),
                        color: widget.borderColor.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
