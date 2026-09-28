import 'package:flutter_test/flutter_test.dart';

import 'package:jterm/core/models/forward_rule.dart';
import 'package:jterm/core/models/macro.dart';
import 'package:jterm/core/models/session_profile.dart';
import 'package:jterm/core/ssh/ssh_config_import.dart';
import 'package:jterm/core/terminal/osc7.dart';

void main() {
  test('SessionProfile JSON round-trip', () {
    final p = SessionProfile(
      id: 's1',
      name: 'prod-web',
      type: SessionType.ssh,
      host: '10.0.0.1',
      port: 2222,
      username: 'root',
      x11Forwarding: true,
      group: '生产/华东',
      forwards: [
        ForwardRule(
          id: 'f1',
          type: ForwardType.local,
          localPort: 8080,
          remoteHost: '127.0.0.1',
          remotePort: 80,
        ),
      ],
      createdMs: 123,
    );
    final copy = SessionProfile.fromJson(p.toJson());
    expect(copy.name, 'prod-web');
    expect(copy.host, '10.0.0.1');
    expect(copy.port, 2222);
    expect(copy.x11Forwarding, isTrue);
    expect(copy.group, '生产/华东');
    expect(copy.forwards.single.describe(), contains('8080'));
    expect(copy.followTerminalFolder, isTrue);
    expect(copy.agentForwarding, isFalse);
    expect(copy.proxyKind, ProxyKind.none);
  });

  test('Macro JSON round-trip', () {
    final m = Macro(id: 'm1', name: 'deploy', steps: [
      MacroStep(command: 'cd /app', delayMs: 100),
    ]);
    final copy = Macro.fromJson(m.toJson());
    expect(copy.steps.single.command, 'cd /app');
    expect(copy.steps.single.delayMs, 100);
  });

  test('OSC 7 path extraction', () {
    expect(pathFromOsc7('file://host/home/dev'), '/home/dev');
    expect(pathFromOsc7('file:///var/log'), '/var/log');
    expect(pathFromOsc7('file://host/tmp/a%20b'), '/tmp/a b');
    expect(pathFromOsc7('relative'), isNull);
  });

  test('OpenSSH config parser keeps hosts, jumps and identity files', () {
    const text = '''
Host *
  User fallback

Host web
  HostName 10.0.0.8
  User root
  Port 2222
  IdentityFile ~/.ssh/id_ed25519
  ForwardX11 yes
  ProxyJump bastion

Host bastion
  HostName bastion.example
  User jump
''';
    final hosts = parseSshConfig(text);
    expect(hosts.map((h) => h.alias), ['web', 'bastion']);
    final web = hosts.first;
    expect(web.targetHost, '10.0.0.8');
    expect(web.port, 2222);
    expect(web.user, 'root');
    expect(web.forwardX11, isTrue);
    expect(web.proxyJump, 'bastion');
    expect(expandHome(web.identityFile!, '/home/dev'), '/home/dev/.ssh/id_ed25519');
  });
}
