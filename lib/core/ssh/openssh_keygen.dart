/// Generates an OpenSSH key pair by calling the system `ssh-keygen`.
library;

import 'dart:io';

class KeygenResult {
  KeygenResult({required this.privatePath, required this.publicKey});

  final String privatePath;
  final String publicKey;
}

Future<KeygenResult> generateOpenSshKey({
  required String path,
  String type = 'ed25519',
  String comment = 'jterm',
  String passphrase = '',
  int rsaBits = 4096,
}) async {
  if (File(path).existsSync()) {
    throw StateError('私钥已存在: $path');
  }
  final args = <String>[
    '-t',
    type,
    '-f',
    path,
    '-N',
    passphrase,
    '-C',
    comment,
    '-q',
  ];
  if (type == 'rsa') {
    args.addAll(['-b', '$rsaBits']);
  }
  final result = await Process.run('ssh-keygen', args);
  if (result.exitCode != 0) {
    final err = '${result.stderr}'.trim();
    throw StateError(err.isEmpty ? 'ssh-keygen 失败 (${result.exitCode})' : err);
  }
  final pubFile = File('$path.pub');
  final publicKey = pubFile.existsSync() ? (await pubFile.readAsString()).trim() : '';
  return KeygenResult(privatePath: path, publicKey: publicKey);
}
