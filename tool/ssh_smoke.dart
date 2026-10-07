/// Smoke test for the real SSH connection path used by the app.
///
/// Covers: password auth, publickey auth (ed25519), PTY shell round-trip,
/// SFTP list/read/write/mkdir/rename/delete, keep-alive stability, wrong
/// passwords, unreachable hosts and changed host keys.
///
/// Usage:
///   pip install paramiko
///   python3 tool/test_sshd.py          # terminal 1: starts 127.0.0.1:2222
///   dart run tool/ssh_smoke.dart       # terminal 2: runs the checks
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:jterm/core/models/session_profile.dart';
import 'package:jterm/core/ssh/sftp_service.dart';
import 'package:jterm/core/ssh/ssh_connection.dart';
import 'package:jterm/core/ssh/ssh_credentials.dart';
import 'package:jterm/core/store/json_store.dart';
import 'package:jterm/core/store/known_hosts_store.dart';

int failures = 0;

void check(String name, bool ok) {
  stdout.writeln('[${ok ? 'PASS' : 'FAIL'}] $name');
  if (!ok) failures++;
}

Future<void> main() async {
  final knownHosts =
      KnownHostsStore(JsonStore('/tmp/jterm_ssh_test/known_hosts.json'));
  await knownHosts.load();

  final hooks = SshConnectHooks(
    verifyHostKey: (host, type, fingerprint) async {
      stdout.writeln('[hook] verifyHostKey: $host $type $fingerprint');
      return HostKeyDecision.trustAndSave;
    },
    missingPassword: (prompt, {obscure = true, initial}) async {
      stdout.writeln('[hook] missingPassword: $prompt');
      return 'testpass';
    },
    keyboardInteractive: (name, instruction, prompts) async {
      stdout.writeln('[hook] keyboardInteractive: $name / $instruction');
      return ['testpass'];
    },
  );

  SessionProfile profile({int port = 2222, String host = '127.0.0.1'}) =>
      SessionProfile(
        id: 'smoke-1',
        name: 'smoke',
        type: SessionType.ssh,
        host: host,
        port: port,
        username: 'testuser',
        authMethod: AuthMethod.password,
        keepAliveSeconds: 0,
      );

  // ---- case 1: happy path: password auth + shell echo round-trip ----
  try {
    final conn = await SshConnection.connect(
      profile(),
      SshCredentials(username: 'testuser', password: 'testpass'),
      hooks: hooks,
      knownHosts: knownHosts,
    );
    check('password auth + connection', conn.isAlive);

    final shell = await conn.client!.shell(
      pty: SSHPtyConfig(type: 'xterm-256color', width: 80, height: 24),
    );

    final received = StringBuffer();
    final done = Completer<void>();
    shell.stdout.listen((data) {
      final text = String.fromCharCodes(data);
      received.write(text);
      if (received.toString().contains('SMOKE_OK_ECHO')) {
        if (!done.isCompleted) done.complete();
      }
    });

    await Future<void>.delayed(const Duration(milliseconds: 300));
    shell.stdin.add(Uint8List.fromList('echo SMOKE_OK_ECHO\n'.codeUnits));

    await done.future.timeout(const Duration(seconds: 10));
    check('shell echo round-trip', true);
    await conn.close();
  } catch (e) {
    stdout.writeln('[error] happy path: $e');
    check('password auth + shell echo round-trip', false);
  }

  // ---- case 2: wrong password -> clear error, no hang ----
  try {
    await SshConnection.connect(
      profile(),
      SshCredentials(username: 'testuser', password: 'WRONG'),
      knownHosts: knownHosts,
    ).timeout(const Duration(seconds: 30));
    check('wrong password is rejected', false);
  } on TimeoutException {
    check('wrong password is rejected (timed out - prompt loop?)', false);
  } catch (e) {
    stdout.writeln('[error] wrong-password path: $e');
    check(
      'wrong password is rejected with friendly message',
      e.toString().contains('认证失败'),
    );
  }

  // ---- case 3: unreachable host fails fast ----
  final sw = Stopwatch()..start();
  try {
    await SshConnection.connect(
      profile(port: 2299),
      SshCredentials(username: 'x', password: 'x'),
      timeout: const Duration(seconds: 4),
    );
    check('unreachable host fails', false);
  } catch (e) {
    sw.stop();
    stdout.writeln('[error] unreachable: $e (${sw.elapsed})');
    check('unreachable host fails fast', sw.elapsed < const Duration(seconds: 15));
  }

  // ---- case 4: publickey auth with the generated ed25519 key ----
  try {
    final pem = await File('/tmp/jterm_ssh_test/test_key').readAsString();
    final pkProfile = profile();
    pkProfile.authMethod = AuthMethod.publicKey;
    final conn = await SshConnection.connect(
      pkProfile,
      SshCredentials(username: 'testuser', privateKeyPem: pem),
      hooks: hooks,
      knownHosts: knownHosts,
    );
    check('publickey auth (ed25519)', conn.isAlive);
    await conn.close();
  } catch (e) {
    stdout.writeln('[error] publickey path: $e');
    check('publickey auth (ed25519)', false);
  }

  // ---- case 5: SFTP browse / read / write / mkdir / rename / delete ----
  try {
    final conn = await SshConnection.connect(
      profile(),
      SshCredentials(username: 'testuser', password: 'testpass'),
      hooks: hooks,
      knownHosts: knownHosts,
    );
    final sftp = SftpService(conn);

    final root = await sftp.list('/');
    final names = root.map((e) => e.name).toList();
    check('sftp list / sees readme.txt', names.contains('readme.txt'));
    check('sftp list marks docs as directory',
        root.any((e) => e.name == 'docs' && e.isDirectory));

    final text = await sftp.readText('/readme.txt');
    check('sftp readText', text.trim() == 'hello jterm sftp');

    await sftp.writeText('/written_by_jterm.txt', 'written-by-jterm');
    final back = await sftp.readText('/written_by_jterm.txt');
    check('sftp writeText round-trip', back == 'written-by-jterm');

    await sftp.mkdir('/newdir');
    await sftp.rename('/newdir', '/newdir2');
    final afterRename = await sftp.list('/');
    check('sftp mkdir+rename', afterRename.any((e) => e.name == 'newdir2'));

    await sftp.removeTree('/newdir2');
    await sftp.deleteFile('/written_by_jterm.txt');
    final afterDelete = await sftp.list('/');
    check('sftp rmdir+delete',
        !afterDelete.any((e) => e.name == 'newdir2' || e.name == 'written_by_jterm.txt'));

    await sftp.close();
    await conn.close();
  } catch (e) {
    stdout.writeln('[error] sftp path: $e');
    check('sftp operations', false);
  }

  // ---- case 6: keep-alive does not kill an idle connection ----
  try {
    final kaProfile = profile();
    kaProfile.keepAliveSeconds = 2;
    final conn = await SshConnection.connect(
      kaProfile,
      SshCredentials(username: 'testuser', password: 'testpass'),
      hooks: hooks,
      knownHosts: knownHosts,
    );
    // Wait for several keep-alive rounds.
    await Future<void>.delayed(const Duration(seconds: 7));
    check('keep-alive keeps idle connection alive', conn.isAlive);
    await conn.close();
  } catch (e) {
    stdout.writeln('[error] keepalive path: $e');
    check('keep-alive keeps idle connection alive', false);
  }

  // ---- case 7: changed host key is detected and rejected ----
  try {
    // Remove all stored fingerprints for this host, then store a fake one so
    // the real key looks *changed* (not merely unknown).
    await knownHosts.forget('127.0.0.1');
    await knownHosts.trust('127.0.0.1', 'SHA256:FAKEFINGERPRINT', 'rsa-sha2-512');
    var asked = false;
    final changedHooks = SshConnectHooks(
      verifyHostKey: (host, type, fingerprint) async {
        asked = true;
        // A real user hits "reject" when the key changed.
        return HostKeyDecision.reject;
      },
      missingPassword: (prompt, {obscure = true, initial}) async => 'testpass',
    );
    try {
      await SshConnection.connect(
        profile(),
        SshCredentials(username: 'testuser', password: 'testpass'),
        hooks: changedHooks,
        knownHosts: knownHosts,
      ).timeout(const Duration(seconds: 30));
      check('changed host key is rejected', false);
    } catch (e) {
      stdout.writeln('[error] changed-key path: $e');
      check('changed host key is rejected', asked);
    }
    // Clean the poisoned entry so later runs start fresh.
    await knownHosts.forget('127.0.0.1');
  } catch (e) {
    stdout.writeln('[error] changed-key setup: $e');
    check('changed host key is rejected', false);
  }

  stdout.writeln(failures == 0 ? 'ALL SMOKE TESTS PASSED' : '$failures FAILURES');
  exitCode = failures == 0 ? 0 : 1;
}

