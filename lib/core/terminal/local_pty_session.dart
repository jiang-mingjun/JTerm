/// Local shell session backed by a real PTY (flutter_pty), the equivalent
/// of MobaXterm's local terminal / Cygwin tab.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';

import 'terminal_session.dart';

class LocalPtySession extends TerminalSessionBase {
  LocalPtySession(super.profile);

  Pty? _pty;
  StreamSubscription<Uint8List>? _outSub;
  bool _started = false;

  String get _shell {
    final env = Platform.environment;
    return env['SHELL'] ?? '/bin/bash';
  }

  @override
  Future<void> connect() async {
    if (_started) return;
    _started = true;
    emitStatus(SessionStatus.connecting);
    try {
      final pty = Pty.start(
        _shell,
        arguments: ['-l'],
        workingDirectory: Platform.environment['HOME'],
        rows: terminal.viewHeight,
        columns: terminal.viewWidth,
      );
      _pty = pty;

      _outSub = pty.output.listen(
        (data) => terminal.write(utf8.decode(data, allowMalformed: true)),
      );
      terminal.onOutput = (data) {
        onInputHook?.call(data);
        pty.write(Uint8List.fromList(utf8.encode(data)));
      };
      terminal.onTitleChange = (t) => emitTitle(t);

      emitStatus(SessionStatus.connected);
      emitTitle('local');

      final code = await pty.exitCode;
      emitStatus(SessionStatus.disconnected, 'process exited ($code)');
    } catch (e) {
      emitStatus(SessionStatus.failed, e.toString());
    }
  }

  @override
  void onTerminalOutput(String data) {}

  @override
  void writeInput(String data) {
    _pty?.write(Uint8List.fromList(utf8.encode(data)));
  }

  @override
  Future<void> resize(int cols, int rows) async {
    _pty?.resize(rows, cols);
  }

  @override
  Future<void> disconnect() async {
    await _outSub?.cancel();
    _outSub = null;
    _pty?.kill();
    _pty = null;
    emitStatus(SessionStatus.disconnected, 'closed');
  }
}
