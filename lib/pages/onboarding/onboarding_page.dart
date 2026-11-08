import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/widget/tv_focus_ring.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/onboarding/steps/disclaimer_step.dart';
import 'package:kazumi/pages/onboarding/steps/mirror_settings_step.dart';
import 'package:kazumi/pages/onboarding/steps/plugin_shop_step.dart';
import 'package:kazumi/pages/onboarding/steps/update_source_step.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/platform/app_exit.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/update/startup_update_check.dart';
import 'package:kazumi/utils/app_mode.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.pluginsController,
    required this.myController,
  });

  final PluginsController pluginsController;
  final MyController myController;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

enum _OnboardingStep {
  welcome('使用约定'),
  updates('更新来源'),
  mirrors('访问加速'),
  rules('添加规则');

  const _OnboardingStep(this.label);

  final String label;
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();
  // 电视形态下焦点必须先落在主按钮上：否则没有 primaryFocus，
  // 方向键找不到遍历起点，按上下左右全无反应。
  final _primaryFocusNode = FocusNode(debugLabel: 'onboarding-primary');
  final _secondaryFocusNode = FocusNode(debugLabel: 'onboarding-secondary');
  // 记住「继续」之前焦点停在哪个选项上，按左键能原地回去
  FocusNode? _lastContentFocus;
  final _steps = [
    _OnboardingStep.welcome,
    if (Platform.isAndroid) _OnboardingStep.updates,
    _OnboardingStep.mirrors,
    _OnboardingStep.rules,
  ];
  int _currentIndex = 0;
  bool _agreed = false;
  bool _busy = false;
  late bool _useGithubUpdate;

