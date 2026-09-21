/// SSH connection manager - the heart of JTerm.
///
/// Wraps one [SSHClient] plus everything around it that MobaXterm offers:
/// host-key verification (TOFU), jump hosts, X11 forwarding into the local X
/// server, auto-started port forwards and keep-alive.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';

import '../models/session_profile.dart';
import '../store/known_hosts_store.dart';
import 'ssh_credentials.dart';

/// What the user answered to a host-key prompt.
enum HostKeyDecision { trustOnce, trustAndSave, reject }

/// Callbacks the UI must provide to drive the connection flow.
class SshConnectHooks {
  SshConnectHooks({
    required this.verifyHostKey,
    required this.missingPassword,
  });

  /// Ask the user about an unknown / changed host key.
  final Future<HostKeyDecision> Function(
      String host, String keyType, String fingerprint) verifyHostKey;

  /// Ask the user for a password (or key passphrase).
  final Future<String?> Function(String prompt, {bool obscure, String? initial}) missingPassword;
}

class SshConnection {
  SshConnection._();

  SSHClient? client;
  String? connectedHost;
  int connectedPort = 22;

  final _x11ChannelCtrl = StreamController<SSHX11Channel>.broadcast();

  /// Emitted for every incoming remote X11 channel request.
  Stream<SSHX11Channel> get x11Channels => _x11ChannelCtrl.stream;

  bool get isAlive => client != null && !client!.isClosed;

  static Future<SshConnection> connect(
    SessionProfile profile,
    SshCredentials creds, {
    SshConnectHooks? hooks,
    KnownHostsStore? knownHosts,
    SshConnection? jumpConnection,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final conn = SshConnection._();
    await conn._connect(
      profile,
      creds,
      hooks: hooks,
      knownHosts: knownHosts,
      jumpConnection: jumpConnection,
      timeout: timeout,
    );
    return conn;
  }

  Future<void> _connect(
    SessionProfile profile,
    SshCredentials creds, {
    required SshConnectHooks? hooks,
    required KnownHostsStore? knownHosts,
    required SshConnection? jumpConnection,
    required Duration timeout,
  }) async {
    final host = profile.host!;
    final port = profile.port;

    // ---- transport socket (direct or through a jump host) ----
    final SSHSocket socket;
    if (jumpConnection != null && jumpConnection.isAlive) {
      socket = await jumpConnection.client!.forwardLocal(host, port);
    } else {
      socket = await SSHSocket.connect(host, port, timeout: timeout);
    }

    var passwordAttempt = creds.password;

    final client = SSHClient(
      socket,
      username: creds.username,
      onVerifyHostKey: (type, fingerprintUtf8) async {
        final fingerprint = utf8.decode(fingerprintUtf8);
        if (knownHosts != null) {
          final known = knownHosts.verify(host, fingerprint);
          if (known == true) return true;
          if (hooks != null) {
            final decision =
                await hooks.verifyHostKey(host, type, fingerprint);
            switch (decision) {
              case HostKeyDecision.trustOnce:
                return true;
              case HostKeyDecision.trustAndSave:
                await knownHosts.trust(host, fingerprint, type);
                return true;
              case HostKeyDecision.reject:
                return false;
            }
          }
        }
        return true; // no store and no hooks - permissive fallback
      },
      onPasswordRequest: () async {
        if (passwordAttempt != null) {
          final p = passwordAttempt;
          passwordAttempt = null; // only use the saved password once
          return p;
        }
        if (hooks != null) {
          return await hooks.missingPassword(
            'Password for ${creds.username}@$host',
            obscure: true,
          );
        }
        return null;
      },
      identities: _loadIdentities(creds),
      keepAliveInterval: Duration(seconds: profile.keepAliveSeconds),
      handshakeTimeout: timeout,
      authTimeout: timeout,
      onX11Forward: profile.x11Forwarding ? _handleX11Channel : null,
    );

    await client.authenticated;

    this.client = client;
    connectedHost = host;
    connectedPort = port;
  }

  static List<SSHKeyPair>? _loadIdentities(SshCredentials creds) {
    if (!creds.hasKey) return null;
    try {
      return SSHKeyPair.fromPem(creds.privateKeyPem!, creds.keyPassphrase);
    } catch (_) {
      // Wrong passphrase is surfaced by the auth failure path instead.
      return null;
    }
  }

  // ------------------------------------------------------------------
  // X11 bridging: remote X clients arrive as SSH channels and are piped
  // into the local X server socket ($DISPLAY).
  // ------------------------------------------------------------------
  final List<StreamSubscription> _x11Pipes = [];

  void _handleX11Channel(SSHX11Channel channel) {
    _x11ChannelCtrl.add(channel);
    _bridgeToLocalX(channel);
  }

  Future<void> _bridgeToLocalX(SSHX11Channel channel) async {
    final display = Platform.environment['DISPLAY'] ?? '';
    // Dart reaches Unix domain sockets through InternetAddress + type.unix.
    InternetAddress unixAddr(String path) =>
        InternetAddress(path, type: InternetAddressType.unix);
    try {
      Socket target;
      if (display.startsWith('/')) {
        target = await Socket.connect(
          unixAddr(display),
          0,
          timeout: const Duration(seconds: 5),
        );
      } else if (display.startsWith(':') || display.startsWith('localhost:')) {
        final n = int.tryParse(display.split(':').last.split('.').first) ?? 0;
        // Try the unix socket first, then TCP 6000+n.
        try {
          target = await Socket.connect(
            unixAddr('/tmp/.X11-unix/X$n'),
            0,
            timeout: const Duration(seconds: 3),
          );
        } on SocketException {
          target = await Socket.connect(
            'localhost',
            6000 + n,
            timeout: const Duration(seconds: 3),
          );
        }
      } else {
        return;
      }

      final sub1 = channel.stream.listen(target.add,
          onError: (Object _) {}, onDone: () => target.destroy());
      final sub2 = target.listen((data) => channel.sink.add(data),
          onError: (Object _) {}, onDone: () => channel.close());
      _x11Pipes.addAll([sub1, sub2]);
    } catch (_) {
      channel.close();
    }
  }

  /// Generates a random MIT-MAGIC-COOKIE-1 value for the x11-req request.
  static String randomX11Cookie() {
    final rnd = Random.secure();
    final bytes = List.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> close() async {
    for (final s in _x11Pipes) {
      await s.cancel();
    }
    _x11Pipes.clear();
    client?.close();
    await _x11ChannelCtrl.close();
  }
}
