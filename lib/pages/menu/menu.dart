import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/pages/menu/tv_top_bar.dart';
import 'package:kazumi/pages/router.dart';
import 'package:kazumi/utils/app_mode.dart';

class ScaffoldMenu extends StatefulWidget {
  const ScaffoldMenu({super.key, required this.location});

  final String location;

  @override
  State<ScaffoldMenu> createState() => _ScaffoldMenu();
}

class _ScaffoldMenu extends State<ScaffoldMenu> with RouteAware {
  final _outletKey = GlobalKey<RouterOutletState>();
  late int _selectedIndex = menu.indexForPath(widget.location);
  DateTime? _lastExitPromptAt;

  /// 电视形态：顶部导航条的焦点锚点（本身不可聚焦，只用来判断焦点是否在导航条里）。
  final FocusNode _tvBarAnchor =
      FocusNode(debugLabel: 'tv-top-bar', skipTraversal: true, canRequestFocus: false);

  /// 电视形态：当前选中 tab 那颗胶囊的焦点节点，UP 到顶时把焦点交给它。
  final FocusNode _tvNavFocus = FocusNode(debugLabel: 'tv-nav-selected');

  /// 电视形态：最后一次落在内容区的焦点节点，从导航条按 DOWN 时回到这里。
  FocusNode? _lastContentFocus;

  /// The shell sits at the bottom of the root stack and stays mounted while
  /// other pages cover it, so it publishes that state for its subtree.
  bool _isCovered = false;

  @override
  void didUpdateWidget(covariant ScaffoldMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _selectedIndex = menu.indexForPath(widget.location);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      rootRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _tvBarAnchor.dispose();
    _tvNavFocus.dispose();
    rootRouteObserver.unsubscribe(this);
    super.dispose();
  }

  /// 焦点是否落在顶部导航条里。
  ///
  /// 内容区是 RouterOutlet 里的独立路由，各自带 FocusScope；Flutter 的方向
  /// 遍历不跨 scope，所以导航条和内容区之间的上下移动必须由外层显式搭桥，
  /// 否则就会出现「按上键到不了分页栏」。这里先记下焦点归属，再由按键处理搬运。
  bool _isInTopBar(FocusNode? node) {
    if (node == null) return false;
    if (identical(node, _tvBarAnchor)) return true;
    return node.ancestors.contains(_tvBarAnchor);
  }

