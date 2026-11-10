import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/app_module.dart';
import 'package:kazumi/app_widget.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/services/deep_links/app_deep_links.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/download/download_directory_service.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/services/network/metered_network_service.dart';
import 'package:kazumi/services/network/ech_http_licenses.dart';
import 'package:kazumi/services/network/proxy_manager.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/pages/error/storage_error_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/app_mode.dart';
import 'package:kazumi/utils/low_resource_profile.dart';
import 'package:kazumi/services/platform/desktop_window_config.dart';
import 'package:kazumi/services/platform/webview_feature_service.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/navigation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先把第一帧画出来：这台电视上如果卡在初始化里几十秒都不出帧，系统会判定
  // 「没有焦点窗口」直接把进程 ANR 掉，用户看到的就是点开闪退/白屏。
  // 起一个纯色启动页顶住，初始化完成后再换成真正的 App。
  runApp(const _BootSplash());
  AppDeepLinks().start();
  registerEchHttpLicenses();
  MediaKit.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
      ),
    );
  }

  if (Platform.isAndroid) {
    // 电视上的 WebView 探测通道偶尔不回声，等它等于拿首帧陪葬；这个特性只影响
    // 注入脚本时机，探测不到就按不支持处理。
    await WebViewFeatureService.initialize()
        .timeout(const Duration(seconds: 2))
        .catchError((Object error) {
          debugPrint('WebView feature probe failed: $error');
        });
  }

  try {
    // 存储初始化给个上限：文件系统卡住时宁可弹「初始化失败」，也不要白屏等着
    // 被系统 ANR 掉。
    final supportDir = await getApplicationSupportDirectory().timeout(
      const Duration(seconds: 6),
    );
    final hivePath = '${supportDir.path}/hive';
    await Hive.initFlutter(hivePath).timeout(const Duration(seconds: 6));
    await GStorage.init().timeout(const Duration(seconds: 6));
  } catch (e) {
    debugPrint('Storage initialization failed: $e');

    if (isDesktop()) {
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow(null, () async {
        // window_manager controls desktop visibility to avoid startup flicker.
        await windowManager.show();
        await windowManager.focus();
      });
    }
    runApp(
      MaterialApp(
        title: '初始化失败',
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [
          Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
            countryCode: "CN",
          ),
        ],
        locale: const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: "CN",
        ),
        builder: (context, child) {
          return const StorageErrorPage();
        },
      ),
    );
    return;
  }
  // 形态判定放在存储就绪之后：探测通道失败时要能读上次的结果兜底，
  // 否则冷启动竞态会让电视静默退回手机布局。
  await AppMode.initialize();
  if (Platform.isAndroid && AppMode.isTv) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]).timeout(const Duration(seconds: 1), onTimeout: () {});
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    ).timeout(const Duration(seconds: 1), onTimeout: () {});
  }
  // 图片解码缓存按形态收口：电视上 48 MB / 200 张就够，
  // 默认的 100 MB / 1000 张在 2.5 GB 的机子上是纯浪费。
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSizeBytes = LowResourceProfile.imageCacheBytes;
  imageCache.maximumSize = LowResourceProfile.imageCacheCount;

  if (LowResourceProfile.enabled) {
    // 下载目录授权与首屏无关，挪到首帧之后，冷启动少等一次 IPC。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DownloadDirectoryService().restoreAccess().ignore();
    });
  } else {
    await DownloadDirectoryService().restoreAccess();
  }
  final showWindowButton = DesktopWindowConfig.showWindowButton;
  if (isDesktop()) {
    await windowManager.ensureInitialized();
    final lowResolution = await isLowResolution();
    final windowOptions = WindowOptions(
      size: lowResolution ? const Size(840, 600) : const Size(1280, 860),
      center: true,
      skipTaskbar: false,
      // macOS embeds native buttons in the Flutter view.
      titleBarStyle: (Platform.isMacOS || !showWindowButton)
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: showWindowButton,
      title: 'Kazumi',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // window_manager controls desktop visibility to avoid startup flicker.
      await windowManager.show();
      await windowManager.focus();
    });
  }
  if (Platform.isWindows) {
    SystemProxyService.init();
  }
  // 网络类型探测只影响「移动网络下载」提示，不该挡住首屏。
  await MeteredNetworkService.refresh().timeout(
    const Duration(seconds: 3),
    onTimeout: () {},
  );
  ProxyManager.applyProxy();
  runApp(
    ModularApp(
      module: appModule,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [KazumiDialog.observer, rootRouteObserver],
      defaultTransition: TransitionType.material,
      provide: (scoped) {
        scoped.addChangeNotifier<ThemeProvider>(ThemeProvider.new);
      },
      child: const AppWidget(),
    ),
  );
}

/// 初始化期间顶住屏幕的启动页：只为让窗口尽快拿到第一帧，
/// 避免初始化慢的设备被判成「无响应」直接杀掉进程。
class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: Color(0xFF101010),
        child: Center(
          child: SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ),
    );
  }
}
