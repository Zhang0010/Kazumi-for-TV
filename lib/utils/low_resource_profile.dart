import 'dart:ui';

import 'package:kazumi/utils/app_mode.dart';

/// 低配电视的性能裁剪（4×Cortex-A53 / 2~3 GB RAM 这档机器）。
///
/// 电视形态统一走一套"够看就行"的取值：这些机器 GPU 是 Mali-G31 级别、
/// 内存还要留给 libmpv 解码，Flutter 默认面向手机 / 桌面的开销放在这儿
/// 会直接表现成滚动掉帧、开机被系统杀进程。
///
/// 手机 / 平板 / 桌面形态一项都不改，保持原有观感。
class LowResourceProfile {
  const LowResourceProfile._();

  /// 是否启用低配裁剪（当前只对电视形态生效）。
  static bool get enabled => AppMode.isTv;

  /// Flutter 图片解码缓存上限。默认 100 MB / 1000 张，一屏海报最多十几张，
  /// 2.5 GB 的机器上这份缓存是白占，还会挤压播放器与系统。
  static int get imageCacheBytes => enabled ? 48 << 20 : 100 << 20;
  static int get imageCacheCount => enabled ? 200 : 1000;

  /// 电视上的图片解码倍率（相对逻辑像素）。默认按设备像素比解码（dpr = 2，
  /// 一张海报 320×492），实测滚动的瓶颈就在这一步；收到 1.5（240×369）
  /// 掉帧比例明显下降，再降到 1.0 观感就发虚了，取 1.5 折中。
  static const double imageDecodeScale = 1.5;

  /// 图片采样质量。电视上是全屏铺开、观看距离 3 米开外，
  /// 双线性（low）与 high 肉眼无差，但每帧采样开销差一档。
  static FilterQuality get imageFilterQuality =>
      enabled ? FilterQuality.low : FilterQuality.high;

  /// 播放器解复用缓存（media_kit 的 `demuxer-max-bytes`）。
  /// 上游默认 1.5 GB，在 2.5 GB 的电视上等于把内存预算吃光；
  /// 64 MB 足够覆盖网络抖动，低了反而更容易卡。
  static int get videoBufferBytes => enabled ? 64 << 20 : 1500 << 20;

  /// 是否用短转场替代滑动转场。滑动转场要同时合成前后两整页，
  /// 弱 GPU 上是导航掉帧的主要来源。
  static bool get useShortRouteTransitions => enabled;

  /// 是否保留 Hero 共享元素动画（飞行期间要渲染两份大图）。
  static bool get enableHeroAnimations => !enabled;
}
