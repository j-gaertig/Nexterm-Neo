import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/models/managed_identity.dart';
import 'package:nexterm/models/server_details.dart';
import 'package:nexterm/utils/server_field_config.dart';

void main() {
  group('getServerFieldConfig', () {
    test('ssh allows password ssh both with terminal hooks monitoring', () {
      final c = getServerFieldConfig('server', 'ssh');
      expect(c.allowedAuthTypes, ['password', 'ssh', 'both']);
      expect(c.showTerminalSettings, isTrue);
      expect(c.showConnectionHooks, isTrue);
      expect(c.showMonitoring, isTrue);
      expect(c.showIdentities, isTrue);
    });
    test('telnet hides identities and keeps terminal', () {
      final c = getServerFieldConfig('server', 'telnet');
      expect(c.showIdentities, isFalse);
      expect(c.showTerminalSettings, isTrue);
      expect(c.showMonitoring, isFalse);
    });
    test('rdp exposes display audio performance security keyboard', () {
      final c = getServerFieldConfig('server', 'rdp');
      expect(c.allowedAuthTypes, ['password-only', 'password']);
      expect(c.showDisplaySettings, isTrue);
      expect(c.showAudioSettings, isTrue);
      expect(c.showPerformanceSettings, isTrue);
      expect(c.showRdpSecurity, isTrue);
      expect(c.showKeyboardLayout, isTrue);
    });
    test('vnc exposes display audio without keyboard performance', () {
      final c = getServerFieldConfig('server', 'vnc');
      expect(c.showDisplaySettings, isTrue);
      expect(c.showAudioSettings, isTrue);
      expect(c.showKeyboardLayout, isFalse);
      expect(c.showPerformanceSettings, isFalse);
    });
    test('sftp allows key auth without terminal', () {
      final c = getServerFieldConfig('server', 'sftp');
      expect(c.allowedAuthTypes, ['password', 'ssh', 'both']);
      expect(c.showTerminalSettings, isFalse);
    });
    test('ftp and ftps allow password only', () {
      expect(getServerFieldConfig('server', 'ftp').allowedAuthTypes, ['password']);
      expect(getServerFieldConfig('server', 'ftps').allowedAuthTypes, ['password']);
    });
  });

  group('getServerTabs', () {
    test('telnet has no identities tab', () {
      expect(getServerTabs('server', 'telnet'), ['details', 'settings']);
    });
    test('ssh has all three tabs', () {
      expect(getServerTabs('server', 'ssh'), ['details', 'identities', 'settings']);
    });
    test('rdp has all three tabs', () {
      expect(getServerTabs('server', 'rdp'), ['details', 'identities', 'settings']);
    });
    test('vnc sftp ftp ftps have identities and settings', () {
      expect(getServerTabs('server', 'vnc'), ['details', 'identities', 'settings']);
      expect(getServerTabs('server', 'sftp'), ['details', 'identities', 'settings']);
      expect(getServerTabs('server', 'ftp'), ['details', 'identities', 'settings']);
      expect(getServerTabs('server', 'ftps'), ['details', 'identities', 'settings']);
    });
  });

  group('validateServerFields', () {
    test('rejects empty name and missing ip port', () {
      expect(validateServerFields('server', 'ssh', '', {'ip': 'a', 'port': '22'}), isFalse);
      expect(validateServerFields('server', 'ssh', 'n', {'ip': '', 'port': '22'}), isFalse);
      expect(validateServerFields('server', 'ssh', 'n', {'ip': 'a', 'port': ''}), isFalse);
    });
    test('accepts complete ssh fields', () {
      expect(validateServerFields('server', 'ssh', 'n', {'ip': '1.2.3.4', 'port': '22'}), isTrue);
    });
  });

  group('IdentityDraft.toPayload', () {
    test('password-only omits username', () {
      final d = IdentityDraft(name: 'a', authType: 'password-only', password: 'p', passwordTouched: true);
      final payload = d.toPayload();
      expect(payload['type'], 'password-only');
      expect(payload.containsKey('username'), isFalse);
      expect(payload['password'], 'p');
    });
    test('rejects unparsable organizationId instead of dropping scope', () {
      final d = IdentityDraft(name: 'a', authType: 'password', organizationId: 'abc');
      expect(() => d.toPayload(), throwsException);
    });
  });

  group('protocol constants', () {
    test('covers all seven protocols with default ports', () {
      final values = ServerEditorConstants.protocols.map((p) => p['value']).toSet();
      expect(values, {'ssh', 'telnet', 'rdp', 'vnc', 'sftp', 'ftp', 'ftps'});
      for (final v in values) {
        expect(ServerEditorConstants.defaultPorts[v], isNotEmpty);
      }
    });
    test('demo hides everything', () {
      final c = getServerFieldConfig('server', 'demo');
      expect(c.showIpPort, isFalse);
      expect(c.showIdentities, isFalse);
      expect(c.showSettings, isFalse);
      expect(getServerTabs('server', 'demo'), ['details']);
    });
  });

  group('ServerDetails.fromJson', () {
    test('parses config identities folder org', () {
      final d = ServerDetails.fromJson({
        'id': 7,
        'name': 'web',
        'icon': 'mdiServer',
        'type': 'server',
        'config': {'protocol': 'ssh', 'ip': '1.2.3.4', 'port': '22'},
        'identities': [1, '2', 3.0],
        'folderId': 9,
        'organizationId': 4,
      });
      expect(d.id, 7);
      expect(d.protocol, 'ssh');
      expect(d.identities, [1, 2, 3]);
      expect(d.folderId, 9);
      expect(d.organizationId, 4);
    });
    test('tolerates missing config', () {
      final d = ServerDetails.fromJson({'id': 1, 'name': 'x'});
      expect(d.config, isEmpty);
      expect(d.identities, isEmpty);
    });
    test('unwraps map folder and org ids', () {
      final d = ServerDetails.fromJson({
        'id': 2,
        'name': 'y',
        'folderId': {'id': 9},
        'organizationId': {'id': 4},
      });
      expect(d.folderId, 9);
      expect(d.organizationId, 4);
    });
  });
}
