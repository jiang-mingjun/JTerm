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
import 'agent_forward.dart';
import 'proxy_connector.dart';
import 'socks_socket.dart';
import 'ssh_agent_client.dart';
import 'ssh_credentials.dart';

/// What the user answered to a host-key prompt.
enum HostKeyDecision { trustOnce, trustAndSave, reject }

/// Callbacks the UI must provide to drive the connection flow.
class SshConnectHooks {
  SshConnectHooks({
    required this.verifyHostKey,
    required this.missingPassword,
    this.keyboardInteractive,
  });

  /// Ask the user about an unknown / changed host key.
  final Future<HostKeyDecision> Function(
      String host, String keyType, String fingerprint) verifyHostKey;

  /// Ask the user for a password (or key passphrase).
  final Future<String?> Function(String prompt, {bool obscure, String? initial}) missingPassword;

  /// Keyboard-interactive prompts (OTP, PAM, Duo, ...). Return null to cancel.
  final Future<List<String>?> Function(
    String name,
    String instruction,
    List<({String prompt, bool echo})> prompts,
  )? keyboardInteractive;
}

class SshConnection {
  SshConnection._();

  SSHClient? client;
  SshAgentClient? agent;
  String? connectedHost;
  int connectedPort = 22;
  final authBanner = StringBuffer();

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

    // ---- local credential preparation (no network yet) ----
    // Done before the socket so a bad key fails fast without leaking a
    // TCP connection, and so agent errors are not confused with network ones.
    var passwordAttempt = creds.password;
    var identities = _loadIdentities(creds);
    if (profile.authMethod == AuthMethod.agent) {
      final connected = await SshAgentClient.connect();
      if (connected == null) {
        throw StateError('无法连接 SSH agent，请确认 SSH_AUTH_SOCK 指向正在运行的 agent');
      }
      agent = connected;
      final fromAgent = await connected.identities();
      if (fromAgent.isEmpty) {
        await connected.close();
        agent = null;
        throw StateError('SSH agent 中没有可用密钥');
      }
      identities = fromAgent;
    }

    // ---- transport socket (jump host, proxy, or direct) ----
    final SSHSocket socket;
    if (jumpConnection != null && jumpConnection.isAlive) {
      socket = await jumpConnection.client!.forwardLocal(host, port);
    } else if (profile.proxyKind != ProxyKind.none &&
        (profile.proxyHost ?? '').isNotEmpty) {
      final proxyUser = profile.proxyUsername ?? '';
      String? proxyPassword;
      if (proxyUser.isNotEmpty && hooks != null) {
        proxyPassword = await hooks.missingPassword(
          '代理密码 $proxyUser@${profile.proxyHost}',
          obscure: true,
        );
      }
      if (profile.proxyKind == ProxyKind.socks5 && proxyUser.isEmpty) {
        socket = await connectSocks5(
          proxyHost: profile.proxyHost!,
          proxyPort: profile.proxyPort,
          targetHost: host,
          targetPort: port,
          timeout: timeout,
        );
      } else {
        socket = await ProxyConnector.open(
          kind: profile.proxyKind,
          proxyHost: profile.proxyHost!,
          proxyPort: profile.proxyPort,
          targetHost: host,
          targetPort: port,
          username: proxyUser.isEmpty ? null : proxyUser,
          password: proxyPassword,
          timeout: timeout,
        );
      }
    } else {
      socket = await SSHSocket.connect(host, port, timeout: timeout);
    }

    final agentHandler = profile.agentForwarding
        ? await buildAgentHandler(identities.whereType<SSHKeyPair>().toList())
        : null;

    final client = SSHClient(
      socket,
      username: creds.username,
      ident: 'JTerm_0.2',
      onUserauthBanner: authBanner.writeln,
      onUserInfoRequest: hooks?.keyboardInteractive == null
          ? null
          : (request) {
              return hooks!.keyboardInteractive!(
                request.name,
                request.instruction,
                [
                  for (final p in request.prompts)
                    (prompt: p.promptText, echo: p.echo),
                ],
              );
            },
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
      identities: identities.isEmpty ? null : identities,
      agentHandler: agentHandler,
      keepAliveInterval: profile.keepAliveSeconds <= 0
          ? null
          : Duration(seconds: profile.keepAliveSeconds),
      // KEX itself takes seconds; the headroom covers the interactive
      // host-key confirmation dialog shown on first connect.
      handshakeTimeout: const Duration(seconds: 45),
      // The auth phase includes interactive password / OTP prompts, so it
      // must not reuse the short network timeout.
      authTimeout: const Duration(minutes: 5),
      onX11Forward: profile.x11Forwarding ? _handleX11Channel : null,
    );

    try {
      await client.authenticated;
    } on SSHAuthFailError {
      await client.close();
      await _closeAgent();
      throw StateError('认证失败：服务器拒绝了密码、密钥等所有认证方式');
    } catch (_) {
      // Handshake/auth error, user cancel or timeout: never leak the socket.
      await client.close();
      await _closeAgent();
      rethrow;
    }

    this.client = client;
    connectedHost = host;
    connectedPort = port;
  }

  /// Parses the private key eagerly so a wrong passphrase or an unsupported
  /// format fails fast with a clear message, instead of silently degrading
  /// into a confusing password-auth fallback.
  static List<SSHIdentity> _loadIdentities(SshCredentials creds) {
    if (!creds.hasKey) return const [];
    final List<SSHKeyPair> pairs;
    try {
      pairs = SSHKeyPair.fromPem(creds.privateKeyPem!, creds.keyPassphrase);
    } catch (e) {
      throw StateError('私钥解析失败（口令错误或格式不支持）：$e');
    }
    if (pairs.isEmpty) {
      throw StateError('私钥文件中不包含可用密钥');
    }
    return pairs;
  }

  Future<void> _closeAgent() async {
    await agent?.close();
    agent = null;
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
    client = null;
    await _closeAgent();
    await _x11ChannelCtrl.close();
  }
}
