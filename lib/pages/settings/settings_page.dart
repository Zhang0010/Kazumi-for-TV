import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/utils/app_mode.dart';

import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/bean/widget/content_section.dart';
import 'package:kazumi/pages/settings/player_settings.dart';
import 'package:kazumi/utils/constants.dart';

class _SettingsCategory {
  const _SettingsCategory({
    required this.label,
    required this.description,
    required this.icon,
    required this.path,
  });

  final String label;
  final String description;
  final IconData icon;
  final String path;
}

class _SettingsGroup {
  const _SettingsGroup({required this.title, required this.categories});

  final String title;
  final List<_SettingsCategory> categories;
}

const List<_SettingsGroup> _settingsGroups = [
  _SettingsGroup(
    title: '播放',
    categories: [
      _SettingsCategory(
        label: '播放设置',
        description: '解码、渲染与播放行为',
        icon: Icons.display_settings_rounded,
        path: '/settings/player',
      ),
      _SettingsCategory(
        label: '弹幕设置',
        description: '弹幕来源与显示效果',
        icon: Icons.subtitles_rounded,
        path: '/settings/danmaku',
      ),
      _SettingsCategory(
        label: '操作设置',
        description: '播放器按键映射',
        icon: Icons.keyboard_rounded,
        path: '/settings/keyboard',
      ),
    ],
  ),
  _SettingsGroup(
    title: '资源',
    categories: [
      _SettingsCategory(
        label: '规则管理',
        description: '番剧资源规则',
        icon: Icons.extension_rounded,
        path: '/settings/plugin',
      ),
      _SettingsCategory(
        label: '下载设置',
        description: '并发数与弹幕缓存',
        icon: Icons.downloading_rounded,
        path: '/settings/download-settings',
      ),
    ],
  ),
  _SettingsGroup(
    title: '应用',
    categories: [
      _SettingsCategory(
        label: '外观设置',
        description: '主题、配色与字体',
        icon: Icons.palette_rounded,
        path: '/settings/theme',
      ),
      _SettingsCategory(
        label: '界面设置',
        description: '启动、窗口行为与展示信息',
        icon: Icons.pages_rounded,
        path: '/settings/interface',
      ),
      _SettingsCategory(
        label: '同步设置',
        description: '追番状态与多设备同步',
        icon: Icons.cloud_rounded,
        path: '/settings/sync',
      ),
      _SettingsCategory(
        label: '网络设置',
        description: '访问加速与代理',
        icon: Icons.language_rounded,
        path: '/settings/proxy',
      ),
    ],
  ),
  _SettingsGroup(
    title: '其他',
    categories: [
      _SettingsCategory(
        label: '更新设置',
        description: '应用与规则更新',
        icon: Icons.update_rounded,
        path: '/settings/update',
      ),
      _SettingsCategory(
        label: '存储与日志',
        description: '图片缓存与错误日志',
        icon: Icons.storage_rounded,
        path: '/settings/storage',
      ),
      _SettingsCategory(
        label: '关于',
        description: '版本与开源信息',
        icon: Icons.info_outline_rounded,
        path: '/settings/about',
      ),
    ],
  ),
];

String _normalizePath(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1) : path;

bool _isWithinPath(String location, String path) =>
    location == path || location.startsWith('$path/');

String _categoryPath(String location) {
  if (location == '/settings') {
    return '/settings/player';
  }
  if (_isWithinPath(location, '/settings/bangumi') ||
      _isWithinPath(location, '/settings/webdav')) {
    return '/settings/sync';
  }
  for (final group in _settingsGroups) {
    for (final category in group.categories) {
      if (_isWithinPath(location, category.path)) {
        return category.path;
      }
    }
  }
  return location;
}

/// 左侧一级菜单的先后顺序：遥控器在菜单里上下移动时按这个顺序走，
/// 不交给几何算法（几何算法会把焦点甩到右边内容区里）。
final List<String> _railOrder = [
  for (final group in _settingsGroups)
    for (final category in group.categories) category.path,
];

