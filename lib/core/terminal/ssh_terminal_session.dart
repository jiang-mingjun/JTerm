/// SSH terminal session - connects, opens a PTY shell, bridges it to the
/// xterm core, and additionally exposes SFTP + port-forwarding on the very
/// same connection (MobaXterm behaviour).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../forward/port_forward_engine.dart';
import '../models/session_profile.dart';
import '../ssh/sftp_service.dart';
import '../ssh/ssh_connection.dart';
import 'session_services.dart';
import 'terminal_session.dart';

class SshTerminalSession extends TerminalSessionBase {
  SshTerminalSession(super.profile, this.services);

  final SessionServices services;

  SshConnection? connection;
  SftpService? sftp;
  PortForwardEngine? forwardEngine;

  SSHSession? _shell;
  StreamSubscription<Uint8List>? _outSub;
  StreamSubscription<Uint8List>? _errSub;
  bool _userClosed = false;

  @override
  Future<void> connect() async {
    if (status == SessionStatus.connected || status == SessionStatus.connecting) {
      return;
    }
    emitStatus(SessionStatus.connecting);
    _userClosed = false;

    try {
      final creds = await services.resolveCredentials(profile);
      if (creds == null) {
        emitStatus(SessionStatus.failed, 'cancelled');
        return;
      }

      // ---- jump host chain (single level in v1) ----
      SshConnection? jump;
      final jumpId = profile.jumpViaSessionId;
      if (jumpId != null && jumpId.isNotEmpty) {
        final jumpProfile = _jumpProfile(jumpId);
        if (jumpProfile != null) {
          final jumpCreds = await services.resolveCredentials(jumpProfile);
          if (jumpCreds != null) {
            jump = await SshConnection.connect(
              jumpProfile,
              jumpCreds,
              hooks: services.hooks,
              knownHosts: services.knownHosts,
            );
          }
        }
      }

      connection = await SshConnection.connect(
        profile,
        creds,
        hooks: services.hooks,
        knownHosts: services.knownHosts,
        jumpConnection: jump,
      );

      final conn = connection!;
      sftp = SftpService(conn);
      forwardEngine = PortForwardEngine(conn);

      // ---- interactive shell ----
      final shell = await conn.client!.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
        x11: profile.x11Forwarding
            ? SSHX11Config(authenticationCookie: SshConnection.randomX11Cookie())
            : null,
        environment: const {'TERM': 'xterm-256color'},
      );
      _shell = shell;

      _outSub = shell.stdout.listen(
        (data) => terminal.write(utf8.decode(data, allowMalformed: true)),
      );
      _errSub = shell.stderr.listen(
        (data) => terminal.write(utf8.decode(data, allowMalformed: true)),
      );
      terminal.onOutput = (data) {
        onInputHook?.call(data);
        shell.stdin.add(Uint8List.fromList(utf8.encode(data)));
      };

      emitStatus(SessionStatus.connected);
      if (title.isEmpty) {
        emitTitle(profile.name);
      }

      // ---- auto-start port forwards ----
      for (final rule in profile.forwards) {
        if (rule.autoStart && rule.enabled && rule.isValid) {
          await forwardEngine!.start(rule);
        }
      }

      // ---- startup command ----
      final cmd = profile.startupCommand;
      if (cmd != null && cmd.isNotEmpty) {
        shell.stdin.add(Uint8List.fromList(utf8.encode('$cmd\n')));
      }

      // ---- monitor for drops ----
      unawaited(conn.client!.done.then((_) {
        if (!_userClosed) {
          emitStatus(SessionStatus.disconnected, 'connection closed');
          _maybeReconnect();
        }
      }));
    } catch (e) {
      emitStatus(SessionStatus.failed, e.toString());
      await _teardown();
    }
  }

  SessionProfile? _jumpProfile(String id) {
    // Resolved through the session repository by the UI-injected resolver is
    // overkill here; the repository is passed via services in AppState and
    // looked up lazily to avoid a core -> state dependency.
    return jumpProfileLookup?.call(id);
  }

  /// Set by the app state so jump profiles can be resolved.
  static SessionProfile? Function(String id)? jumpProfileLookup;

  void _maybeReconnect() {
    if (profile.reconnect == ReconnectPolicy.onDrop ||
        profile.reconnect == ReconnectPolicy.always) {
      emitStatus(SessionStatus.reconnecting);
      Future.delayed(const Duration(seconds: 3), () {
        if (!_userClosed && status == SessionStatus.reconnecting) {
          connect();
        }
      });
    }
  }

  Future<void> reconnect() async {
    await _teardown();
    await connect();
  }

  @override
  void onTerminalOutput(String data) {
    // Handled via terminal.onOutput set in connect().
  }

  @override
  void writeInput(String data) {
    _shell?.stdin.add(Uint8List.fromList(utf8.encode(data)));
  }

  @override
  Future<void> resize(int cols, int rows) async {
    _shell?.resizeTerminal(cols, rows);
  }

  @override
  Future<void> disconnect() async {
    _userClosed = true;
    await _teardown();
    emitStatus(SessionStatus.disconnected, 'closed');
  }

  Future<void> _teardown() async {
    await _outSub?.cancel();
    await _errSub?.cancel();
    _outSub = null;
    _errSub = null;
    _shell = null;
    await forwardEngine?.stopAll();
    forwardEngine = null;
    await sftp?.close();
    sftp = null;
    final conn = connection;
    connection = null;
    await conn?.close();
  }
}
