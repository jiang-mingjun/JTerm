import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jterm/core/models/forward_rule.dart';
import 'package:jterm/core/models/session_profile.dart';
import 'package:jterm/core/ssh/openssh_config.dart';
import 'package:jterm/core/terminal/osc_cwd.dart';
import 'package:jterm/core/transfer/zmodem.dart';

void main() {
  test('session profile keeps agent, proxy and serial fields', () {
    final profile = SessionProfile(
      id: 's1',
      name: 'edge',
      type: SessionType.ssh,
      host: '10.1.1.1',
      authMethod: AuthMethod.agent,
      agentForwarding: true,
      proxyKind: ProxyKind.httpConnect,
      proxyHost: 'proxy.internal',
      proxyPort: 8080,
      proxyUsername: 'alice',
      autoConnect: true,
      followTerminalFolder: false,
      serialBaudRate: 57600,
      forwards: [
        ForwardRule(
          id: 'f1',
          type: ForwardType.local,
          localPort: 8080,
          remoteHost: '127.0.0.1',
          remotePort: 80,
        ),
      ],
    );
    final copy = SessionProfile.fromJson(profile.toJson());
    expect(copy.authMethod, AuthMethod.agent);
    expect(copy.agentForwarding, isTrue);
    expect(copy.proxyKind, ProxyKind.httpConnect);
    expect(copy.proxyHost, 'proxy.internal');
    expect(copy.proxyUsername, 'alice');
    expect(copy.autoConnect, isTrue);
    expect(copy.followTerminalFolder, isFalse);
    expect(copy.forwards.single.localPort, 8080);
  });

  test('OpenSSH config builds a jump chain and forwards', () {
    const text = '''
Host bastion
  HostName 10.0.0.1
  User jump

Host web
  HostName 10.0.0.8
  User app
  Port 2222
  IdentityFile ~/.ssh/id_ed25519
  ProxyJump bastion
  ForwardAgent yes
  LocalForward 8080 127.0.0.1:80
''';
    final profiles = OpenSshConfig.parse(text, home: '/home/dev');
    final web = profiles.firstWhere((p) => p.name == 'web');
    final bastion = profiles.firstWhere((p) => p.name == 'bastion');
    expect(web.host, '10.0.0.8');
    expect(web.port, 2222);
    expect(web.username, 'app');
    expect(web.privateKeyPath, '/home/dev/.ssh/id_ed25519');
    expect(web.agentForwarding, isTrue);
    expect(web.jumpViaSessionId, bastion.id);
    expect(web.forwards.single.type, ForwardType.local);
    expect(web.forwards.single.localPort, 8080);
    expect(web.forwards.single.remotePort, 80);
  });

  test('OSC 7 file URL becomes a path', () {
    final extractor = OscCwdExtractor();
    final chunk = utf8.encode('hi\x1b]7;file://host/home/dev/src\x07tail');
    final parsed = extractor.push(chunk);
    expect(parsed.cwd, '/home/dev/src');
    expect(parsed.text, 'hitail');
  });

  test('ZMODEM CRC and a one-file receive', () async {
    expect(crc16([0, 0, 0, 0, 0]), 0);
    expect(crc16([1, 0x33, 0, 0, 0]), 0x1d64);
    expect(crc32([104, 105, 10]), 0xed6f7a7a);

    final saved = <String, Uint8List>{};
    final engine = ZmodemEngine(
      onFile: (name, bytes) async {
        saved[name] = bytes;
      },
      onPick: () async => null,
    );
    final remote = <int>[];
    void write(Uint8List bytes) => remote.addAll(bytes);

    await engine.add(ZmodemCodec.hexHeader(zrqinit, 0), write);
    expect(remote, isNotEmpty);
    remote.clear();

    final meta = ZmodemCodec.subpacket(
      [...utf8.encode('hello.txt'), 0, ...utf8.encode('5 0 100644'), 0],
      zcrcw,
    );
    await engine.add([
      ...ZmodemCodec.hexHeader(zfile, 0),
      ...meta,
    ], write);
    expect(remote, isNotEmpty);

    final payload = utf8.encode('hello');
    await engine.add([
      ...ZmodemCodec.bin32Header(zdata, 0),
      ...ZmodemCodec.subpacket(payload, zcrce),
      ...ZmodemCodec.bin32Header(zeof, payload.length),
    ], write);
    expect(saved['hello.txt'], payload);

    await engine.add(ZmodemCodec.hexHeader(zfin, 0), write);
    expect(engine.active, isFalse);
  });

  test('terminal bytes before a ZMODEM header stay visible', () async {
    final engine = ZmodemEngine(
      onFile: (_, __) async {},
      onPick: () async => null,
    );
    final shown = await engine.add(
      [...utf8.encode('prompt\$ '), ...ZmodemCodec.hexHeader(zrqinit, 0)],
      (_) {},
    );
    expect(utf8.decode(shown), 'prompt\$ ');
  });
}
