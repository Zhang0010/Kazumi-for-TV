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
  final GlobalKey<TvTopBarState> _topBarKey = GlobalKey<TvTopBarState>();

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
  void initState() {
    super.initState();
    if (AppMode.isTv) {
      // 路由自带的 FocusScope 会先抢到初始焦点，导航条上的 autofocus 抢不过它，
      // 结果就是「进了主界面却没有任何一个控件被选中」。这里在首帧后显式把焦点按到当前 tab。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _topBarKey.currentState?.focusSelected();
      });
    }
  }

  @override
  void dispose() {
    _tvBarAnchor.dispose();

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
    if (_topBarKey.currentState?.owns(node) ?? false) return true;
    return node.ancestors.contains(_tvBarAnchor);
  }

  /// 把焦点送回导航条当前 tab 的胶囊。
  void _focusTopBar() {
    _topBarKey.currentState?.focusSelected();
  }

  /// 节点还能不能用：既要有挂载的 element、可聚焦，还要真的落在屏幕可见范围里。
  /// 只判断 context 不够——切 tab 或返回上一页后，旧节点可能仍挂在树上，
  /// 但位置在可视区之外，焦点按过去就「看不见、也走不动」。
  bool _isFocusableAndVisible(FocusNode node) {
    if (node.context == null || !node.canRequestFocus) return false;
    final rect = node.rect;
    if (rect.height <= 0 || rect.width <= 0) return false;
    final size = MediaQuery.of(context).size;
    if (rect.bottom <= _tvBarAnchor.rect.bottom) return false;
    if (rect.top >= size.height || rect.right <= 0 || rect.left >= size.width) {
      return false;
    }
    return true;
  }

  /// 从导航条往下进内容区。
  ///
  /// 之前按遍历顺序取「第一个在导航条下方的节点」，在 1080p 上会挑到列表末尾
  /// 那些还没滚出屏幕、但视觉上在页面底部的小控件，看起来就像「按下键没反应」。
  /// 改成按几何位置挑：取最靠上的一行，同行里取离当前导航胶囊最近的那个。
  bool _focusContent() {
    final last = _lastContentFocus;
    if (last != null && !_isFocusableAndVisible(last)) {
      _lastContentFocus = null;
    } else if (last != null) {
      last.requestFocus();
      return true;
    }
    final anchor = _tvBarAnchor.rect;
    if (anchor.isEmpty) return false;
    final double barBottom = anchor.bottom;
    final primary = FocusManager.instance.primaryFocus;
    final double wantX = primary?.rect.center.dx ?? anchor.center.dx;

    final candidates = <FocusNode>[];
    for (final node in FocusManager.instance.rootScope.traversalDescendants) {
      if (_isInTopBar(node)) continue;
      if (!node.canRequestFocus) continue;
      final rect = node.rect;
      if (rect.height <= 0 || rect.width <= 0) continue;
      if (rect.top < barBottom - 1) continue;
      candidates.add(node);
    }
    if (candidates.isEmpty) return false;
    candidates.sort((a, b) {
      final ra = a.rect;
      final rb = b.rect;
      final rowA = (ra.top / 8).round();
      final rowB = (rb.top / 8).round();
      if (rowA != rowB) return rowA.compareTo(rowB);
      return (ra.center.dx - wantX).abs().compareTo((rb.center.dx - wantX).abs());
    });
    final target = candidates.first;
    target.requestFocus();
    return true;
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
    // 换 tab 等于换了一整套内容节点，旧页面的焦点必须丢掉：
    // 留着它会让「下键」把焦点按回上一个 tab 里那个已经看不见的控件，
    // 表现就是「按了没反应」。
    _lastContentFocus = null;
    outlet.navigate('/tab${menu.getPath(index)}/');
    setState(() => _selectedIndex = index);
    // 换 tab 后焦点要跟着落到新的胶囊上，否则数字键切完 tab 焦点还留在旧格。
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusTopBar());
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
          final hasWidgetFocus = primary != null &&
              primary.context != null &&
              primary is! FocusScopeNode;
          final inTopBar = hasWidgetFocus && _isInTopBar(primary);
          if (!inTopBar && hasWidgetFocus) {
            _lastContentFocus = primary;
          }

          // 焦点停在路由的 FocusScope 上（没有任何控件被选中）时，方向键先找落脚点：
          // 下键进内容区，其余方向把焦点交给导航条，避免出现「按了没反应」的死状态。
          if (!hasWidgetFocus) {
            if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                _focusContent()) {
              return KeyEventResult.handled;
            }
            if (<LogicalKeyboardKey>{
              LogicalKeyboardKey.arrowUp,
              LogicalKeyboardKey.arrowDown,
              LogicalKeyboardKey.arrowLeft,
              LogicalKeyboardKey.arrowRight,
            }.contains(event.logicalKey)) {
              _focusTopBar();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }

          // 上键：先在内容区里正常往上走，走到最上面一行还上不去，就把焦点交给导航条。
          if (!inTopBar && event.logicalKey == LogicalKeyboardKey.arrowUp) {
            final moved = primary.focusInDirection(TraversalDirection.up);
            if (!moved) {
              _focusTopBar();
            }
            return KeyEventResult.handled;
          }

          // 下键：从导航条回到内容区，回到上次停留的那一格。
          if (inTopBar && event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (_focusContent()) return KeyEventResult.handled;
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
                  key: _topBarKey,
                  selectedIndex: selectedIndex,
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
