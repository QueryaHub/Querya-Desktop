import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/storage/local_db.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDb.initFfi();
  runApp(const QueryaApp());
  doWhenWindowReady(() {
    final win = appWindow;
    win.minSize = const Size(900, 600);
    win.size = const Size(1280, 720);
    win.alignment = Alignment.center;
    win.title = 'Querya';
    win.show();
  });
}
