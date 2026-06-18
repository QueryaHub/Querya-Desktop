import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/app_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('QueryaThemeScope provides workbench tokens', (tester) async {
    late Color seenAccent;

    await tester.pumpWidget(
      ShadcnApp(
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: QueryaThemeScope(
          data: QueryaTheme.darkDefault,
          child: material.Builder(
            builder: (context) {
              seenAccent = context.workbench.accent;
              return const material.SizedBox();
            },
          ),
        ),
      ),
    );

    expect(seenAccent, QueryaTheme.darkDefault.workbench.accent);
  });

  testWidgets('QueryaThemeScope rebuilds when data changes', (tester) async {
    var canvas = QueryaTheme.darkDefault.workbench.canvas;

    await tester.pumpWidget(
      _ScopeHost(
        data: QueryaTheme.darkDefault,
        onCanvas: (c) => canvas = c,
      ),
    );

    const light = QueryaTheme.lightDefault;
    await tester.pumpWidget(
      _ScopeHost(
        data: light,
        onCanvas: (c) => canvas = c,
      ),
    );

    expect(canvas, light.workbench.canvas);
    expect(canvas, isNot(QueryaTheme.darkDefault.workbench.canvas));
  });
}

class _ScopeHost extends StatelessWidget {
  const _ScopeHost({
    required this.data,
    required this.onCanvas,
  });

  final QueryaTheme data;
  final ValueChanged<Color> onCanvas;

  @override
  Widget build(BuildContext context) {
    return ShadcnApp(
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: QueryaThemeScope(
        data: data,
        child: material.Builder(
          builder: (context) {
            onCanvas(context.workbench.canvas);
            return const material.SizedBox();
          },
        ),
      ),
    );
  }
}
