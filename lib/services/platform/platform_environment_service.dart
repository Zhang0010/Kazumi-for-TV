import 'dart:io';

import 'package:flutter/services.dart';
import 'package:kazumi/services/logging/logger.dart';

class PlatformEnvironmentService {
  PlatformEnvironmentService._();

  static const _intentChannel = MethodChannel('com.predidit.kazumi/intent');

  static Future<bool> isRunningOnX11() async {
    if (!Platform.isLinux) {
      return false;
    }
    try {
      return await _intentChannel.invokeMethod('isRunningOnX11');
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to check X11 environment: '${e.message}'.");
      return false;
    }
  }

  static Future<int> getAndroidSdkVersion() async {
    if (!Platform.isAndroid) {
      return 0;
    }
    try {
      return await _intentChannel.invokeMethod('getAndroidSdkVersion');
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to get Android SDK version: '${e.message}'.");
      return 0;
    }
  }

  /// 是否电视类设备（Leanback / UiMode=TELEVISION / 无触摸屏）。
  ///
  /// 通道本身失败时**不吞异常**：调用方必须能区分「设备不是电视」和
  /// 「这次没问出来」（冷启动时插件通道可能还没就绪）。后者如果被当成
  /// false，电视上就会静默退回手机布局，且要等下次冷启动才恢复。
  static Future<bool> isTvDevice() async {
    if (!Platform.isAndroid) {
      return false;
    }
    return await _intentChannel.invokeMethod<bool>('isTvDevice') ?? false;
  }
}