  /// 从导航条往下进内容区：优先回到上次停留的控件（跨 scope 的 requestFocus 是允许的），
  /// 没有历史（比如刚切完 tab）就按遍历顺序找第一个位于导航条下方、可聚焦的节点。
  bool _focusContent() {
    final last = _lastContentFocus;
    if (last != null && last.context != null && last.canRequestFocus) {
      last.requestFocus();
      return true;
    }
    final double barBottom = _tvBarAnchor.rect.bottom;
    for (final node in FocusManager.instance.rootScope.traversalDescendants) {
      if (identical(node, _tvBarAnchor) || _isInTopBar(node)) continue;
      if (!node.canRequestFocus) continue;
      final rect = node.rect;
      if (rect.height <= 0 || rect.width <= 0) continue;
      if (rect.top < barBottom - 1) continue;
      node.requestFocus();
      return true;
    }
    return false;
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() => _setCovered(false);

  void _setCovered(bool value) {
    if (!mounted || _isCovered == value) {
      return;
    }
    setState(() => _isCovered = value);
  }

  void _selectDestination(int index) {
    _lastExitPromptAt = null;
    if (index == _selectedIndex) {
      return;
    }
    final outlet = _outletKey.currentState;
    if (outlet == null) return;
    outlet.navigate('/tab${menu.getPath(index)}/');
    setState(() => _selectedIndex = index);
  }

  void _handleSystemBack(BuildContext context) {
    if (_outletKey.currentState?.maybePop() ?? false) {
      _lastExitPromptAt = null;
      return;
    }

    if (_selectedIndex != 0) {
      _selectDestination(0);
      return;
    }

    final now = DateTime.now();
    final lastPromptAt = _lastExitPromptAt;
    if (lastPromptAt == null ||
        now.difference(lastPromptAt) > const Duration(seconds: 2)) {
      _lastExitPromptAt = now;
      KazumiDialog.showToast(message: '再按一次退出应用', context: context);
      return;
    }

    _lastExitPromptAt = null;
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return RouteVisibility(
      isCovered: _isCovered,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _handleSystemBack(context);
          }
        },
        child: OrientationBuilder(
          builder: (context, orientation) {
            return orientation == Orientation.portrait
                ? _bottomMenu(context, _selectedIndex)
                : _sideMenu(context, _selectedIndex);
          },
        ),
      ),
    );
  }

  Widget _outlet(BuildContext context, {BorderRadius? borderRadius}) {
    Widget child = NotificationListener<NavigationNotification>(
      // A non-poppable outlet must not override the shell's PopScope state.
      onNotification: (notification) => !notification.canHandlePop,
      child: RouterOutlet(key: _outletKey),
    );
    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius, child: child);
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }

  Widget _bottomMenu(BuildContext context, int selectedIndex) {
    return Scaffold(
      body: _outlet(context),
      bottomNavigationBar: NavigationBar(
        destinations: const <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.home),
            icon: Icon(Icons.home_outlined),
            label: '推荐',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.timeline),
            icon: Icon(Icons.timeline_outlined),
            label: '时间表',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.favorite),
            icon: Icon(Icons.favorite_outlined),
            label: '追番',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.settings),
            icon: Icon(Icons.settings),
            label: '我的',
          ),
        ],
        selectedIndex: selectedIndex,
        onDestinationSelected: _selectDestination,
      ),
    );
  }

  Widget _sideMenu(BuildContext context, int selectedIndex) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(16),
      bottomLeft: Radius.circular(16),
    );
    const topBarRadius = BorderRadius.only(
      topLeft: Radius.circular(16),
      topRight: Radius.circular(16),
    );
    final Widget rail = EmbeddedNativeControlArea(
      child: NavigationRail(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              groupAlignment: 1,
              leading: FloatingActionButton(
                elevation: 0,
                heroTag: null,
                onPressed: () => context.pushNamed('/search/'),
                child: const Icon(Icons.search),
              ),
              labelType: NavigationRailLabelType.selected,
              destinations: const <NavigationRailDestination>[
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.home),
                  icon: Icon(Icons.home_outlined),
                  label: Text('推荐'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.timeline),
                  icon: Icon(Icons.timeline_outlined),
                  label: Text('时间表'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.favorite),
                  icon: Icon(Icons.favorite_border),
                  label: Text('追番'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.settings),
                  icon: Icon(Icons.settings_outlined),
                  label: Text('我的'),
                ),
              ],
              selectedIndex: selectedIndex,
              onDestinationSelected: _selectDestination,
            ),
    );

    if (!AppMode.isTv) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        body: Row(
          children: [
            rail,
            Expanded(child: _outlet(context, borderRadius: borderRadius)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          // 数字键 1-4 直接切 tab（电视惯例，可在设置里关）。
          final index = switch (event.logicalKey) {
            LogicalKeyboardKey.digit1 => 0,
            LogicalKeyboardKey.digit2 => 1,
            LogicalKeyboardKey.digit3 => 2,
            LogicalKeyboardKey.digit4 => 3,
            _ => null,
          };
          if (index != null) {
            _selectDestination(index);
            return KeyEventResult.handled;
          }

          final primary = FocusManager.instance.primaryFocus;
          final inTopBar = _isInTopBar(primary);
          if (!inTopBar && primary != null) {
            _lastContentFocus = primary;
          }

          // 上键：先在内容区里正常往上走，走到最上面一行还上不去，就把焦点交给导航条。
          if (!inTopBar && event.logicalKey == LogicalKeyboardKey.arrowUp) {
            final moved = primary?.focusInDirection(TraversalDirection.up) ?? false;
            if (!moved) {
              _tvNavFocus.requestFocus();
            }
            return KeyEventResult.handled;
          }

          // 下键：从导航条回到内容区，回到上次停留的那一格。
          if (inTopBar && event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (_focusContent()) {
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Focus(
                focusNode: _tvBarAnchor,
                child: TvTopBar(
                  selectedIndex: selectedIndex,
                  navFocusNode: _tvNavFocus,
                  onSelect: _selectDestination,
                  onSearch: () => context.pushNamed('/search/'),
                  onHistory: () => context.pushNamed('/settings/history/'),
                ),
              ),
            ),
            Expanded(
              child: _outlet(context, borderRadius: topBarRadius),
            ),
          ],
        ),
      ),
    );
  }
}
