/// SOCKS5 CONNECT client (RFC 1928, no authentication).
///
/// Produces an [SSHSocket] so dartssh2 can speak SSH through an HTTP-unaware
/// proxy, the same way MobaXterm's proxy setting does.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'byte_queue.dart';

Future<SSHSocket> connectSocks5({
  required String proxyHost,
  required int proxyPort,
  required String targetHost,
  required int targetPort,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final socket = await Socket.connect(proxyHost, proxyPort, timeout: timeout);
  final queue = ByteQueue(socket);
  try {
    socket.add(const [0x05, 0x01, 0x00]);
    final greeting = await queue.take(2).timeout(timeout);
    if (greeting[0] != 0x05 || greeting[1] != 0x00) {
      throw StateError('SOCKS5 代理拒绝了无认证握手');
    }

    final hostBytes = Uint8List.fromList(targetHost.codeUnits);
    if (hostBytes.length > 255) {
      throw StateError('目标主机名过长');
    }
    final request = BytesBuilder(copy: false)
      ..add(const [0x05, 0x01, 0x00, 0x03])
      ..add([hostBytes.length])
      ..add(hostBytes)
      ..add([(targetPort >> 8) & 0xff, targetPort & 0xff]);
    socket.add(request.takeBytes());

    final head = await queue.take(4).timeout(timeout);
    if (head[1] != 0x00) {
      throw StateError('SOCKS5 连接失败 (${_socksError(head[1])})');
    }
    switch (head[3]) {
      case 0x01:
        await queue.take(4 + 2).timeout(timeout);
      case 0x03:
        final len = (await queue.take(1).timeout(timeout))[0];
        await queue.take(len + 2).timeout(timeout);
      case 0x04:
        await queue.take(16 + 2).timeout(timeout);
      default:
        throw StateError('SOCKS5 返回了未知地址类型');
    }
    return _SocksSocket(socket, queue.detachStream());
  } catch (_) {
    await queue.close();
    socket.destroy();
    rethrow;
  }
}

String _socksError(int code) {
  return switch (code) {
    0x01 => '一般性失败',
    0x02 => '规则不允许',
    0x03 => '网络不可达',
    0x04 => '主机不可达',
    0x05 => '连接被拒绝',
    0x06 => 'TTL 超时',
    0x07 => '命令不支持',
    0x08 => '地址类型不支持',
    _ => '错误码 $code',
  };
}

class _SocksSocket implements SSHSocket {
  _SocksSocket(this._socket, this._stream);

  final Socket _socket;
  final Stream<Uint8List> _stream;

  @override
  Stream<Uint8List> get stream => _stream;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> close() => _socket.close();

  @override
  void destroy() => _socket.destroy();

  @override
  Future<void> flush() => _socket.flush();
}
