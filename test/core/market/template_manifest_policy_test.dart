import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/extension_support.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_policy.dart';

/// `manifest.json` of QueryaHub/extension-template. A starting point that the
/// app then refuses to install (or shows as a "Preview" listing) would defeat
/// it, so this pins the template to the app's sandbox policy.
const _templateManifest = '''
{
  "manifestVersion": 1,
  "id": "example.redis-template",
  "name": "Example driver (template)",
  "version": "0.1.0",
  "publisher": "Your Name",
  "type": "database_driver",
  "main": "bin/querya-example-driver",
  "engines": { "querya_desktop": ">=0.4.19" },
  "capabilities": { "databaseDriver": true },
  "sandbox": {
    "engine": "process",
    "permissions": {
      "network": { "mode": "connection_host_only", "allow_ssl": false },
      "filesystem": { "scratch_mb": 10, "access": "scratch_only" },
      "resources": { "memory_mb": 128, "max_open_files": 32, "timeout_seconds": 60 }
    }
  },
  "contributions": {
    "drivers": [
      {
        "driverId": "example-redis",
        "displayName": "Example (Redis protocol)",
        "defaultPort": 6379,
        "connectionFormSchema": "assets/connection_form.json"
      }
    ]
  }
}
''';

void main() {
  test('the extension template is installable under the sandbox policy', () {
    final manifest = ExtensionManifest.fromJson(
      jsonDecode(_templateManifest) as Map<String, dynamic>,
    );
    expect(manifest.manifestVersion, 1);
    expect(ExtensionSupport.manifestFormatProblem(manifest), isNull);
    expect(SandboxPolicy.validate(manifest), isEmpty);
    expect(ExtensionSupport.isPreviewOnlyManifest(manifest), isFalse);
  });
}
