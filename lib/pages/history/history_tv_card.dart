import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/tv_action_dialog.dart';
import 'package:kazumi/bean/widget/tv_focus_ring.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';

/// 电视形态的历史记录卡片：海报 + 一行标题 + 一行「第几话 · 时间」。
///
/// 手机上那套「一整行横条 + 两个按钮」在电视上要跨整个屏幕去够右侧按钮，
/// 而且一屏只放得下三条。这里换成海报网格：一屏能看十几部，OK 直接续播，
/// 长按 OK / 菜单键出操作弹窗。
class HistoryTvCard extends StatefulWidget {
  const HistoryTvCard({
    super.key,
    required this.history,
    required this.onPlay,
    required this.onDetails,
    required this.onDelete,
    required this.collectType,
    required this.onChangeCollect,
    this.autofocus = false,
    this.busy = false,
  });

  final History history;
  final VoidCallback onPlay;
  final VoidCallback onDetails;
  final Future<void> Function() onDelete;
  final CollectType collectType;
  final ValueChanged<CollectType>? onChangeCollect;
  final bool autofocus;
  final bool busy;

  @override
  State<HistoryTvCard> createState() => _HistoryTvCardState();
}

enum _CardAction { play, details, collect, delete }

class _HistoryTvCardState extends State<HistoryTvCard> {
  bool _menuOpen = false;

  String get _position {
    final progress =
        widget.history.progresses[widget.history.lastWatchEpisode]?.progress;
    if (progress == null || progress.inSeconds <= 0) return '';
    final seconds = (progress.inSeconds % 60).toString().padLeft(2, '0');
    final minutes = (progress.inMinutes % 60).toString().padLeft(2, '0');
    return progress.inHours > 0
        ? '看到 ${progress.inHours}:$minutes:$seconds'
        : '看到 ${progress.inMinutes}:$seconds';
  }

  String get _episode {
    final name = widget.history.lastWatchEpisodeName;
    return name.isEmpty ? '第 ${widget.history.lastWatchEpisode} 话' : name;
  }

  Future<void> _openActions() async {
    if (_menuOpen || widget.busy) return;
    _menuOpen = true;
    try {
      final action = await showTvActionDialog<_CardAction>(
        context,
        title: '历史记录',
        entries: [
          TvActionEntry(
            value: _CardAction.play,
            label: '继续播放',
            subtitle: _position.isEmpty ? _episode : '$_episode · $_position',
            icon: Icons.play_arrow_rounded,
          ),
          TvActionEntry(
            value: _CardAction.details,
            label: '番剧详情',
            icon: Icons.info_outline_rounded,
          ),
          TvActionEntry(
            value: _CardAction.collect,
            label: '追番状态',
            subtitle: widget.collectType == CollectType.none
                ? '未追'
                : widget.collectType.label,
            icon: Icons.favorite_border_rounded,
            enabled: widget.onChangeCollect != null,
          ),
          TvActionEntry(
            value: _CardAction.delete,
            label: '删除记录',
            icon: Icons.delete_outline_rounded,
            destructive: true,
          ),
        ],
      );
      if (!mounted || action == null) return;
      switch (action) {
        case _CardAction.play:
          widget.onPlay();
        case _CardAction.details:
          widget.onDetails();
        case _CardAction.collect:
          await _changeCollect();
        case _CardAction.delete:
          await widget.onDelete();
      }
    } finally {
      _menuOpen = false;
    }
  }

  Future<void> _changeCollect() async {
    final onChangeCollect = widget.onChangeCollect;
    if (onChangeCollect == null) return;
    final picked = await showCollectTypePicker(
      context,
      current: widget.collectType,
    );
    if (picked != null) onChangeCollect(picked);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isMenu =
        key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.f1 ||
        key == LogicalKeyboardKey.controlLeft;
    if (!isMenu) return KeyEventResult.ignored;
    _openActions();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = widget.history.bangumiItem.nameCn.isEmpty
        ? widget.history.bangumiItem.name
        : widget.history.bangumiItem.nameCn;
    final image = widget.history.bangumiItem.images['large'] ?? '';
    final offline =
        HistoryEntryKind.normalize(widget.history.entryKind) ==
        HistoryEntryKind.offline;
    final position = _position;
    final time = TimeOfDay.fromDateTime(
      widget.history.lastWatchTime.toLocal(),
    ).format(context);

    // 焦点必须落在 InkWell 上（它自带 ActivateIntent），外层 Focus 只做按键兜底：
    // 用 canRequestFocus: false，遥控器 OK 才能触发续播。
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKey,
      child: TvFocusRing(
        borderRadius: 14,
        child: Material(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            autofocus: widget.autofocus,
            onTap: widget.busy ? null : widget.onPlay,
            onLongPress: widget.busy ? null : _openActions,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 0.65,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (image.isEmpty)
                        ColoredBox(
                          color: colors.surfaceContainerHighest,
                          child: Icon(
                            Icons.movie_outlined,
                            color: colors.onSurfaceVariant,
                          ),
                        )
                      else
                        LayoutBuilder(
                          builder: (context, box) => NetworkImgLayer(
                            src: image,
                            width: box.maxWidth,
                            height: box.maxHeight,
                          ),
                        ),
                      // 底部一层暗角，压住海报上的字
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: 46,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xB3000000)],
                            ),
                          ),
                        ),
                      ),
                      if (position.isNotEmpty)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 6,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.play_circle_fill_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  position,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (offline)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '缓存',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$_episode · $time',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
