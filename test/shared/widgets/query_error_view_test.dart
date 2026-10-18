import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/query_error_text.dart';
import 'package:querya_desktop/shared/widgets/query_error_view.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  Future<void> pump(WidgetTester t, String raw, {bool inline = false}) async {
    await t.binding.setSurfaceSize(const material.Size(800, 600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(queryaThemeTestShell(
      child: material.SizedBox.expand(
        child: material.Center(
          child: QueryErrorView(error: QueryErrorText.parse(raw), inline: inline),
        ),
      ),
    ));
  }

  const raw = 'MongoDartError: Could not run the command\n'
      'at db.users.find()\nserver said: unauthorized';

  testWidgets('the headline first, the rest behind Show details', (t) async {
    await pump(t, raw);
    expect(find.text('Query Error'), findsOneWidget);
    expect(find.text('MongoDartError: Could not run the command'),
        findsOneWidget);
    expect(find.textContaining('unauthorized'), findsNothing);

    await t.tap(find.text('Show details'));
    await t.pump();
    expect(find.textContaining('unauthorized'), findsWidgets);
    await t.tap(find.text('Hide details'));
    await t.pump();
    expect(find.textContaining('unauthorized'), findsNothing);
  });

  testWidgets('Copy error puts the whole text on the clipboard', (t) async {
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pump(t, raw);

    await t.tap(find.text('Copy error'));
    await t.pump();
    expect(copied, raw);
    expect(find.text('Copied'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(find.text('Copy error'), findsOneWidget);
  });

  testWidgets('inline has no title of its own: the box around it has one',
      (t) async {
    await pump(t, raw, inline: true);
    expect(find.text('Query Error'), findsNothing);
    expect(find.text('MongoDartError: Could not run the command'),
        findsOneWidget);
  });

  testWidgets('a one-line error has no details or copy', (t) async {
    await pump(t, 'collection not found');
    expect(find.text('collection not found'), findsOneWidget);
    expect(find.text('Show details'), findsNothing);
  });

  testWidgets('a new error closes the details', (t) async {
    await pump(t, raw);
    await t.tap(find.text('Show details'));
    await t.pump();
    await pump(t, '$raw\nsecond');
    expect(find.text('Show details'), findsOneWidget);
  });
}
