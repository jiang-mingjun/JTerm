/// Services bundle injected into terminal sessions by the UI layer.
/// Keeps [core] free of Flutter UI dependencies.
library;

import '../models/session_profile.dart';
import '../store/credential_vault.dart';
import '../store/known_hosts_store.dart';
import '../ssh/ssh_connection.dart';
import '../ssh/ssh_credentials.dart';

typedef CredentialResolver = Future<SshCredentials?> Function(SessionProfile profile);

class SessionServices {
  SessionServices({
    required this.vault,
    required this.knownHosts,
    required this.hooks,
    required this.resolveCredentials,
  });

  final CredentialVault vault;
  final KnownHostsStore knownHosts;
  final SshConnectHooks hooks;
  final CredentialResolver resolveCredentials;
}
