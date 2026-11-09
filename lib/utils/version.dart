import 'dart:math';

/// 比较两个版本号，remote 比 local 新时返回 true。
///
/// 版本号可能带前缀和后缀（`v1.0.1`、`1.0.1-beta`、`1.0.1+build`），
/// 之前直接 `int.parse` 每个 `.` 分段，遇到 `1-beta` 会抛 FormatException，
/// 检查更新整条链路就废了。这里只取每段开头的数字比较，后缀按预发布处理：
/// 数字相同的情况下，带后缀的算更旧（1.0.1-beta < 1.0.1）。
bool needUpdate(String localVersion, String remoteVersion) {
  final local = _parse(localVersion);
  final remote = _parse(remoteVersion);
  final maxLength = max(local.numbers.length, remote.numbers.length);
  for (var i = 0; i < maxLength; i++) {
    final localSegment = i < local.numbers.length ? local.numbers[i] : 0;
    final remoteSegment = i < remote.numbers.length ? remote.numbers[i] : 0;
    if (remoteSegment > localSegment) {
      return true;
    } else if (remoteSegment < localSegment) {
      return false;
    }
  }
  if (local.prerelease.isNotEmpty && remote.prerelease.isEmpty) {
    return true;
  }
  return false;
}

class _Version {
  const _Version(this.numbers, this.prerelease);

  final List<int> numbers;
  final String prerelease;
}

_Version _parse(String version) {
  var text = version.trim();
  if (text.startsWith('v') || text.startsWith('V')) {
    text = text.substring(1);
  }
  // 构建号（+xxx）不参与比较
  final plus = text.indexOf('+');
  if (plus >= 0) text = text.substring(0, plus);
  final dash = text.indexOf('-');
  final core = dash >= 0 ? text.substring(0, dash) : text;
  final prerelease = dash >= 0 ? text.substring(dash + 1) : '';
  final numbers = <int>[
    for (final segment in core.split('.')) _leadingDigits(segment),
  ];
  return _Version(numbers, prerelease);
}

int _leadingDigits(String segment) {
  final match = RegExp(r'^\d+').firstMatch(segment.trim());
  if (match == null) return 0;
  return int.tryParse(match.group(0)!) ?? 0;
}
