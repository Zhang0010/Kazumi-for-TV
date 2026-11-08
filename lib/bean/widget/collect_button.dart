import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/bean/widget/tv_action_dialog.dart';
import 'package:kazumi/bean/widget/tv_focus_ring.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/utils/app_mode.dart';

class CollectButton extends StatefulWidget {
  const CollectButton({
    super.key,
    required this.bangumiItem,
    this.color = Colors.white,
    this.onOpen,
    this.onClose,
    this.style,
  }) : _isExtended = false;

  const CollectButton.extend({
    super.key,
    required this.bangumiItem,
    this.color = Colors.white,
    this.onOpen,
    this.onClose,
    this.style,
  }) : _isExtended = true;

  final BangumiItem bangumiItem;
  final Color color;
  final bool _isExtended;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  /// 电视形态下需要和旁边的按钮同尺寸，这里把按钮样式交给调用方决定。
  final ButtonStyle? style;

  @override
  State<CollectButton> createState() => _CollectButtonState();
}

class _CollectButtonState extends State<CollectButton> {
  final _collectController = inject<CollectController>();

  String _labelFor(CollectType type) =>
      type == CollectType.none ? '未追' : type.label;

  IconData _iconFor(CollectType type) => switch (type) {
    CollectType.none => Icons.favorite_border,
    CollectType.watching => Icons.favorite,
    CollectType.planToWatch => Icons.star_rounded,
    CollectType.onHold => Icons.pending_actions,
    CollectType.watched => Icons.done,
    CollectType.abandoned => Icons.heart_broken,
  };

  Future<void> _selectType(CollectType type) async {
    if (!mounted ||
        type.value == _collectController.getCollectType(widget.bangumiItem)) {
      return;
    }
    await _collectController.addCollect(widget.bangumiItem, type: type.value);
    if (mounted) setState(() {});
  }

  /// 电视形态：用的是弹窗选择，不是贴边菜单。Markup 菜单在遥控器上点不动
  /// （菜单项挂在 Overlay 上、没有可聚焦的落点），改成和设置页一样的列表弹窗。
  Future<void> _showTvPicker(BuildContext context) async {
    final picked = await showCollectTypePicker(
      context,
      current: CollectType.fromValue(
        _collectController.getCollectType(widget.bangumiItem),
      ),
    );
    if (picked != null) {
      await _selectType(picked);
    }
  }

  Widget _buildTvButton(BuildContext context, CollectType collectType) {
    final label = _labelFor(collectType);
    return TvFocusRing(
      borderRadius: widget._isExtended ? 20 : 24,
      scale: 1.06,
      child: widget._isExtended
          ? FilledButton.icon(
              onPressed: () => _showTvPicker(context),
              style: widget.style,
              icon: Icon(_iconFor(collectType)),
              label: Text(label),
            )
          : IconButton(
              onPressed: () => _showTvPicker(context),
              tooltip: label,
              icon: Icon(_iconFor(collectType), color: widget.color),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final collectType = CollectType.fromValue(
      _collectController.getCollectType(widget.bangumiItem),
    );
    if (AppMode.isTv) {
      return _buildTvButton(context, collectType);
    }
    return KazumiMenuButton(
      onClose: widget.onClose,
      onOpen: widget.onOpen,
      crossAxisUnconstrained: false,
      // 追番/未追按钮是详情页最常按的东西，电视上必须一眼看出焦点在哪。
      builder: (context, toggle) => TvFocusRing(
        borderRadius: widget._isExtended ? 20 : 24,
        scale: 1.06,
        child: widget._isExtended
            ? FilledButton.icon(
                onPressed: toggle,
                style: widget.style,
                icon: Icon(_iconFor(collectType)),
                label: Text(_labelFor(collectType)),
              )
            : IconButton(
                onPressed: toggle,
                tooltip: _labelFor(collectType),
                icon: Icon(_iconFor(collectType), color: widget.color),
              ),
      ),
      menuChildren: [
        for (final type in CollectType.values)
          KazumiMenuItem(
            label: _labelFor(type),
            selected: type == collectType,
            onPressed: () => _selectType(type),
          ),
      ],
    );
  }
}
