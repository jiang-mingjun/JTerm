/// Serial console session. Opens a Linux tty with termios and bridges it to
/// the same terminal core used by SSH.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../serial/serial_port.dart';
import 'terminal_session.dart';

class SerialTerminalSession extends TerminalSessionBase {
  SerialTerminalSession(super.profile, {super.maxLines});

  SerialPort? _port;
  StreamSubscription<Uint8List>? _sub;
  bool _userClosed = false;

  @override
  Future<void> connect() async {
    if (status == SessionStatus.connected || status == SessionStatus.connecting) {
      return;
    }
    emitStatus(SessionStatus.connecting);
    _userClosed = false;
    await disconnectQuiet();
    final device = profile.serialDevice;
    if (device == null || device.isEmpty) {
      emitStatus(SessionStatus.failed, '未指定串口设备');
      return;
    }
    try {
      await ensureLog();
      final port = await SerialPort.open(
        device,
        baudRate: profile.serialBaudRate,
        dataBits: profile.serialDataBits,
        parity: profile.serialParity,
        stopBits: profile.serialStopBits,
      );
      _port = port;
      _sub = port.stream.listen(
        (data) => paint(utf8.decode(data, allowMalformed: true)),
        onDone: () {
          if (!_userClosed) {
            emitStatus(SessionStatus.disconnected, '串口已关闭');
          }
        },
        onError: (Object e) {
          if (!_userClosed) emitStatus(SessionStatus.failed, e.toString());
        },
      );
      terminal.onOutput = (data) {
        handleUserInput(data);
      };
      emitStatus(SessionStatus.connected);
      emitTitle(profile.name.isEmpty ? device : profile.name);
    } catch (e) {
      emitStatus(SessionStatus.failed, e.toString());
    }
  }

  Future<void> disconnectQuiet() async {
    await _sub?.cancel();
    _sub = null;
    await _port?.close();
    _port = null;
  }

  @override
  void onTerminalOutput(String data) {}

  @override
  void writeInput(String data) {
    _port?.write(utf8.encode(data));
  }

  @override
  Future<void> resize(int cols, int rows) async {
    noteViewport(cols, rows);
  }

  @override
  Future<void> disconnect() async {
    _userClosed = true;
    await disconnectQuiet();
    emitStatus(SessionStatus.disconnected, '已关闭');
  }
}
