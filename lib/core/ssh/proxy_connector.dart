/// Outbound proxies in front of an SSH transport: SOCKS5 and HTTP CONNECT.
///
/// The proxy handshake and the later SSH stream share one socket subscription,
/// so bytes that arrive in the same chunk as the proxy reply are not dropped.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/session_profile.dart';

class ProxyException implements Exception {
  ProxyException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ProxyConnector {
  /// Opens a TCP stream to [targetHost]:[targetPort] via [kind].
  static Future<SSHSocket> open({
    required ProxyKind kind,
    required String proxyHost,
    required int proxyPort,
    required String targetHost,
    required int targetPort,
    String? username,
    String? password,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final raw = await Socket.connect(proxyHost, proxyPort, timeout: timeout);
    final socket = _ProxySocket(raw);
    try {
      switch (kind) {
        case ProxyKind.none:
          break;
        case ProxyKind.socks5:
          await _socks5(
            socket,
            targetHost: targetHost,
            targetPort: targetPort,
            username: username,
            password: password,
          );
        case ProxyKind.httpConnect:
          await _httpConnect(
            socket,
            targetHost: targetHost,
            targetPort: targetPort,
            username: username,
            password: password,
          );
      }
      socket.finishHandshake();
      return socket;
    } catch (e) {
      raw.destroy();
      rethrow;
    }
  }
}

class _ProxySocket implements SSHSocket {
  _ProxySocket(this._socket) {
    _sub = _socket.listen(
      (chunk) {
        if (_handshake) {
          _stash.addAll(chunk);
          _poke();
        } else {
          _incoming.add(chunk);
        }
      },
      onError: (Object e, StackTrace s) {
        _closedError = e;
        _poke();
        if (!_incoming.isClosed) _incoming.addError(e, s);
      },
      onDone: () {
        _closed = true;
        _poke();
        if (!_handshake && !_incoming.isClosed) _incoming.close();
      },
    );
  }

  final Socket _socket;
  final _incoming = StreamController<Uint8List>();
  final _stash = <int>[];
  StreamSubscription<Uint8List>? _sub;
  Completer<void>? _wait;
  bool _handshake = true;
  bool _closed = false;
  Object? _closedError;

  void _poke() {
    final w = _wait;
    _wait = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<void> _need(int n) async {
    while (_stash.length < n) {
      if (_closed) {
        throw ProxyException(_closedError?.toString() ?? '代理连接提前关闭');
      }
      _wait = Completer<void>();
      await _wait!.future;
    }
  }

  Future<Uint8List> readExact(int n) async {
    await _need(n);
    final out = Uint8List.fromList(_stash.sublist(0, n));
    _stash.removeRange(0, n);
    return out;
  }

  Future<String> readUntil(String marker) async {
    while (true) {
      final text = latin1.decode(_stash);
      final i = text.indexOf(marker);
      if (i >= 0) {
        final end = i + marker.length;
        final head = latin1.decode(_stash.sublist(0, end));
        _stash.removeRange(0, end);
        return head;
      }
      if (text.length > 8192) {
        throw ProxyException('HTTP 代理响应过长');
      }
      if (_closed) {
        throw ProxyException('HTTP 代理没有返回完整响应');
      }
      _wait = Completer<void>();
      await _wait!.future;
    }
  }

  void finishHandshake() {
    _handshake = false;
    if (_stash.isNotEmpty) {
      final left = Uint8List.fromList(_stash);
      _stash.clear();
      _incoming.add(left);
    }
    if (_closed && !_incoming.isClosed) {
      _incoming.close();
    }
  }

  @override
  Stream<Uint8List> get stream => _incoming.stream;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _socket.close();
    if (!_incoming.isClosed) await _incoming.close();
  }

  @override
  void destroy() {
    _sub?.cancel();
    _socket.destroy();
    if (!_incoming.isClosed) _incoming.close();
  }

  @override
  Future<void> flush() => _socket.flush();
}

Future<void> _socks5(
  _ProxySocket socket, {
  required String targetHost,
  required int targetPort,
  String? username,
  String? password,
}) async {
  final user = username ?? '';
  final pass = password ?? '';
  final auth = user.isNotEmpty;
  socket.sink.add(auth
      ? Uint8List.fromList([0x05, 0x02, 0x00, 0x02])
      : Uint8List.fromList([0x05, 0x01, 0x00]));
  final greet = await socket.readExact(2);
  if (greet[0] != 0x05) {
    throw ProxyException('SOCKS5 握手失败');
  }
  if (greet[1] == 0x02) {
    final u = utf8.encode(user);
    final p = utf8.encode(pass);
    if (u.length > 255 || p.length > 255) {
      throw ProxyException('SOCKS5 用户名或密码过长');
    }
    socket.sink.add(Uint8List.fromList([0x01, u.length, ...u, p.length, ...p]));
    final status = await socket.readExact(2);
    if (status[1] != 0x00) {
      throw ProxyException('SOCKS5 认证被拒绝');
    }
  } else if (greet[1] != 0x00) {
    throw ProxyException('SOCKS5 代理不接受所选认证方式');
  }

  final hostBytes = utf8.encode(targetHost);
  if (hostBytes.length > 255) {
    throw ProxyException('目标主机名过长');
  }
  socket.sink.add(Uint8List.fromList([
    0x05,
    0x01,
    0x00,
    0x03,
    hostBytes.length,
    ...hostBytes,
    (targetPort >> 8) & 0xff,
    targetPort & 0xff,
  ]));
  final head = await socket.readExact(4);
  if (head[1] != 0x00) {
    throw ProxyException('SOCKS5 连接失败 (code ${head[1]})');
  }
  switch (head[3]) {
    case 0x01:
      await socket.readExact(4 + 2);
    case 0x03:
      final len = (await socket.readExact(1))[0];
      await socket.readExact(len + 2);
    case 0x04:
      await socket.readExact(16 + 2);
    default:
      throw ProxyException('SOCKS5 返回了未知地址类型');
  }
}

Future<void> _httpConnect(
  _ProxySocket socket, {
  required String targetHost,
  required int targetPort,
  String? username,
  String? password,
}) async {
  final buf = StringBuffer()
    ..write('CONNECT $targetHost:$targetPort HTTP/1.1\r\n')
    ..write('Host: $targetHost:$targetPort\r\n');
  final user = username ?? '';
  if (user.isNotEmpty) {
    final token = base64Encode(utf8.encode('$user:${password ?? ''}'));
    buf.write('Proxy-Authorization: Basic $token\r\n');
  }
  buf.write('\r\n');
  socket.sink.add(utf8.encode(buf.toString()));

  final header = await socket.readUntil('\r\n\r\n');
  final status = header.split('\r\n').first;
  if (!status.contains(' 200 ')) {
    throw ProxyException('HTTP 代理拒绝 CONNECT: $status');
  }
}
