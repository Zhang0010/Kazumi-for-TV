import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/platform/platform_environment_service.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 界面形态。
enum AppInterfaceMode {
  /// 跟随构建（TV 包 → 电视形态；手机包 → 手机形态）
  auto,

  /// 强制电视形态（遥控器 UX、无触摸、无 hover）
  tv,

  /// 强制手机 / 桌面形态
  phone,
}

/// 全局形态状态。
///
/// 本仓库是「Kazumi For TV」：**默认就是电视形态**，构建开关
/// `KAZUMI_TV` 默认 true，启动时不做任何设备条件判定 —— 判定的结果
/// 只取决于一个编译期常量，永远不会因为开机竞态、通道没就绪这类
/// 外部原因漂移成手机布局。
///
/// 判定顺序：
/// 1. 设置里的「界面模式」覆盖项（电视 / 手机，用户显式选择才算数）
/// 2. 构建开关 `KAZUMI_TV`（默认 true）
/// 3. 非电视构建（`--dart-define=KAZUMI_TV=false`）才走设备探测兜底
class AppMode {
  AppMode._();

  /// 构建开关默认 true：出手机 / 平板包时显式传
  /// `--dart-define=KAZUMI_TV=false` 才关掉电视形态。
  static const bool _buildFlagTv = bool.fromEnvironment(
    'KAZUMI_TV',
    defaultValue: true,
  );

  static bool _isTv = _buildFlagTv;

  /// 最近一次形态判定的说明，设置 → 界面 会展示它，方便一眼看出
  /// 这次是「TV 包默认电视」「用户手动选电视 / 手机」还是「探测」。
  static String detectionReport = _buildFlagTv ? 'TV 包默认电视形态' : '尚未判定';

  /// 是否电视形态。
  static bool get isTv => _isTv;

  /// 触摸 / 鼠标交互是否可用（TV 形态下为 false）。
  static bool get hasPointerInput => !_isTv;

  /// 桌面平台（Windows / macOS / Linux）。
  static bool get isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// 启动时调用一次，确定本次运行的形态。
  ///
  /// 电视包里这一步不碰设备、不发通道调用：只读一次设置里的覆盖项。
  static Future<void> initialize() async {
    final mode = _storedMode();
    if (mode == AppInterfaceMode.tv) {
      _isTv = true;
      detectionReport = '设置：电视模式';
      return;
    }
    if (mode == AppInterfaceMode.phone) {
      _isTv = false;
      detectionReport = '设置：手机 / 平板模式';
      return;
    }
    if (_buildFlagTv) {
      _isTv = true;
      detectionReport = 'TV 包默认电视形态';
      return;
    }
    if (!Platform.isAndroid) {
      _isTv = false;
      detectionReport = '非 Android 平台';
      return;
    }
    // 只有显式关掉构建开关的包才需要问设备（手机包的「自动」）。
    final detected = await _detectTvDeviceWithRetry();
    final remembered = _rememberedDetection();
    _isTv = detected ?? remembered ?? false;
    detectionReport = detected == null
        ? '设备探测无应答，沿用上次结果 ${_describe(remembered)}'
        : '设备探测：${detected ? "电视" : "手机"}';
    if (detected != null) _rememberDetection(detected);
  }

  static String _describe(bool? value) => switch (value) {
        true => '电视',
        false => '手机',
        null => '无',
      };

  static Future<bool?> _detectTvDeviceWithRetry({
    int attempts = 3,
    Duration delay = const Duration(milliseconds: 300),
  }) async {
    for (var i = 0; i < attempts; i++) {
      try {
        return await PlatformEnvironmentService.isTvDevice();
      } catch (error) {
        if (i == attempts - 1) {
          KazumiLogger().w('AppMode: isTvDevice 探测失败', error: error);
          return null;
        }
        await Future<void>.delayed(delay);
      }
    }
    return null;
  }

  /// 上次成功探测到的形态；-1 未知 / 0 非电视 / 1 电视。
  static bool? _rememberedDetection() {
    try {
      return switch (GStorage.getSetting(SettingsKeys.detectedTvDevice)) {
        1 => true,
        0 => false,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  static void _rememberDetection(bool isTv) {
    try {
      unawaited(GStorage.putSetting(SettingsKeys.detectedTvDevice, isTv ? 1 : 0));
    } catch (_) {
      // 存不下去也不影响本次判定。
    }
  }

  static AppInterfaceMode _storedMode() {
    try {
      final raw = GStorage.getSetting(SettingsKeys.interfaceMode);
      return switch (raw) {
        1 => AppInterfaceMode.tv,
        2 => AppInterfaceMode.phone,
        _ => AppInterfaceMode.auto,
      };
    } catch (_) {
      return AppInterfaceMode.auto;
    }
  }

  /// 当前设置里保存的覆盖项。
  static AppInterfaceMode get storedMode => _storedMode();

  /// 保存覆盖项（需要重启生效，重启前只影响下次判定）。
  static Future<void> setMode(AppInterfaceMode mode) async {
    await GStorage.putSetting(
      SettingsKeys.interfaceMode,
      switch (mode) {
        AppInterfaceMode.auto => 0,
        AppInterfaceMode.tv => 1,
        AppInterfaceMode.phone => 2,
      },
    );
  }

  /// 探测到的真实设备形态（不受设置覆盖影响），用于设置页展示。
  static Future<bool> detectTvDevice() async {
    if (!Platform.isAndroid) return false;
    final detected = await _detectTvDeviceWithRetry();
    return detected ?? _rememberedDetection() ?? false;
  }
}
