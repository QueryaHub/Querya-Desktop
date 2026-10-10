import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_manager.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/features/connections/connection_edit_secrets.dart';
import 'package:querya_desktop/features/connections/ssh_tunnel_section.dart';

import '../../memory_secrets_backend.dart';
import '../../support/fake_ssh.dart';
import '../../support/querya_theme_test_shell.dart';

/// #1302: Test Connection of an edited connection uses the saved secrets for
/// the fields left blank, and never hands the form's own secrets to a tunnel.
void main() {
  setUp(() {
    ConnectionSecretsStore.profileId = 'test-profile';
    testMemorySecrets.clear();
  });

  group('secretsForConnectionTest', () {
    test('a blank password is the saved one, a typed one wins', () async {
      await ConnectionSecretsStore.writeForConnection(5, password: 'saved');

      final blank = await secretsForConnectionTest(
        connectionId: 5,
        password: null,
        connectionString: null,
        sshSecrets: null,
      );
      expect(blank.password, 'saved');

      final typed = await secretsForConnectionTest(
        connectionId: 5,
        password: 'typed',
        connectionString: null,
        sshSecrets: null,
      );
      expect(typed.password, 'typed');
    });

    test('the saved password is put into a URI the form shows without it',
        () async {
      await ConnectionSecretsStore.writeForConnection(5, password: 'p@ss');

      final r = await secretsForConnectionTest(
        connectionId: 5,
        password: null,
        connectionString: 'postgresql://admin@db.example.com:5432/app',
        sshSecrets: null,
      );

      final uri = Uri.parse(r.connectionString!);
      expect(uri.userInfo, startsWith('admin:'));
      expect(Uri.decodeComponent(uri.userInfo.split(':').last), 'p@ss');
    });

    test('blank SSH fields are the saved ones, as a copy', () async {
      await ConnectionSecretsStore.writeSshSecretsForConnection(
        5,
        password: 'ssh-saved',
        privateKey: 'key-saved',
      );
      final form = SshTunnelSecrets(passphrase: 'typed-phrase');

      final r = await secretsForConnectionTest(
        connectionId: 5,
        password: null,
        connectionString: null,
        sshSecrets: form,
      );

      expect(r.sshSecrets!.password, 'ssh-saved');
      expect(r.sshSecrets!.privateKey, 'key-saved');
      expect(r.sshSecrets!.passphrase, 'typed-phrase');
      expect(identical(r.sshSecrets, form), isFalse);
      // The form's own object is untouched.
      expect(form.password, isNull);
    });

    test('a new connection (no id) tests with what was typed, as a copy',
        () async {
      final form = SshTunnelSecrets(password: 'typed');
      final r = await secretsForConnectionTest(
        connectionId: null,
        password: 'pw',
        connectionString: null,
        sshSecrets: form,
      );
      expect(r.password, 'pw');
      expect(r.sshSecrets!.password, 'typed');
      // A tunnel zeroes what it is given: that must not be the form's object.
      r.sshSecrets!.zero();
      expect(form.password, 'typed');
    });

    test('nothing is read or written for an unsaved connection', () async {
      await ConnectionSecretsStore.writeForConnection(0, password: 'other');
      final r = await secretsForConnectionTest(
        connectionId: 0,
        password: null,
        connectionString: null,
        sshSecrets: null,
      );
      expect(r.password, isNull);
    });
  });

  group('Test SSH connection in the tunnel section', () {
    late FakeSshServer server;
    late SshTunnelManager original;

    setUp(() {
      server = FakeSshServer(password: 'ssh-saved');
      original = SshTunnelManager.instance;
      SshTunnelManager.instance = SshTunnelManager.forTesting(
        connector: server.connect,
        clientBuilder: server.build,
      );
    });

    tearDown(() => SshTunnelManager.instance = original);

    Future<void> pumpSection(
      WidgetTester t, {
      required int? connectionId,
      required SshTunnelSecrets secrets,
    }) async {
      await t.binding.setSurfaceSize(const material.Size(900, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(queryaThemeTestShell(
        child: material.SingleChildScrollView(
          child: SshTunnelSection(
            config: const SshTunnelConfig(
              enabled: true,
              host: 'bastion.example',
              port: 22,
              username: 'deploy',
            ),
            secrets: secrets,
            onChanged: (_) {},
            connectionId: connectionId,
          ),
        ),
      ));
      await t.pump();
    }

    Future<void> runTest(WidgetTester t) async {
      await t.tap(find.text('Test SSH Connection'));
      for (var i = 0; i < 40; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)));
        await t.pump();
        if (find.textContaining('Connected').evaluate().isNotEmpty ||
            find.textContaining('failed').evaluate().isNotEmpty) {
          break;
        }
      }
    }

    testWidgets('an edited tunnel connects with the saved password',
        (t) async {
      await ConnectionSecretsStore.writeSshSecretsForConnection(
        9,
        password: 'ssh-saved',
      );
      await pumpSection(t, connectionId: 9, secrets: SshTunnelSecrets());

      await runTest(t);

      expect(find.textContaining('Connected'), findsOneWidget);
    });

    testWidgets('a new tunnel with a blank password still fails', (t) async {
      await pumpSection(t, connectionId: null, secrets: SshTunnelSecrets());

      await runTest(t);

      expect(find.textContaining('Connected'), findsNothing);
      expect(find.textContaining('failed'), findsOneWidget);
    });
  });
}
