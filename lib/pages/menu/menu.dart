import 'dart:async';

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
  final FocusNode _tvNavFocus = FocusNode(debugLabel: 'tv-top-nav');
  /// 挂在电视形态外壳根节点上，用来判断焦点是否还在壳内。
  final GlobalKey _shellRootKey = GlobalKey(debugLabel: 'tv-menu-shell');
  Timer? _focusWatchdog;

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
      // 路由自带的 FocusScope 会先抢到初始焦点，只靠 autofocus 抢不过它，
      // 结果就是「进了主界面却没有任何一个控件被选中」，方向键全死。
      // 这里在首帧后把焦点按到当前 tab，并在随后几拍里复查——路由转场结束得比
      // 第一帧晚，一次设置会被后面拿走的焦点盖掉。
      WidgetsBinding.instance.addPostFrameCallback((_) => _assertBarFocus());
      // 看门狗：只要焦点整个丢掉（primaryFocus 为空、或只是个 FocusScope），
      // 就把它抓回导航条。遥控器没有鼠标可以「点一下」找回焦点，
      // 少了这一层，一次抢焦点就可能让整个界面再也按不动。
      _focusWatchdog = Timer.periodic(const Duration(milliseconds: 600), (_) {
        if (!mounted || _isCovered) return;
        final primary = FocusManager.instance.primaryFocus;
        if (primary == null || primary is FocusScopeNode) {
          _assertBarFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _focusWatchdog?.cancel();
    _tvNavFocus.dispose();
    _tvBarAnchor.dispose();

    rootRouteObserver.unsubscribe(this);
    super.dispose();
  }

  /// 焦点是否落在顶部导航条里。
  ///
  /// 内容区是 RouterOutlet 里的独立路由，各自带 FocusScope；Flutter 的方向
  /// 遍历不跨 scope，所以导航条和内容区之间的上下移动必须由外层显式搭桥，
  /// 否则就会出现「按上键到不了分页栏」。这里先记下焦点归属，再由按键处理搬运。
  /// 焦点是否落在本壳（导航条 + 内容区）自己的子树里。
  bool _isFocusInsideShell() {
    final focused = FocusManager.instance.primaryFocus?.context;
    final shell = _shellRootKey.currentContext;
    if (focused == null || shell == null) return true;
    if (identical(focused, shell)) return true;
    var inside = false;
    (focused as Element).visitAncestorElements((element) {
      if (identical(element, shell)) {
        inside = true;
        return false;
      }
      return true;
    });
    return inside;
  }

  bool _isInTopBar(FocusNode node) {
    if (identical(node, _tvBarAnchor)) return true;
    if (identical(node, _tvNavFocus)) return true;
    return node.ancestors.contains(_tvBarAnchor);
  }

  /// 把焦点送回导航条当前 tab 的胶囊。
  void _focusTopBar() {
    if (_tvNavFocus.context != null) _tvNavFocus.requestFocus();
  }

  /// 确认焦点真的落在导航条上，没落上就重试几拍。
  ///
  /// 路由转场、页面重建都会把焦点临时交给 FocusScope，一次性 requestFocus 很容易
  /// 被之后的焦点变化抹掉，表现出来就是「整个界面按不动」。
  void _assertBarFocus([int attempt = 0]) {
    if (!mounted || attempt > 25) return;
    if (_tvNavFocus.context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _assertBarFocus(attempt + 1);
      });
      return;
    }
    if (_tvNavFocus.hasPrimaryFocus) return;
    _tvNavFocus.requestFocus();
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      if (!_tvNavFocus.hasPrimaryFocus) _assertBarFocus(attempt + 1);
    });
  }

  /// 节点还能不能用：既要有挂载的 element、可聚焦，还要真的落在屏幕可见范围里。
  /// 只判断 context 不够——切 tab 或返回上一页后，旧节点可能仍挂在树上，
  /// 但位置在可视区之外，焦点按过去就「看不见、也走不动」。
  bool _isFocusableAndVisible(FocusNode node) {
    if (node is FocusScopeNode) return false;
    if (node.context == null || !node.canRequestFocus) return false;
    final rect = node.rect;
    if (rect.height <= 0 || rect.width <= 0) return false;
    // 用 root view 的逻辑尺寸：节点 rect 是全局坐标，MediaQuery 里的 size 已经被
    // 电视形态的缩放改写过，两者不是同一个坐标系。
    final view = View.of(context);
    final viewport = view.physicalSize / view.devicePixelRatio;
    if (rect.bottom <= _tvBarAnchor.rect.bottom) return false;
    // 满屏容器（整页兜底的 Focus）不算落脚点
    if (rect.width * rect.height >= viewport.width * viewport.height * 0.4) {
      return false;
    }
    if (rect.top >= viewport.height || rect.right <= 0 || rect.left >= viewport.width) {
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
    final view = View.of(context);
    final viewport = view.physicalSize / view.devicePixelRatio;
    // 从导航条下来一律落在最上一行最左边那一格：电视上的通行做法，
    // 也是人眼从导航往下的第一落点；贴着胶囊横坐标算反而容易跳到行中间。

    // 注意：FocusScopeNode 也是 canRequestFocus 的，而且整块内容区就是一条 scope，
    // 它的矩形正好盖在整个页面上、top 也刚好在导航条下面。一旦把它当落脚点，
    // 焦点就交给了一个「没有画面」的容器：requestFocus 成功、界面毫无变化，
    // 再按下键又落回它身上——这就是「下键按了没反应」的真凶。
    final candidates = <FocusNode>[];
    FocusScopeNode? scopeBelow;
    for (final node in FocusManager.instance.rootScope.traversalDescendants) {
      if (_isInTopBar(node)) continue;
      final rect = node.rect;
      if (rect.height <= 0 || rect.width <= 0) continue;
      if (rect.top < barBottom - 1) continue;
      if (rect.top >= viewport.height) continue;
      if (node is FocusScopeNode) {
        if (scopeBelow == null || rect.top < scopeBelow.rect.top) {
          scopeBelow = node;
        }
        continue;
      }
      if (!node.canRequestFocus) continue;
      // 有些页面会在最外层套一个「整片区域」的 Focus（用来接快捷键、兜住焦点），
      // 它同样是可聚焦的，矩形又刚好铺满内容区、top 也最靠上——不排除掉的话，
      // 下键永远落在这种看不见的容器上，表现就是整页「选不了」。
      if (rect.width * rect.height >= viewport.width * viewport.height * 0.4) {
        continue;
      }
      candidates.add(node);
    }
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) {
        final ra = a.rect;
        final rb = b.rect;
        final rowA = (ra.top / 8).round();
        final rowB = (rb.top / 8).round();
        if (rowA != rowB) return rowA.compareTo(rowB);
        return ra.left.compareTo(rb.left);
      });
      candidates.first.requestFocus();
      return true;
    }
    // 兜底：整页一个可聚焦控件都没有（还在加载、或者是空状态页）时，
    // 让路由自己的 scope 做一次标准的方向遍历。
    if (scopeBelow != null) {
      scopeBelow.requestFocus();
      if (scopeBelow.focusInDirection(TraversalDirection.down)) return true;
    }
    return false;
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() {
    _setCovered(false);
    // 从二级页返回时路由会重置焦点，回来第一件事就是把焦点交还导航条。
    if (AppMode.isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _assertBarFocus());
    }
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _assertBarFocus());
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
      key: _shellRootKey,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          // 弹窗 / 底部抽屉（选源、设置面板…）盖在上面时一律不接管：
          // 那些层有自己的焦点域，外壳插手下键会把焦点拽回本页，
          // 表现为「在抽屉里按下键，抽屉直接没了」。
          //
          // 判断方式既不能用 `ModalRoute.isCurrent`（嵌套路由下外壳这条路由
          // 永远不是「当前」，会把正常按键全挡掉），也不能比较路由是否相同
          // （内容区在 RouterOutlet 里是另一条路由，同样会被挡）。
          // 可靠判据：焦点控件是不是长在本壳的子树里。抽屉/弹窗挂在 Overlay，
          // 不在子树内，自然被放行。
          if (!_isFocusInsideShell()) {
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
              // 一个控件都没被选中时不能干等：先送回导航条，导航条也拿不到再
              // 找内容区第一个可聚焦控件，保证任何一个方向键都能把界面「唤醒」。
              _focusTopBar();
              _assertBarFocus();
              if (!_tvNavFocus.hasPrimaryFocus) _focusContent();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }

          // 上键：先在内容区里正常往上走，走到最上面一行还上不去，就把焦点交给导航条。
          if (!inTopBar && event.logicalKey == LogicalKeyboardKey.arrowUp) {
            final moved = primary.focusInDirection(TraversalDirection.up);
            if (!moved) {
              // 内容区第一行再往上没有落脚点：收回导航条（带重试，胶囊
              // 还没挂上时会失败）。
              _focusTopBar();
              _assertBarFocus();
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
                // 兜底：哪怕胶囊还没挂上，也要先把焦点留在本壳内，
                // 否则焦点停在上层的 FocusScope 上，按键根本进不到这里，
                // 整个界面就像死机一样。
                autofocus: AppMode.isTv,
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
