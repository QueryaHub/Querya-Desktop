import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/layout/window_layout.dart';

void main() {
  testWidgets('dialogConstraints scales with QueryaUiScaleScope',
      (tester) async {
    await tester.pumpWidget(
      QueryaUiScaleScope(
        scale: 1.25,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              final c = WindowLayout.dialogConstraints(
                context,
                maxWidth: 480,
                minWidth: 360,
                maxHeight: 640,
              );
              expect(c.maxWidth, 600);
              expect(c.minWidth, 450);
              expect(c.maxHeight, 800);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  });

  testWidgets('scaledDialogExtent applies scale before viewport clamp',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => QueryaUiScaleScope(
          scale: 1.25,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (context) {
            final extent = WindowLayout.scaledDialogExtent(
              context,
              screenExtent: 2000,
              insetTotal: 100,
              baseMax: 480,
              baseMin: 200,
            );
            expect(extent, 600);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
