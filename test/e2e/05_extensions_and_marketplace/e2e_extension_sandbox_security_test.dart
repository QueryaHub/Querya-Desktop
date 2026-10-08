import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/harness/extension_harness.dart';

import 'e2e_stub_driver.dart';

const _timeout = Timeout(Duration(seconds: 60));

/// Same probe the harness uses before it wraps a plugin in `bwrap`.
bool _bwrapUsable() {
  if (!Platform.isLinux) return false;
  try {
    return Process.runSync(
            'bwrap', const ['--ro-bind', '/', '/', '/bin/true']).exitCode ==
        0;
  } catch (_) {
    return false;
  }
}

void main() {
  final skip = stubDriverSkipReason();
  late Directory root;
  late Directory hostDir;

  setUp(() {
    root = Directory.systemTemp.createTempSync('querya_e2e_sandbox_ext_');
    hostDir = Directory.systemTemp.createTempSync('querya_e2e_sandbox_host_');
  });
  tearDown(() {
    root.deleteSync(recursive: true);
    hostDir.deleteSync(recursive: true);
  });

  Future<void> runProbe({required bool sandbox}) async {
    final report = await QueryaExtensionHarness(
      shutdownTimeout: const Duration(seconds: 3),
    ).run(
      extensionRoot: root.path,
      targetVersion: '0.5.0',
      sandbox: sandbox,
    );
    expect(report.failedCount, 0, reason: report.toConsole());
  }

  test('without a sandbox the probe writes to the host (control)',
      timeout: _timeout, skip: skip, () async {
    final target = p.join(hostDir.path, 'escaped.txt');
    writeStubDriver(root, mode: 'probe', probeFile: target);

    await runProbe(sandbox: false);

    expect(File(target).existsSync(), isTrue);
  });

  test('inside bubblewrap the same write cannot reach the host filesystem',
      timeout: _timeout,
      skip: skip ?? (_bwrapUsable() ? null : 'bwrap is not usable here'),
      () async {
    final target = p.join(hostDir.path, 'escaped.txt');
    writeStubDriver(root, mode: 'probe', probeFile: target);

    await runProbe(sandbox: true);

    expect(File(target).existsSync(), isFalse);
    expect(hostDir.listSync(), isEmpty);
  });
}