class _SettingsCategorySelected extends Notification {
  const _SettingsCategorySelected(this.path);

  final String path;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.location});

  final String location;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _outletKey = GlobalKey<RouterOutletState>();
  Object? _categoryNavigation;
  late String _location = _normalizePath(widget.location);

  /// 左侧一级菜单的焦点节点。右侧内容跑在 RouterOutlet（嵌套 Navigator）里，
  /// 有自己的 FocusScope，方向键遍历出不了那个 scope，所以需要在这里手动接一下。
  final Map<String, FocusNode> _railFocusNodes = {};

  /// 右侧内容区的焦点 scope。包在 RouterOutlet 外面，这样「从菜单按右键」时
  /// 只在内容区里找落点——不包的话拿到的是页面级 scope，里面还带着左侧菜单，
  /// 结果焦点从菜单按右键反而跳到菜单另一项上。
  final FocusScopeNode _paneScope = FocusScopeNode(debugLabel: 'settings-pane');

  FocusNode _railFocusNode(String path) => _railFocusNodes.putIfAbsent(
    path,
    () => FocusNode(debugLabel: 'settings-rail-$path'),
  );

  @override
  void dispose() {
    for (final node in _railFocusNodes.values) {
      node.dispose();
    }
    _paneScope.dispose();
    super.dispose();
  }

  /// 把焦点送回右侧内容。切了分类之后旧的焦点节点会被销毁，所以退一步
  /// 找嵌套路由自己的 FocusScope，再往里走一格。
  void _focusIntoPane({int attempt = 0}) {
    for (final node in _paneScope.traversalDescendants) {
      if (node is FocusScopeNode) continue;
      if (node.context != null &&
          node.canRequestFocus &&
          _isFocusVisible(node)) {
        node.requestFocus();
        return;
      }
    }
    // 内容页还没建完（刚切分类的第一帧很常见），下一帧再试。
    if (attempt < 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusIntoPane(attempt: attempt + 1);
      });
    }
  }

  /// 把焦点落到左侧菜单的指定分类上（菜单内上下移动用）。
  void _focusRailAt(String path) {
    final node = _railFocusNode(path);
    if (node.context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final retry = _railFocusNode(path);
        retry.requestFocus();
        _ensureFocusVisible(retry);
      });
      return;
    }
    node.requestFocus();
    _ensureFocusVisible(node);
  }

  /// 把焦点落到左侧一级菜单的当前分类上，并把它滚进可视区。
  /// 电视上右侧内容按左键走到边界就走这条路。
  void _focusRail({bool ensureVisible = true}) {
    final node = _railFocusNode(_selectedCategoryPath);
    if (node.context == null) {
      // 节点还没挂到树上（列表刚重建），等一帧再落焦点。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final retry = _railFocusNode(_selectedCategoryPath);
        retry.requestFocus();
        if (ensureVisible) _ensureFocusVisible(retry);
      });
      return;
    }
    node.requestFocus();
    if (ensureVisible) _ensureFocusVisible(node);
  }

  /// 焦点正停在左侧菜单的第几项；没有落在菜单里时退回当前选中的分类。
  int get _railFocusIndex {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null) {
      for (var i = 0; i < _railOrder.length; i++) {
        if (_railFocusNodes[_railOrder[i]] == primary) return i;
      }
    }
    return _railOrder.indexOf(_selectedCategoryPath);
  }

  /// 方向键挪完焦点后确认新焦点「看得见」。
  ///
  /// 本应用的焦点框是 TvFocusOverlay 按 primaryFocus 的渲染盒画的，它会跳过
  /// FocusScope、跳过满屏容器、跳过 16px 以下的小块——焦点落进这些节点时
  /// 屏幕上没有任何指示，遥控器看起来就是「按了没反应」。这里用同一套判据
  /// 判断，落空了就撤回到左侧菜单，别把焦点丢在看不见的地方。
  bool _isFocusVisible(FocusNode? node) {
    if (node == null || node is FocusScopeNode) return false;
    final nodeContext = node.context;
    if (nodeContext == null) return false;
    final box = nodeContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    if (box.size.width < 16 || box.size.height < 16) return false;
    final screen = MediaQuery.maybeSizeOf(nodeContext) ?? Size.zero;
    if (screen.width > 0 && screen.height > 0) {
      if (box.size.width * box.size.height >
          screen.width * screen.height * 0.4) {
        return false;
      }
    }
    return true;
  }

  bool get _railHasFocus {
    final primary = FocusManager.instance.primaryFocus;
    return primary != null && _railFocusNodes.containsValue(primary);
  }

  /// 在左侧菜单里按确认（切换分类）之后，新页面会自己 autofocus，遥控器就
  /// 「跑飞」到右边内容区了——用户本想继续上下挑分类。这里在这一帧和 200ms
  /// 后再把焦点落回左侧，保证确认键只切内容、不搬家。
  void _restoreRailFocus() {
    if (!AppMode.isTv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_railHasFocus) _focusRail();
    });
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted && !_railHasFocus) _focusRail();
    });
  }

  void _ensureFocusVisible(FocusNode node) {
    final nodeContext = node.context;
    if (nodeContext == null) return;
    Scrollable.ensureVisible(
      nodeContext,
      alignment: 0.5,
      duration: Duration.zero,
    );
  }

  /// 电视形态下补一条「右侧内容 ←→ 左侧一级菜单」的通路。
  /// 只在设置页内部生效，不动全局按键映射。
  KeyEventResult _handleFocusKeys(FocusNode node, KeyEvent event) {
    if (!AppMode.isTv || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    final inRail = _railFocusNodes.containsValue(primary);

    // 焦点在左侧菜单时，↑↓ 只在菜单里上下走：几何遍历会把焦点甩到右边
    // 内容区（内容行又宽又高，正好压在菜单项的右下方向），遥控器像失灵。
    if (inRail &&
        (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown)) {
      final index = _railFocusIndex;
      if (index < 0) return KeyEventResult.ignored;
      final delta = event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
      final target = index + delta;
      if (target < 0 || target >= _railOrder.length) {
        return KeyEventResult.handled; // 到顶/到底就停住，不往外跳
      }
      _focusRailAt(_railOrder[target]);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && !inRail) {
      // 右侧内容里还能往左走就照常走；走不动说明到边界了，交给一级菜单。
      if (primary.focusInDirection(TraversalDirection.left)) {
        final moved = FocusManager.instance.primaryFocus;
        if (moved != null && moved != primary && _isFocusVisible(moved)) {
          return KeyEventResult.handled;
        }
      }
      _focusRail();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight && inRail) {
      _focusIntoPane();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String get _selectedCategoryPath => _categoryPath(_location);
  bool get _isSecondaryRoute =>
      _location != '/settings' && _location != _selectedCategoryPath;

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _categoryNavigation = null;
      _location = _normalizePath(widget.location);
    }
  }

  void _replaceCategory(String path) {
    final fromRail = _railHasFocus;
    final outlet = _outletKey.currentState!;
    // Nested pushes leave _location unchanged, so check the stack as well.
    if (!outlet.canPop && !_isSecondaryRoute && _selectedCategoryPath == path) {
      return;
    }
    _categoryNavigation = null;
    outlet.navigate(path);
    setState(() => _location = path);
    if (fromRail) _restoreRailFocus();
  }

  Future<void> _pushCategory(String path) async {
    if (_categoryNavigation != null) return;
    final fromRail = _railHasFocus;
    final navigation = Object();
    final previousLocation = _location;
    _categoryNavigation = navigation;
    setState(() => _location = path);
    await _outletKey.currentState!.push<void>(path);
    // Ignore completions from history replaced by a rail selection.
    if (!mounted || _categoryNavigation != navigation) return;
    setState(() {
      _categoryNavigation = null;
      _location = previousLocation;
    });
    if (fromRail) _restoreRailFocus();
  }

  void _goBack() {
    if (_outletKey.currentState?.maybePop() ?? false) return;
    _exitSettings();
  }

  void _exitSettings() {
    if (!context.maybePop()) context.navigate('/tab/my');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > LayoutBreakpoint.compact['width']!;
        return NavigatorPopHandler<Object?>(
          onPopWithResult: (_) => _goBack(),
          child: Scaffold(
            appBar: wide
                ? SysAppBar(
                    title: const Text('设置'),
                    leading: BackButton(onPressed: _exitSettings),
                  )
                : null,
            body: SafeArea(
              top: false,
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _handleFocusKeys,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Keep the outlet at the same tree position on resize.
                    SizedBox(
                      width: wide ? 280 : 0,
                      child: Offstage(
                        offstage: !wide,
                        child: _SettingsMenu(
                          wide: true,
                          selectedPath: _selectedCategoryPath,
                          onSelect: _replaceCategory,
                          focusNodeFor: _railFocusNode,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SettingsPaneScope(
                        embedded: wide,
                        showBackButton: _isSecondaryRoute,
                        onBack: _goBack,
                        child: NotificationListener<_SettingsCategorySelected>(
                          onNotification: (notification) {
                            _pushCategory(notification.path);
                            return true;
                          },
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              pageTransitionsTheme:
                                  settingsPageTransitionsTheme,
                            ),
                            child: FocusScope(
                              node: _paneScope,
                              child: RouterOutlet(key: _outletKey),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class SettingsIndexPage extends StatelessWidget {
  const SettingsIndexPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (SettingsPaneScope.of(context)?.embedded ?? false) {
      return const PlayerSettingsPage();
    }
    return Scaffold(
      appBar: SysAppBar(
        title: const Text('设置'),
        leading: BackButton(
          onPressed: () {
            if (!context.maybePop()) context.navigate('/tab/my');
          },
        ),
      ),
      body: _SettingsMenu(
        wide: false,
        onSelect: (path) => _SettingsCategorySelected(path).dispatch(context),
      ),
    );
  }
}

class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({
    required this.wide,
    this.selectedPath,
    required this.onSelect,
    this.focusNodeFor,
  });

  final bool wide;
  final String? selectedPath;
  final ValueChanged<String> onSelect;

  /// 电视形态下由外层托管焦点节点（需要跨 RouterOutlet 的 scope 跳转）。
  final FocusNode Function(String path)? focusNodeFor;

  @override
  Widget build(BuildContext context) {
    // 电视形态用 SingleChildScrollView + Column 而不是 ListView：ListView
    // 只建可视区内的子项，滚到下面的分类（比如「关于」）时那个焦点节点根本
    // 没挂到树上，右侧内容按左键 requestFocus 就成了空操作——表现出来就是
    // 「按左键回不到左边」。16 个条目一次全建，代价可以忽略。
    final children = <Widget>[
      for (final group in _settingsGroups)
        if (wide) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
            child: SectionHeader(title: Text(group.title)),
          ),
          for (final category in group.categories)
            _RailDestination(
              category: category,
              selected: selectedPath == category.path,
              focusNode: focusNodeFor?.call(category.path),
              onTap: () => onSelect(category.path),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: ContentSection.group(
              title: group.title,
              children: [
                for (final category in group.categories)
                  SettingsCategoryTile(
                    icon: category.icon,
                    title: category.label,
                    description: category.description,
                    onTap: () => onSelect(category.path),
                  ),
              ],
            ),
          ),
    ];
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: wide
          ? SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(4, 0, 0, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: children,
            ),
    );
  }
}

class _RailDestination extends StatelessWidget {
  const _RailDestination({
    required this.category,
    required this.selected,
    required this.onTap,
    this.focusNode,
  });

  final _SettingsCategory category;
  final bool selected;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? colorScheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: focusNode,
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(category.icon, size: 24, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category.label,
                    style: textTheme.labelLarge?.copyWith(color: foreground),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
