import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kazumi/services/platform/platform_environment_service.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 界面形态。同一份代码同时支持手机 / 桌面 / 电视，运行时判定。
enum AppInterfaceMode {
  /// 自动判定（默认）
  auto,

  /// 强制电视形态（遥控器 UX、无触摸、无 hover）
  tv,

  /// 强制手机 / 桌面形态
  phone,
}

/// 全局形态状态。
///
/// 判定顺序：
/// 1. 构建开关 `--dart-define=KAZUMI_TV=true`（出 TV 专用包时用）
/// 2. 设置里的「界面模式」覆盖项
/// 3. 平台通道探测：Leanback / UiMode=TV / 无触摸屏
class AppMode {
  AppMode._();

  static const bool _buildFlagTv = bool.fromEnvironment(
    'KAZUMI_TV',
    defaultValue: false,
  );

  static bool _isTv = _buildFlagTv;

  /// 是否电视形态。
  static bool get isTv => _isTv;

  /// 触摸 / 鼠标交互是否可用（TV 形态下为 false）。
  static bool get hasPointerInput => !_isTv;

  /// 桌面平台（Windows / macOS / Linux）。
  static bool get isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// 启动时调用一次，确定本次运行的形态。
  static Future<void> initialize() async {
    if (_buildFlagTv) {
      _isTv = true;
      return;
    }
    if (!Platform.isAndroid) {
      _isTv = false;
      return;
    }
    final mode = _storedMode();
    if (mode == AppInterfaceMode.tv) {
      _isTv = true;
      return;
    }
    if (mode == AppInterfaceMode.phone) {
      _isTv = false;
      return;
    }
    try {
      _isTv = await PlatformEnvironmentService.isTvDevice();
    } catch (_) {
      _isTv = false;
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
    try {
      return await PlatformEnvironmentService.isTvDevice();
    } catch (_) {
      return false;
    }
  }
}
