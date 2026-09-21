/// Minimal RFC 854 telnet client with option negotiation and NAWS support.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class TelnetClient {
  TelnetClient(this.host, this.port);

  final String host;
  final int port;

  Socket? _socket;
  final _dataOut = StreamController<Uint8List>.broadcast();

  /// Payload data (negotiation bytes stripped) ready for the terminal.
  Stream<Uint8List> get onData => _dataOut.stream;

  final _closed = Completer<void>();
  Future<void> get done => _closed.future;

  // Telnet protocol constants.
  static const int iac = 255;
  static const int dont = 254;
  static const int do_ = 253;
  static const int will = 251;
  static const int wont = 252;
  static const int sb = 250;
  static const int se = 240;
  static const int naws = 31;
  static const int echo = 1;
  static const int sga = 3;

  bool _serverEcho = false;

  Future<void> connect({Duration timeout = const Duration(seconds: 10)}) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    _socket = socket;
    socket.listen(_onRawData, onError: (Object e) {
      if (!_closed.isCompleted) _closed.complete();
    }, onDone: () {
      if (!_closed.isCompleted) _closed.complete();
    });
    // Announce window-size support, the rest is negotiated lazily.
    _sendCommand([iac, will, naws]);
  }

  void _onRawData(Uint8List chunk) {
    final out = BytesBuilder();
    var i = 0;
    while (i < chunk.length) {
      final b = chunk[i];
      if (b != iac) {
        out.addByte(b);
        i++;
        continue;
      }
      if (i + 1 >= chunk.length) break;
      final cmd = chunk[i + 1];
      if (cmd == iac) {
        out.addByte(iac);
        i += 2;
      } else if (cmd == sb) {
        // Subnegotiation: skip until IAC SE.
        var j = i + 2;
        while (j + 1 < chunk.length &&
            !(chunk[j] == iac && chunk[j + 1] == se)) {
          j++;
        }
        i = j + 2;
      } else if (cmd == will || cmd == wont || cmd == do_ || cmd == dont) {
        if (i + 2 >= chunk.length) break;
        final opt = chunk[i + 2];
        _onNegotiation(cmd, opt);
        i += 3;
      } else {
        // GA / EOR / NOP etc. - ignore.
        i += 2;
      }
    }
    final data = out.toBytes();
    if (data.isNotEmpty) _dataOut.add(Uint8List.fromList(data));
  }

  void _onNegotiation(int cmd, int opt) {
    if (cmd == will) {
      if (opt == echo) {
        _serverEcho = true;
        _sendCommand([iac, do_, opt]);
      } else {
        _sendCommand([iac, dont, opt]);
      }
    } else if (cmd == do_) {
      if (opt == naws || opt == sga) {
        _sendCommand([iac, will, opt]);
        if (opt == naws && _cols > 0) _sendNaws();
      } else {
        _sendCommand([iac, wont, opt]);
      }
    }
  }

  int _cols = 0;
  int _rows = 0;

  void resize(int cols, int rows) {
    _cols = cols;
    _rows = rows;
    if (_socket != null) _sendNaws();
  }

  void _sendNaws() {
    final cols = _cols, rows = _rows;
    // Any 0xff byte inside the payload must be escaped by doubling IAC.
    List<int> esc(int v) => v == iac ? [iac, iac] : [v];
    _sendCommand([
      iac, sb, naws,
      ...esc((cols >> 8) & 0xff), ...esc(cols & 0xff),
      ...esc((rows >> 8) & 0xff), ...esc(rows & 0xff),
      iac, se,
    ]);
  }

  void _sendCommand(List<int> bytes) {
    _socket?.add(bytes);
  }

  /// Send terminal input. `\n` is converted to `\r\n` for telnet servers.
  void write(String data) {
    final normalized = data.replaceAll('\r\n', '\r\n').replaceAll('\n', '\r\n');
    _socket?.add(utf8.encode(normalized));
  }

  Future<void> close() async {
    await _socket?.close();
    _socket = null;
    if (!_closed.isCompleted) _closed.complete();
    await _dataOut.close();
  }

  /// Whether the server performs local echo suppression already.
  bool get serverEchoes => _serverEcho;
}
