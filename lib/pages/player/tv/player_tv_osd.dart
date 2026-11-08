import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/format.dart';

/// 电视形态播放器 OSD。
///
/// 只有遥控器：DPAD + OK + BACK + MENU，没有 hover、没有触摸手势。
/// 键位（与 docs/tv/DESIGN.md §3.3 一致）：
/// - OSD 隐藏：OK = 播放/暂停，长按 OK = 选集抽屉，←→ = ±10s，↑↓ = 呼出 OSD
/// - OSD 显示：←→ = 移动焦点（焦点在进度条上时 = seek），OK = 激活，BACK = 收起
class PlayerTvOsd extends StatefulWidget {
  const PlayerTvOsd({
    super.key,
    required this.playerController,
    required this.videoPageController,
    required this.playerFocusNode,
    required this.onBackPressed,
    required this.onShowOsd,
    required this.onHideOsd,
    required this.onSeekBy,
    required this.onNextEpisode,
    required this.onPreviousEpisode,
    required this.onChangeEpisode,
    required this.onToggleDanmaku,
    required this.onFullscreen,
    required this.onScreenshot,
    required this.onSkipOP,
    required this.setPlaybackSpeed,
  });

  final PlayerController playerController;
  final VideoPageController videoPageController;
  final FocusNode playerFocusNode;
  final VoidCallback onBackPressed;
  final VoidCallback onShowOsd;
  final VoidCallback onHideOsd;
  final void Function(int seconds) onSeekBy;
  final VoidCallback onNextEpisode;
  final VoidCallback onPreviousEpisode;
  final void Function(int episode, int road) onChangeEpisode;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onFullscreen;
  final VoidCallback onScreenshot;
  final VoidCallback onSkipOP;
  final Future<void> Function(double speed) setPlaybackSpeed;

  @override
  State<PlayerTvOsd> createState() => _PlayerTvOsdState();
}

class _PlayerTvOsdState extends State<PlayerTvOsd> {
  final FocusNode _playPauseFocus = FocusNode(debugLabel: 'tv-play-pause');
  final FocusNode _prevFocus = FocusNode(debugLabel: 'tv-prev');
  final FocusNode _nextFocus = FocusNode(debugLabel: 'tv-next');
  final FocusNode _progressFocus = FocusNode(debugLabel: 'tv-progress');
  final FocusNode _speedFocus = FocusNode(debugLabel: 'tv-speed');
  final FocusNode _danmakuFocus = FocusNode(debugLabel: 'tv-danmaku');
  final FocusNode _backFocus = FocusNode(debugLabel: 'tv-back');
  final FocusNode _episodesFocus = FocusNode(debugLabel: 'tv-episodes');

  Timer? _okLongPressTimer;
  bool _okLongPressFired = false;

  Timer? _hudTimer;
  String? _hudText;

  Timer? _playPauseFlashTimer;
  bool _flashPlaying = true;
  bool _flashVisible = false;

  bool _drawerOpen = false;
  int _drawerRoad = 0;

  bool get _osdVisible => widget.playerController.panel.showVideoController;

