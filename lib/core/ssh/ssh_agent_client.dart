/// OpenSSH agent client (`SSH_AUTH_SOCK`).
///
/// Speaks the agent protocol both as an authentication identity source and as
/// the handler dartssh2 uses for `auth-agent-req` forwarding.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

class SshAgentException implements Exception {
  SshAgentException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AgentIdentity {
  AgentIdentity({required this.blob, required this.comment});

  final Uint8List blob;
  final String comment;

  String get keyType {
    if (blob.length < 4) return '';
    final len = ByteData.sublistView(blob).getUint32(0);
    if (blob.length < 4 + len) return '';
    return String.fromCharCodes(blob.sublist(4, 4 + len));
  }
}

class SshAgentClient implements SSHAgentHandler {
  SshAgentClient._(this._socket);

  final Socket _socket;
  final _inbox = <int>[];
  Completer<void>? _wait;
  bool _closed = false;
  Future<void> _lock = Future.value();

  static Future<SshAgentClient?> connect([String? socketPath]) async {
    final path = socketPath ?? Platform.environment['SSH_AUTH_SOCK'];
    if (path == null || path.isEmpty) return null;
    try {
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
        timeout: const Duration(seconds: 3),
      );
      final client = SshAgentClient._(socket);
      socket.listen(
        (chunk) {
          client._inbox.addAll(chunk);
          client._poke();
        },
        onDone: () {
          client._closed = true;
          client._poke();
        },
        onError: (Object _) {
          client._closed = true;
          client._poke();
        },
      );
      return client;
    } catch (_) {
      return null;
    }
  }

  void _poke() {
    final w = _wait;
    _wait = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<Uint8List> _transact(Uint8List payload) {
    final result = Completer<Uint8List>();
    _lock = _lock.then((_) async {
      try {
        final frame = BytesBuilder()
          ..add(_u32(payload.length))
          ..add(payload);
        _socket.add(frame.takeBytes());
        final response = await _readFrame();
        result.complete(response);
      } catch (e, s) {
        if (!result.isCompleted) result.completeError(e, s);
      }
    });
    return result.future;
  }

  Future<Uint8List> _readFrame() async {
    while (_inbox.length < 4) {
      if (_closed) throw SshAgentException('SSH agent 连接已关闭');
      _wait = Completer<void>();
      await _wait!.future;
    }
    final len = ByteData.sublistView(Uint8List.fromList(_inbox), 0, 4).getUint32(0);
    while (_inbox.length < 4 + len) {
      if (_closed) throw SshAgentException('SSH agent 连接已关闭');
      _wait = Completer<void>();
      await _wait!.future;
    }
    final payload = Uint8List.fromList(_inbox.sublist(4, 4 + len));
    _inbox.removeRange(0, 4 + len);
    return payload;
  }

  @override
  Future<Uint8List> handleRequest(Uint8List request) => _transact(request);

  Future<List<AgentIdentity>> listIdentities() async {
    final resp = await _transact(Uint8List.fromList([11]));
    if (resp.isEmpty || resp[0] != 12) return const [];
    final data = ByteData.sublistView(resp);
    var o = 1;
    if (resp.length < 5) return const [];
    final count = data.getUint32(o);
    o += 4;
    final list = <AgentIdentity>[];
    for (var i = 0; i < count; i++) {
      if (o + 4 > resp.length) break;
      final klen = data.getUint32(o);
      o += 4;
      if (o + klen > resp.length) break;
      final blob = Uint8List.fromList(resp.sublist(o, o + klen));
      o += klen;
      if (o + 4 > resp.length) break;
      final clen = data.getUint32(o);
      o += 4;
      if (o + clen > resp.length) break;
      final comment = utf8Safe(resp.sublist(o, o + clen));
      o += clen;
      list.add(AgentIdentity(blob: blob, comment: comment));
    }
    return list;
  }

  Future<Uint8List> sign(Uint8List keyBlob, Uint8List data, {int flags = 0}) async {
    final payload = BytesBuilder()
      ..addByte(13)
      ..add(_string(keyBlob))
      ..add(_string(data))
      ..add(_u32(flags));
    final resp = await _transact(payload.toBytes());
    if (resp.isEmpty || resp[0] != 14 || resp.length < 5) {
      throw SshAgentException('SSH agent 拒绝签名');
    }
    final slen = ByteData.sublistView(resp, 1, 5).getUint32(0);
    if (resp.length < 5 + slen) {
      throw SshAgentException('SSH agent 签名长度无效');
    }
    return Uint8List.fromList(resp.sublist(5, 5 + slen));
  }

  /// Identities the SSH client can offer during public-key authentication.
  Future<List<SSHIdentity>> identities() async {
    final list = await listIdentities();
    return [
      for (final id in list)
        SSHIdentity.custom(
          type: _authType(id.keyType),
          publicKey: SSHRawHostKey(id.blob),
          comment: id.comment,
          shouldProbe: true,
          signer: (data) async {
            final flags = id.keyType == 'ssh-rsa' ? 2 : 0;
            return SSHRawSignature(await sign(id.blob, data, flags: flags));
          },
        ),
    ];
  }

  Future<void> close() => _socket.close();

  static String _authType(String keyType) {
    if (keyType == 'ssh-rsa') return 'rsa-sha2-256';
    return keyType;
  }
}

Uint8List _u32(int v) => Uint8List(4)
  ..buffer.asByteData().setUint32(0, v);

Uint8List _string(Uint8List bytes) {
  final out = Uint8List(4 + bytes.length);
  out.buffer.asByteData().setUint32(0, bytes.length);
  out.setRange(4, out.length, bytes);
  return out;
}

String utf8Safe(List<int> bytes) {
  try {
    return String.fromCharCodes(bytes);
  } catch (_) {
    return '';
  }
}
