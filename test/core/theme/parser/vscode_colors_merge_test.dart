import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/vscode_colors_merge.dart';

void main() {
  group('mergeVsCodeColorLayers', () {
    test('empty layers yields empty map', () {
      expect(mergeVsCodeColorLayers([]), isEmpty);
    });

    test('later layers override earlier keys', () {
      final merged = mergeVsCodeColorLayers([
        {'editor.background': '#111111', 'sideBar.background': '#222222'},
        {'editor.background': '#333333', 'panel.background': '#444444'},
        {'sideBar.background': '#ff0000'},
      ]);
      expect(merged['editor.background'], '#333333');
      expect(merged['panel.background'], '#444444');
      expect(merged['sideBar.background'], '#ff0000');
    });

    test('result is unmodifiable', () {
      final merged = mergeVsCodeColorLayers([
        {'a': '#111111'},
      ]);
      expect(
        () => merged['b'] = '#222222',
        throwsUnsupportedError,
      );
    });
  });
}
