import 'package:flutter_test/flutter_test.dart';

import 'package:jterm/core/models/forward_rule.dart';
import 'package:jterm/core/models/macro.dart';
import 'package:jterm/core/models/session_profile.dart';

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
  });

  test('Macro JSON round-trip', () {
    final m = Macro(id: 'm1', name: 'deploy', steps: [
      MacroStep(command: 'cd /app', delayMs: 100),
    ]);
    final copy = Macro.fromJson(m.toJson());
    expect(copy.steps.single.command, 'cd /app');
    expect(copy.steps.single.delayMs, 100);
  });
}
