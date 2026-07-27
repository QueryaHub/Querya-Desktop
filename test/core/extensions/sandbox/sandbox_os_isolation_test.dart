import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_launch_command.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_os_isolation.dart';

void main() {
  group('SandboxOsIsolation', () {
    test('returns null when launch command uses OS sandbox', () {
      final command = SandboxLaunchCommand.build(
        pluginExecutable: '/bin/driver',
        scratchPath: '/tmp/s',
        platformOverride: 'linux',
        bwrapAvailable: true,
      );

      expect(
        SandboxOsIsolation.exceptionForLaunchCommand(command),
        isNull,
      );
    });

    test('returns linux message when bwrap unavailable', () {
      final command = SandboxLaunchCommand.build(
        pluginExecutable: '/bin/driver',
        scratchPath: '/tmp/s',
        platformOverride: 'linux',
        bwrapAvailable: false,
      );

      final error = SandboxOsIsolation.exceptionForLaunchCommand(command);
      expect(error, isNotNull);
      expect(error!.platform, 'linux');
      expect(error.message, contains('bubblewrap'));
    });

    test('returns windows message for soft isolation path', () {
      final command = SandboxLaunchCommand.build(
        pluginExecutable: r'C:\driver.exe',
        scratchPath: r'C:\tmp\s',
        platformOverride: 'windows',
      );

      final error = SandboxOsIsolation.exceptionForLaunchCommand(command);
      expect(error, isNotNull);
      expect(error!.platform, 'windows');
      expect(error.message, contains('Windows'));
    });
  });
}
