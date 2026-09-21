/// Telnet terminal session (RFC 854, see core/telnet/telnet_client.dart).
library;

import 'dart:async';
import 'dart:convert';

import '../telnet/telnet_client.dart';
import 'terminal_session.dart';

class TelnetTerminalSession extends TerminalSessionBase {
  TelnetTerminalSession(super.profile);

  TelnetClient? _client;
  StreamSubscription? _sub;
  bool _userClosed = false;

  @override
  Future<void> connect() async {
    if (status == SessionStatus.connected) return;
    emitStatus(SessionStatus.connecting);
    _userClosed = false;
    try {
      final client = TelnetClient(profile.host!, profile.port);
      _client = client;
      await client.connect();

      _sub = client.onData.listen(
        (data) => terminal.write(utf8.decode(data, allowMalformed: true)),
      );
      terminal.onOutput = (data) {
        onInputHook?.call(data);
        client.write(data);
      };

      emitStatus(SessionStatus.connected);
      emitTitle(profile.name);

      await client.done;
      if (!_userClosed) {
        emitStatus(SessionStatus.disconnected, 'connection closed');
      }
    } catch (e) {
      emitStatus(SessionStatus.failed, e.toString());
    }
  }

  @override
  void onTerminalOutput(String data) {}

  @override
  void writeInput(String data) {
    _client?.write(data);
  }

  @override
  Future<void> resize(int cols, int rows) async {
    _client?.resize(cols, rows);
  }

  @override
  Future<void> disconnect() async {
    _userClosed = true;
    await _sub?.cancel();
    _sub = null;
    await _client?.close();
    _client = null;
    emitStatus(SessionStatus.disconnected, 'closed');
  }
}
