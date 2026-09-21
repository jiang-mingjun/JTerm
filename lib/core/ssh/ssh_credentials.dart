/// Runtime credential bundle used to establish one SSH connection.
/// Populated by the UI layer from the vault / user prompts.
library;

class SshCredentials {
  SshCredentials({
    required this.username,
    this.password,
    this.privateKeyPem,
    this.keyPassphrase,
  });

  final String username;
  final String? password;
  final String? privateKeyPem;
  final String? keyPassphrase;

  bool get hasKey => privateKeyPem != null && privateKeyPem!.isNotEmpty;
  bool get hasPassword => password != null && password!.isNotEmpty;
}
