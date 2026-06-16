import 'package:flutter/widgets.dart';
import 'package:refresh_rate/refresh_rate.dart';

import 'src/example_app.dart';
export 'src/example_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  RefreshRate.enable();
  runApp(const RefreshRateExampleApp());
}
