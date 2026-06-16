import 'package:flutter/material.dart';

import 'example_home.dart';
import 'example_theme.dart';

class RefreshRateExampleApp extends StatelessWidget {
  const RefreshRateExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'refresh_rate example',
      debugShowCheckedModeBanner: false,
      theme: buildExampleTheme(),
      home: const ExampleHome(),
    );
  }
}