  @override
  void initState() {
    super.initState();
    _drawerRoad = widget.videoPageController.selectedEpisode.road;
    FocusManager.instance.addEarlyKeyEventHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKeyEvent);
    _okLongPressTimer?.cancel();
    _hudTimer?.cancel();
    _playPauseFlashTimer?.cancel();
    _playPauseFocus.dispose();
    _prevFocus.dispose();
    _nextFocus.dispose();
    _progressFocus.dispose();
    _speedFocus.dispose();
    _danmakuFocus.dispose();
    _backFocus.dispose();
    _episodesFocus.dispose();
    super.dispose();
  }

  bool get _isCurrentRoute {
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  bool get _focusInPlayer {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    final node = widget.playerFocusNode;
    return primary == node || primary.ancestors.contains(node);
  }

  bool get _canHandleKeys {
    if (!_isCurrentRoute) return false;
    if (widget.playerController.panel.lockPanel) return false;
    return _focusInPlayer;
  }

  bool _isOk(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;

  bool _isMenu(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.contextMenu ||
      key == LogicalKeyboardKey.f1 ||
      key == LogicalKeyboardKey.controlLeft;

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (!_canHandleKeys) return KeyEventResult.ignored;
    if (_drawerOpen) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final visible = _osdVisible;

    if (_isOk(key)) {
      if (visible) return KeyEventResult.ignored;
      if (event is KeyDownEvent) {
        _okLongPressFired = false;
        _okLongPressTimer?.cancel();
        _okLongPressTimer = Timer(const Duration(milliseconds: 550), () {
          _okLongPressFired = true;
          _openDrawer();
        });
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        _okLongPressTimer?.cancel();
        _okLongPressTimer = null;
        if (!_okLongPressFired) {
          _flashPlayPause();
          unawaited(widget.playerController.playOrPause());
        }
        _okLongPressFired = false;
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (_isMenu(key)) {
      if (event is KeyDownEvent) {
        _openDrawer();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.mediaPlayPause && event is KeyDownEvent) {
      _flashPlayPause();
      unawaited(widget.playerController.playOrPause());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext && event is KeyDownEvent) {
      widget.onNextEpisode();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious && event is KeyDownEvent) {
      widget.onPreviousEpisode();
      return KeyEventResult.handled;
    }

    if (visible) return KeyEventResult.ignored;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _seek(-widget.playerController.playback.arrowKeySkipTime);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _seek(widget.playerController.playback.arrowKeySkipTime);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp && event is KeyDownEvent) {
        _showOsd(focusBottom: false);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown && event is KeyDownEvent) {
        _showOsd(focusBottom: true);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _showOsd({required bool focusBottom}) {
    widget.onShowOsd();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = focusBottom ? _playPauseFocus : _backFocus;
      node.requestFocus();
    });
  }

  void _hideOsd() {
    widget.onHideOsd();
    widget.playerFocusNode.requestFocus();
  }

  void _seek(int seconds) {
    widget.onSeekBy(seconds);
    final playback = widget.playerController.playback;
    final target = playback.currentPosition + Duration(seconds: seconds);
    _showHud(
      '${seconds.isNegative ? '−' : '+'}${seconds.abs()}s   ${durationToString(target.isNegative ? Duration.zero : target)}',
    );
  }

  void _showHud(String text) {
    _hudTimer?.cancel();
    setState(() => _hudText = text);
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _hudText = null);
    });
  }

  void _flashPlayPause() {
    _playPauseFlashTimer?.cancel();
    setState(() {
      _flashPlaying = !widget.playerController.playback.playing;
      _flashVisible = true;
      _hudText = null;
    });
    _playPauseFlashTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _flashVisible = false);
    });
  }

  Future<void> _openSpeedMenu() async {
    final speeds = defaultPlaySpeedList;
    final current = widget.playerController.playback.playerSpeed;
    final selected = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xEE000000),
        title: const Text('播放速度', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final speed in speeds)
                  ListTile(
                    autofocus: speed == current,
                    title: Text(
                      '${speed}x',
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: speed == current
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                    onTap: () => Navigator.of(dialogContext).pop(speed),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.setPlaybackSpeed(selected);
    }
    if (!mounted) return;
    _speedFocus.requestFocus();
  }

  void _openDrawer() {
    final roads = widget.videoPageController.roadList;
    if (roads.isEmpty) return;
    if (_osdVisible) widget.onHideOsd();
    setState(() {
      _drawerRoad = widget.videoPageController.selectedEpisode.road;
      _drawerOpen = true;
    });
  }

  void _closeDrawer() {
    setState(() => _drawerOpen = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.playerFocusNode.requestFocus();
    });
  }

  void _selectEpisode(int episode) {
    _closeDrawer();
    widget.onChangeEpisode(episode, _drawerRoad);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final visible = widget.playerController.panel.showVideoController;
        return PopScope(
          canPop: !visible && !_drawerOpen,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_drawerOpen) {
              _closeDrawer();
            } else {
              _hideOsd();
            }
          },
          child: Stack(
            children: [
              if (_drawerOpen) _buildDrawer(context),
              if (!_drawerOpen && visible) ...[
                _buildTopBar(context),
                _buildBottomBar(context),
              ],
              _buildHud(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHud(BuildContext context) {
    final hud = _hudText;
    final flash = _flashVisible;
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (flash)
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _flashPlaying
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                color: Colors.white,
                size: 76,
              ),
            ),
          if (hud != null)
            Container(
              margin: const EdgeInsets.only(top: 200),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                hud,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final vpc = widget.videoPageController;
    final title = vpc.title;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 24, 34),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              _TvIconButton(
                focusNode: _backFocus,
                icon: Icons.arrow_back_rounded,
                tooltip: '返回',
                onPressed: widget.onBackPressed,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // 顶部只留返回 + 标题：原来右上角一排文字按钮挂在标题旁边，
              // 既挤又离视线中心远；常用功能已经挪到底部按钮行。
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 44, 24, 18),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 进度条单独占一行、拉满宽度：原来它夹在按钮中间，
              // ←→ 走焦点时很容易一步踏进去就变成「跳进度」，
              // 现在按钮一行、进度条一行，想调进度得先按上键上来。
              _TvProgressBar(
                focusNode: _progressFocus,
                playerController: widget.playerController,
                onSeekBy: _seek,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _TvIconButton(
                    focusNode: _playPauseFocus,
                    icon: widget.playerController.playback.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip:
                        widget.playerController.playback.playing ? '暂停' : '播放',
                    onPressed: () {
                      _flashPlayPause();
                      unawaited(widget.playerController.playOrPause());
                    },
                    size: 34,
                  ),
                  _TvIconButton(
                    focusNode: _prevFocus,
                    icon: Icons.skip_previous_rounded,
                    tooltip: '上一集',
                    onPressed: widget.onPreviousEpisode,
                  ),
                  _TvIconButton(
                    focusNode: _nextFocus,
                    icon: Icons.skip_next_rounded,
                    tooltip: '下一集',
                    onPressed: widget.onNextEpisode,
                  ),
                  const SizedBox(width: 16),
                  Observer(
                    builder: (_) => Text(
                      '${durationToString(widget.playerController.playback.currentPosition)}'
                      ' / ${durationToString(widget.playerController.playback.duration)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // 常用的三个功能放在行尾：←→ 一直走就能到
                  _TvTextButton(
                    focusNode: _episodesFocus,
                    icon: Icons.video_library_rounded,
                    label: '剧集',
                    onPressed: _openDrawer,
                  ),
                  _TvTextButton(
                    focusNode: _danmakuFocus,
                    icon: widget.playerController.danmaku.danmakuOn
                        ? Icons.subtitles_rounded
                        : Icons.subtitles_off_rounded,
                    label: widget.playerController.danmaku.danmakuOn
                        ? '弹幕 开'
                        : '弹幕 关',
                    onPressed: widget.onToggleDanmaku,
                  ),
                  _TvTextButton(
                    focusNode: _speedFocus,
                    icon: Icons.speed_rounded,
                    label: '${widget.playerController.playback.playerSpeed}x',
                    onPressed: _openSpeedMenu,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final roads = widget.videoPageController.roadList;
    if (roads.isEmpty) return const SizedBox.shrink();
    final road = roads[_drawerRoad.clamp(0, roads.length - 1)];
    final selected = widget.videoPageController.selectedEpisode;
    return Positioned.fill(
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _closeDrawer,
              child: Container(color: Colors.black54),
            ),
          ),
          Container(
            width: 560,
            color: const Color(0xF21A1A1A),
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: SafeArea(
              left: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.video_library_rounded,
                          color: Colors.white, size: 26),
                      const SizedBox(width: 10),
                      const Text(
                        '选集',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${road.data.length} 集',
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (roads.length > 1)
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: roads.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final active = index == _drawerRoad;
                          return _TvChip(
                            label: _roadLabel(roads[index], index),
                            active: active,
                            onPressed: () {
                              setState(() => _drawerRoad = index);
                            },
                          );
                        },
                      ),
                    ),
                  if (roads.length > 1) const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (var i = 1; i <= road.data.length; i++)
                            _TvEpisodeChip(
                              index: i,
                              label: _episodeLabel(road, i),
                              active: selected.road == _drawerRoad &&
                                  selected.episode == i,
                              autofocus: selected.road == _drawerRoad &&
                                  selected.episode == i,
                              onPressed: () => _selectEpisode(i),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'OK 播放 · BACK 关闭',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _roadLabel(Road road, int index) {
    final name = road.name.trim();
    if (name.isEmpty) return '线路 ${index + 1}';
    return name.length > 10 ? '${name.substring(0, 10)}…' : name;
  }

  String _episodeLabel(Road road, int episode) {
    final index = episode - 1;
    if (index >= 0 && index < road.identifier.length) {
      final title = road.identifier[index].trim();
      if (title.isNotEmpty) return title;
    }
    return episode.toString().padLeft(2, '0');
  }
}

class _TvIconButton extends StatefulWidget {
  const _TvIconButton({
    required this.focusNode,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 26,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  @override
  State<_TvIconButton> createState() => _TvIconButtonState();
}

class _TvIconButtonState extends State<_TvIconButton> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter ||
            event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
      widget.onPressed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (value) => setState(() => _focused = value),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: widget.size + 30,
            height: widget.size + 22,
            decoration: BoxDecoration(
              color: _focused ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: _focused ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _TvTextButton extends StatefulWidget {
  const _TvTextButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_TvTextButton> createState() => _TvTextButtonState();
}

class _TvTextButtonState extends State<_TvTextButton> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter ||
            event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
      widget.onPressed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (value) => setState(() => _focused = value),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _focused ? Colors.white : Colors.white10,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon,
                  size: 22, color: _focused ? Colors.black : Colors.white),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: _focused ? Colors.black : Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvProgressBar extends StatefulWidget {
  const _TvProgressBar({
    required this.focusNode,
    required this.playerController,
    required this.onSeekBy,
  });

  final FocusNode focusNode;
  final PlayerController playerController;
  final void Function(int seconds) onSeekBy;

  @override
  State<_TvProgressBar> createState() => _TvProgressBarState();
}

class _TvProgressBarState extends State<_TvProgressBar> {
  bool _focused = false;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final step = widget.playerController.playback.arrowKeySkipTime;
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        widget.onSeekBy(-step);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        widget.onSeekBy(step);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _handleKey,
      onFocusChange: (value) => setState(() => _focused = value),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _focused ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: Observer(
          builder: (context) {
            final playback = widget.playerController.playback;
            final total = playback.duration.inMilliseconds;
            final position = playback.currentPosition.inMilliseconds;
            final buffered = playback.buffer.inMilliseconds;
            double ratio(int value) =>
                total <= 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      children: [
                        Container(color: Colors.white24),
                        FractionallySizedBox(
                          widthFactor: ratio(buffered),
                          child: Container(color: Colors.white38),
                        ),
                        FractionallySizedBox(
                          widthFactor: ratio(position),
                          child: Container(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TvChip extends StatefulWidget {
  const _TvChip({
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  State<_TvChip> createState() => _TvChipState();
}

class _TvChipState extends State<_TvChip> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter ||
            event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
      widget.onPressed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final highlight = _focused || widget.active;
    return Focus(
      onKeyEvent: _onKey,
      onFocusChange: (value) => setState(() => _focused = value),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: highlight ? Colors.white : Colors.white12,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: highlight ? Colors.black : Colors.white,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

class _TvEpisodeChip extends StatefulWidget {
  const _TvEpisodeChip({
    required this.index,
    required this.label,
    required this.active,
    required this.autofocus,
    required this.onPressed,
  });

  final int index;
  final String label;
  final bool active;
  final bool autofocus;
  final VoidCallback onPressed;

  @override
  State<_TvEpisodeChip> createState() => _TvEpisodeChipState();
}

class _TvEpisodeChipState extends State<_TvEpisodeChip> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter ||
            event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
      widget.onPressed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onFocusChange(bool value) {
    setState(() => _focused = value);
    if (!value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.of(context).position.ensureVisible(
            context.findRenderObject()!,
            alignment: 0.5,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final highlight = _focused;
    return SizedBox(
      width: 120,
      height: 64,
      child: Focus(
        autofocus: widget.autofocus,
        onKeyEvent: _onKey,
        onFocusChange: _onFocusChange,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: highlight
                  ? Colors.white
                  : (widget.active
                      ? Colors.orange.withValues(alpha: 0.85)
                      : Colors.white10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.active && !highlight
                    ? Colors.orange
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: highlight ? Colors.black : Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
