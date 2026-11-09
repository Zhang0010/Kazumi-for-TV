import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/tv_slider_keys.dart';

/// 电视上滑块会把 ↑↓ 当成调值，焦点进去就出不来。
/// 这里守住两件事：↑↓ 能走去别的控件，←→ 仍然调节滑块。
void main() {
  testWidgets('上下键把焦点移出滑块，左右键仍交给滑块调值', (tester) async {
    final sliderFocus = FocusNode(debugLabel: 'slider');
    final belowFocus = FocusNode(debugLabel: 'below');
    addTearDown(sliderFocus.dispose);
    addTearDown(belowFocus.dispose);

    var value = 1.0;
    TvSliderKeys.install();
    addTearDown(TvSliderKeys.uninstall);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              StatefulBuilder(
                builder: (context, setState) => Slider(
                  value: value,
                  min: 0,
                  max: 2,
                  divisions: 4,
                  focusNode: sliderFocus,
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
              Focus(
                focusNode: belowFocus,
                child: const SizedBox(
                  width: 120,
                  height: 48,
                  child: Text('below'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    sliderFocus.requestFocus();
    await tester.pump();
    expect(sliderFocus.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      sliderFocus.hasPrimaryFocus,
      isFalse,
      reason: '下键应该把焦点送出滑块',
    );
    expect(belowFocus.hasPrimaryFocus, isTrue);

    // 回滑块，左右键必须还能调值
    sliderFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(value, greaterThan(1.0), reason: '右键仍应调节滑块数值');
  });

  // 回归基线：不装拦截时，Flutter 的 Slider 会把 ↑↓ 也当成调值，
  // 焦点因此留在滑块上 —— 这就是「焦点进滑块就出不来」的真因。
  testWidgets('未装拦截时上下键被滑块吃掉', (tester) async {
    final sliderFocus = FocusNode(debugLabel: 'slider-raw');
    final belowFocus = FocusNode(debugLabel: 'below-raw');
    addTearDown(sliderFocus.dispose);
    addTearDown(belowFocus.dispose);

    var value = 1.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              StatefulBuilder(
                builder: (context, setState) => Slider(
                  value: value,
                  min: 0,
                  max: 2,
                  divisions: 4,
                  focusNode: sliderFocus,
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
              Focus(
                focusNode: belowFocus,
                child: const SizedBox(
                  width: 120,
                  height: 48,
                  child: Text('below'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    sliderFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(sliderFocus.hasPrimaryFocus, isTrue);
  });
}
