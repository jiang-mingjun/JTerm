/// Services bundle injected into terminal sessions by the UI layer.
/// Keeps [core] free of Flutter UI dependencies.
library;

import 'dart:io';
import 'dart:typed_data';

import '../models/session_profile.dart';
import '../store/credential_vault.dart';
import '../store/known_hosts_store.dart';
import '../ssh/ssh_connection.dart';
import '../ssh/ssh_credentials.dart';

class UploadPick {
  UploadPick({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

typedef CredentialResolver = Future<SshCredentials?> Function(SessionProfile profile);

class SessionServices {
  SessionServices({
    required this.vault,
    required this.knownHosts,
    required this.hooks,
    required this.resolveCredentials,
    this.logDirectory = '',
    this.downloadDirectory = '',
    this.pickUpload,
  });

  final CredentialVault vault;
  final KnownHostsStore knownHosts;
  final SshConnectHooks hooks;
  final CredentialResolver resolveCredentials;
  final String logDirectory;
  final String downloadDirectory;

  /// UI-provided file picker used when the remote side runs `rz`.
  final Future<UploadPick?> Function()? pickUpload;

  Future<Directory> prepareDownloadDir() async {
    final path = downloadDirectory.isEmpty ? '.' : downloadDirectory;
    final dir = Directory(path);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
