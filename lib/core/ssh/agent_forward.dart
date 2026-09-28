/// SSH agent forwarding.
///
/// Prefers the local OpenSSH agent (`SSH_AUTH_SOCK`). When no agent is
/// running, the key used to log in is exposed to the remote host instead.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'byte_queue.dart';

Future<SSHAgentHandler?> buildAgentHandler(List<SSHKeyPair>? identities) async {
  final sock = Platform.environment['SSH_AUTH_SOCK'];
  if (sock != null && sock.isNotEmpty) {
    final type = await FileSystemEntity.type(sock, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      return UnixSshAgent(sock);
    }
  }
  if (identities != null && identities.isNotEmpty) {
    return SSHKeyPairAgent(identities, comment: 'jterm');
  }
  return null;
}

class UnixSshAgent implements SSHAgentHandler {
  UnixSshAgent(this.socketPath);

  final String socketPath;

  @override
  Future<Uint8List> handleRequest(Uint8List request) async {
    Socket? socket;
    ByteQueue? queue;
    try {
      socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
        timeout: const Duration(seconds: 5),
      );
      queue = ByteQueue(socket);
      final header = Uint8List(4);
      final view = ByteData.sublistView(header);
      view.setUint32(0, request.length);
      socket.add(header);
      socket.add(request);
      await socket.flush();
      final lenBytes = await queue.take(4).timeout(const Duration(seconds: 8));
      final length = ByteData.sublistView(lenBytes).getUint32(0);
      if (length <= 0 || length > 256 * 1024) {
        return Uint8List.fromList([SSHAgentProtocol.failure]);
      }
      return await queue.take(length).timeout(const Duration(seconds: 8));
    } catch (_) {
      return Uint8List.fromList([SSHAgentProtocol.failure]);
    } finally {
      await queue?.close();
      socket?.destroy();
    }
  }
}
