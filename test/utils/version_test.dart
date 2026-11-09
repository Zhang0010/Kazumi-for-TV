import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/version.dart';

void main() {
  group('needUpdate', () {
    test('基础数字比较', () {
      expect(needUpdate('2.4.3', '2.4.4'), isTrue);
      expect(needUpdate('2.4.3', '2.5.0'), isTrue);
      expect(needUpdate('2.4.3', '2.4.3'), isFalse);
      expect(needUpdate('2.4.3', '2.4.2'), isFalse);
    });

    test('预发布后缀不再抛异常', () {
      expect(() => needUpdate('1.0.1-beta', '1.0.1-beta'), returnsNormally);
      expect(needUpdate('1.0.1-beta', '1.0.1-beta'), isFalse);
      expect(needUpdate('1.0.1-beta', '1.0.2'), isTrue);
      expect(needUpdate('1.0.1-beta', '1.0.1'), isTrue);
      expect(needUpdate('1.0.1', '1.0.1-beta'), isFalse);
    });

    test('v 前缀与构建号', () {
      expect(needUpdate('1.0.1-beta', 'v1.0.2'), isTrue);
      expect(needUpdate('1.0.1-beta', 'v1.0.1-beta'), isFalse);
      expect(needUpdate('1.0.1-beta+20404', '1.0.1-beta'), isFalse);
    });

    test('段落数量不同时按缺省 0 处理', () {
      expect(needUpdate('1.0', '1.0.1'), isTrue);
      expect(needUpdate('1.0.1', '1.0'), isFalse);
    });
  });
}
