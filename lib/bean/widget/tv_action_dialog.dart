import 'package:flutter/material.dart';
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
