import 'package:flutter/material.dart';
import 'package:kazumi/utils/low_resource_profile.dart';

extension ImageExtension on num {
  /// 解码尺寸（物理像素）。
  ///
  /// 电视形态按 [LowResourceProfile.imageDecodeScale] 收一档：1080p 投影上
  /// 观看看距 3 米开外，少一两百万像素的解码与上传换来的是滚动的帧率
  /// （这台 MT9653 的瓶颈就在图像解码与纹理上传，不在布局）。
  int cacheSize(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final scale =
        LowResourceProfile.enabled ? LowResourceProfile.imageDecodeScale : dpr;
    return (this * scale).round();
  }
}