  PluginsController get _pluginsController => widget.pluginsController;
  bool get _isLastStep => _currentIndex == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    _useGithubUpdate = GStorage.getSetting(SettingsKeys.autoUpdate);
    if (AppMode.isTv) {
      FocusManager.instance.addEarlyKeyEventHandler(_handleEarlyKey);
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusPrimary());
    }
  }

  @override
  void dispose() {
    if (AppMode.isTv) {
      FocusManager.instance.removeEarlyKeyEventHandler(_handleEarlyKey);
    }
    _primaryFocusNode.dispose();
    _secondaryFocusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _focusPrimary() {
    if (!mounted || !AppMode.isTv) return;
    _primaryFocusNode.requestFocus();
  }

  /// 电视形态的引导页只有一路「往下走」：右键直接落到主按钮上，
  /// 左键从主按钮退回刚才停留的选项。
  ///
  /// 必须用「早拦截」：步骤里的 `RadioListTile` 自己绑了方向键（无障碍的
  /// radio 语义，左右键切换选项），普通 `Focus.onKeyEvent` 挂在祖先上时
  /// 键已经被它吃掉，表现为「右键在两个选项之间来回跳」。
  KeyEventResult _handleEarlyKey(KeyEvent event) {
    if (!AppMode.isTv || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    // 只接管引导页自己这一层的按键：弹窗（如「暂不添加规则？」）、后续
    // 页面都有自己的焦点域，这里一律放行，否则会把它们的左右键一起吞掉。
    // 用「焦点所在路由 ≠ 本页路由」判断，别用 isCurrent —— 嵌套路由下
    // isCurrent 不可靠。
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    final focusedRoute = focusedContext == null
        ? null
        : ModalRoute.of(focusedContext);
    if (focusedRoute != null &&
        !identical(focusedRoute, ModalRoute.of(context))) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight &&
        key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    // 按住不放会连发 KeyRepeatEvent：这些也必须一并吞掉，
    // 否则第一下我们处理了，后面的重复事件又落回 RadioListTile 上。
    final isDown = event is KeyDownEvent;
    final primary = FocusManager.instance.primaryFocus;
    final onPrimary = identical(primary, _primaryFocusNode);
    final onSecondary = identical(primary, _secondaryFocusNode);
    // 底部那排按钮（退出 / 上一步 / 继续）之外的节点都算「内容区」
    final onContent = !onPrimary && !onSecondary;

    /// 焦点从底部按钮回到内容区上次停留的选项
    void backToContent() {
      final target = _lastContentFocus;
      if (target != null && target.context != null && target.canRequestFocus) {
        target.requestFocus();
      }
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (isDown && !onPrimary) {
        // 底部行是 [退出/上一步] …… [继续]，右键一律落到主按钮
        if (onContent && primary != null && primary is! FocusScopeNode) {
          _lastContentFocus = primary;
        }
        _primaryFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }

    // arrowDown：底部按钮在页面最下方，下面什么都没有，下键应该回到
    // 上方的选项（例如「访问加速」那三行）。用向上的方向遍历来落点。
    if (key == LogicalKeyboardKey.arrowDown) {
      if (!onPrimary && !onSecondary) {
        // 内容区里的下键交给默认遍历（选项之间移动）
        return KeyEventResult.ignored;
      }
      if (isDown) {
        primary?.focusInDirection(TraversalDirection.up);
      }
      return KeyEventResult.handled;
    }

    // arrowUp：交给默认遍历；内容区走到顶后落到主按钮，避免卡在顶上
    if (key == LogicalKeyboardKey.arrowUp) {
      if (isDown && onContent) {
        final moved =
            primary != null && primary.focusInDirection(TraversalDirection.up);
        if (!moved) _primaryFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // arrowLeft：内容区 → 左下的次要按钮（第一页是退出，其余是上一步）；
    // 主按钮 → 内容区上次的落点；次要按钮 → 内容区。
    if (isDown) {
      if (onContent) {
        _lastContentFocus = primary;
        _secondaryFocusNode.requestFocus();
      } else {
        backToContent();
      }
    }
    return KeyEventResult.handled;
  }

  Widget _buildStep(_OnboardingStep step) => switch (step) {
    _OnboardingStep.welcome => const DisclaimerStep(),
    _OnboardingStep.updates => UpdateSourceStep(
      useGithubUpdate: _useGithubUpdate,
      onChanged: (value) {
        setState(() => _useGithubUpdate = value);
        unawaited(GStorage.putSetting(SettingsKeys.autoUpdate, value));
      },
    ),
    _OnboardingStep.mirrors => const MirrorSettingsStep(),
    _OnboardingStep.rules => PluginShopStep(controller: _pluginsController),
  };

  String get _primaryLabel => !_agreed
      ? '同意并继续'
      : _isLastStep
      ? '开始使用'
      : '继续';

  Future<void> _navigate({required bool forward}) async {
    if (_busy || (!forward && _currentIndex == 0)) return;
    _busy = true;
    try {
      if (forward && !_agreed) setState(() => _agreed = true);
      if (forward && _isLastStep) {
        await _finish();
      } else {
        await _goToPage(_currentIndex + (forward ? 1 : -1));
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _goToPage(int index) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(index);
    } else {
      await _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubicEmphasized,
      );
    }
    // 翻页时上面 unfocus 过，电视形态要重新把焦点放回主按钮
    _focusPrimary();
  }

  Future<void> _finish() async {
    if (_pluginsController.pluginList.isEmpty) {
      final confirmed = await KazumiDialog.show<bool>(
        context: context,
        builder: (_) => const _SkipRulesDialog(),
      );
      if (confirmed != true) return;
    }
    await GStorage.putSetting(SettingsKeys.onboardingCompleted, true);
    if (!mounted) return;
    final myController = widget.myController;
    unawaited(
      runStartupUpdateCheck(
        isEnabled: () => GStorage.getSetting(SettingsKeys.autoUpdate),
        checkForUpdate: () => myController.checkUpdate(type: 'auto'),
      ),
    );
    context.navigate(GStorage.getSetting(SettingsKeys.defaultStartupPage));
  }

  Widget _buildBottomBar(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(16) > 24;
        final secondary = TextButton(
          focusNode: AppMode.isTv ? _secondaryFocusNode : null,
          style: TextButton.styleFrom(
            minimumSize: const Size(88, 56),
            foregroundColor: theme.colorScheme.onSurfaceVariant,
          ),
          onPressed: _currentIndex == 0
              ? AppExit.quit
              : () => _navigate(forward: false),
          child: Text(_currentIndex == 0 ? '退出' : '上一步'),
        );
        final primary = FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(176, 56),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          focusNode: AppMode.isTv ? _primaryFocusNode : null,
          autofocus: AppMode.isTv,
          onPressed: () => _navigate(forward: true),
          iconAlignment: IconAlignment.end,
          icon: Icon(
            _isLastStep ? Icons.check_rounded : Icons.arrow_forward_rounded,
          ),
          label: Text(_primaryLabel),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: stacked
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TvFocusRing(borderRadius: 28, child: primary),
                    const SizedBox(height: 4),
                    TvFocusRing(borderRadius: 28, child: secondary),
                  ],
                )
              : Row(
                  children: [
                    TvFocusRing(borderRadius: 28, child: secondary),
                    const SizedBox(width: 16),
                    const Spacer(),
                    TvFocusRing(borderRadius: 28, child: primary),
                  ],
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (bool didPop, Object? result) {
      if (!didPop) unawaited(_navigate(forward: false));
    },
    child: Scaffold(
      appBar: const SysAppBar(),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1184),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width < 600 ? 20 : 32,
              ),
              child: Column(
                children: [
                  _OnboardingProgress(
                    labels: _steps.map((step) => step.label).toList(),
                    currentIndex: _currentIndex,
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: _agreed
                          ? null
                          : const NeverScrollableScrollPhysics(),
                      onPageChanged: (index) {
                        setState(() => _currentIndex = index);
                      },
                      children: _steps.map(_buildStep).toList(),
                    ),
                  ),
                  _buildBottomBar(context),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SkipRulesDialog extends StatelessWidget {
  const _SkipRulesDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    constraints: const BoxConstraints(maxWidth: 560),
    icon: const Icon(Icons.warning_amber_rounded),
    title: const Text('暂不添加规则？'),
    content: const Text('没有规则时无法搜索和播放番剧。之后也可以在规则管理中添加。'),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('仍然继续'),
      ),
      FilledButton(
        autofocus: true,
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('返回添加'),
      ),
    ],
  );
}

class _OnboardingProgress extends StatelessWidget {
  const _OnboardingProgress({required this.labels, required this.currentIndex});

  final List<String> labels;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      label:
          '第 ${currentIndex + 1} 步，共 ${labels.length} 步，${labels[currentIndex]}',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      labels[currentIndex],
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${currentIndex + 1} / ${labels.length}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 250),
                        curve: Curves.easeInOutCubicEmphasized,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i <= currentIndex
                              ? colors.primary
                              : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
