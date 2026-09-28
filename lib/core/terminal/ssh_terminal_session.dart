/// SSH terminal session - connects, opens a PTY shell, bridges it to the
/// xterm core, and additionally exposes SFTP + port-forwarding on the very
/// same connection (MobaXterm behaviour).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../forward/port_forward_engine.dart';
import '../models/session_profile.dart';
import '../ssh/sftp_service.dart';
import '../ssh/ssh_connection.dart';
import '../transfer/zmodem.dart';
import 'osc7.dart';
import 'osc_cwd.dart';
import 'session_services.dart';
import 'terminal_session.dart';

class SshTerminalSession extends TerminalSessionBase {
  SshTerminalSession(super.profile, this.services, {super.maxLines});

  final SessionServices services;

  SshConnection? connection;
  SftpService? sftp;
  PortForwardEngine? forwardEngine;

  SSHSession? _shell;
  StreamSubscription<Uint8List>? _outSub;
  StreamSubscription<Uint8List>? _errSub;
  final List<SshConnection> _hops = [];
  bool _userClosed = false;
  bool _hadSession = false;
  int _generation = 0;
  Timer? _reconnectTimer;
  ZmodemEngine? _zmodem;

  @override
  Future<void> connect() async {
    if (status == SessionStatus.connected ||
        status == SessionStatus.connecting) {
      return;
    }
    emitStatus(SessionStatus.connecting);
    _userClosed = false;
    _reconnectTimer?.cancel();
    _generation++;
    await _teardown();
    var dropArmed = false;

    try {
      await ensureLog();
      final creds = await services.resolveCredentials(profile);
      if (creds == null) {
        emitStatus(SessionStatus.failed, '已取消');
        return;
      }

      SshConnection? jump;
      final jumpId = profile.jumpViaSessionId;
      if (jumpId != null && jumpId.isNotEmpty) {
        jump = await _openJump(jumpId, <String>{});
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

      _zmodem = ZmodemEngine(
        onFile: _saveZmodem,
        onPick: _pickZmodem,
        onStatus: (message) => paint('\r\n\x1b[33m[zmodem] $message\x1b[0m\r\n'),
      );
      _outSub = shell.stdout.listen((data) {
        unawaited(_onRemote(shell, data));
      });
      _errSub = shell.stderr.listen((data) {
        paint(utf8.decode(data, allowMalformed: true));
      });
      terminal.onOutput = (data) {
        handleUserInput(data);
      };

      _hadSession = true;
      reconnectAttempt = 0;
      emitStatus(SessionStatus.connected);
      if (title.isEmpty) emitTitle(profile.name);

      for (final rule in profile.forwards) {
        if (rule.autoStart && rule.enabled && rule.isValid) {
          await forwardEngine!.start(rule);
        }
      }

      final banner = conn.authBanner.toString().trim();
      if (banner.isNotEmpty) paint('$banner\r\n');
      if (profile.followTerminalFolder) {
        shell.stdin.add(cwdTrackingCommand());
      }
      final cmd = profile.startupCommand;
      if (cmd != null && cmd.isNotEmpty) {
        shell.stdin.add(Uint8List.fromList(utf8.encode('$cmd\n')));
      }

      final generation = _generation;
      dropArmed = true;
      unawaited(conn.client!.done.then((_) {
        if (_userClosed || generation != _generation) return;
        emitStatus(SessionStatus.disconnected, '连接已关闭');
        _maybeReconnect();
      }));
    } catch (e) {
      emitStatus(SessionStatus.failed, e.toString());
      await _teardown();
      if (!dropArmed) _maybeReconnect();
    }
  }

  Future<SshConnection> _openJump(String id, Set<String> seen) async {
    if (!seen.add(id)) {
      throw StateError('跳板配置出现循环');
    }
    final jumpProfile = jumpProfileLookup?.call(id);
    if (jumpProfile == null) {
      throw StateError('找不到跳板会话');
    }
    SshConnection? parent;
    final parentId = jumpProfile.jumpViaSessionId;
    if (parentId != null && parentId.isNotEmpty) {
      parent = await _openJump(parentId, seen);
    }
    final creds = await services.resolveCredentials(jumpProfile);
    if (creds == null) {
      throw StateError('跳板认证已取消');
    }
    final hop = await SshConnection.connect(
      jumpProfile,
      creds,
      hooks: services.hooks,
      knownHosts: services.knownHosts,
      jumpConnection: parent,
    );
    _hops.add(hop);
    return hop;
  }

  /// Set by the app state so jump profiles can be resolved.
  static SessionProfile? Function(String id)? jumpProfileLookup;

  Future<void> _onRemote(SSHSession shell, Uint8List data) async {
    final engine = _zmodem;
    if (engine == null) {
      final text = utf8.decode(data, allowMalformed: true);
      _captureOsc7(text);
      paint(text);
      return;
    }
    final shown = await engine.add(data, shell.stdin.add);
    if (shown.isEmpty) return;
    final text = utf8.decode(shown, allowMalformed: true);
    _captureOsc7(text);
    paint(text);
  }

  Future<void> _saveZmodem(String name, Uint8List bytes) async {
    final dir = await services.prepareDownloadDir();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    paint('\r\n\x1b[32m[zmodem] 已保存 ${file.path}\x1b[0m\r\n');
  }

  Future<ZmodemUpload?> _pickZmodem() async {
    final picked = await services.pickUpload?.call();
    if (picked == null) return null;
    if (picked.bytes.length > 32 * 1024 * 1024) {
      paint('\r\n\x1b[31m[zmodem] 文件超过 32MB，已取消\x1b[0m\r\n');
      return null;
    }
    return ZmodemUpload(name: picked.name, bytes: picked.bytes);
  }

  void _captureOsc7(String text) {
    for (final payload in osc7Payloads(text)) {
      final path = pathFromOsc7(payload);
      if (path != null) emitCwd(path);
    }
  }

  void _maybeReconnect() {
    if (_userClosed || !_hadSession) return;
    if (profile.reconnect == ReconnectPolicy.never) return;
    reconnectAttempt += 1;
    if (reconnectAttempt > 6) {
      emitStatus(SessionStatus.failed, '重连失败，已停止');
      return;
    }
    const delays = [2, 4, 8, 12, 20, 30];
    final seconds = delays[reconnectAttempt - 1];
    emitStatus(SessionStatus.reconnecting, '$seconds 秒后进行第 $reconnectAttempt 次重连');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!_userClosed && status == SessionStatus.reconnecting) {
        unawaited(connect());
      }
    });
  }

  Future<void> reconnect() async {
    _userClosed = true;
    _reconnectTimer?.cancel();
    await _teardown();
    _userClosed = false;
    await connect();
  }

  @override
  void onTerminalOutput(String data) {}

  @override
  void writeInput(String data) {
    _shell?.stdin.add(Uint8List.fromList(utf8.encode(data)));
  }

  @override
  Future<void> resize(int cols, int rows) async {
    noteViewport(cols, rows);
    _shell?.resizeTerminal(cols, rows);
  }

  @override
  Future<void> disconnect() async {
    _userClosed = true;
    _reconnectTimer?.cancel();
    await _teardown();
    emitStatus(SessionStatus.disconnected, '已关闭');
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
    for (final hop in _hops.reversed) {
      await hop.close();
    }
    _hops.clear();
  }
}
