/// App-wide state: storage bootstrap, credential vault, known hosts and the
/// UI-driven connect hooks (host key prompts, password prompts).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/models/session_profile.dart';
import '../core/ssh/ssh_connection.dart';
import '../core/ssh/ssh_credentials.dart';
import '../core/store/credential_vault.dart';
import '../core/store/json_store.dart';
import '../core/store/known_hosts_store.dart';
import '../core/store/session_repository.dart';
import '../core/terminal/session_services.dart';
import '../core/terminal/ssh_terminal_session.dart';
import '../ui/dialogs/app_dialogs.dart';
import 'settings_state.dart';

class AppState extends ChangeNotifier {
  final navigatorKey = GlobalKey<NavigatorState>();

  late final String dataDir;
  late final SessionRepository repo;
  late final CredentialVault vault;
  late final KnownHostsStore knownHosts;
  late final SettingsState settings;
  late final SessionServices services;

  bool initialized = false;
  String? initError;

  BuildContext? get _ctx => navigatorKey.currentContext;

  Future<void> init() async {
    try {
      final base = await getApplicationSupportDirectory();
      dataDir = base.path;
      repo = SessionRepository(JsonStore('$dataDir/sessions.json'));
      vault = await CredentialVault.open('$dataDir/vault.json');
      knownHosts = KnownHostsStore(JsonStore('$dataDir/known_hosts.json'));
      settings = await SettingsState.load();
      await repo.load();
      await knownHosts.load();

      // Let the SSH core resolve jump-host profiles through the repository.
      SshTerminalSession.jumpProfileLookup = repo.byId;

      services = SessionServices(
        vault: vault,
        knownHosts: knownHosts,
        hooks: SshConnectHooks(
          verifyHostKey: _askHostKey,
          missingPassword: _askSecret,
        ),
        resolveCredentials: resolveCredentials,
      );
      initialized = true;
    } catch (e) {
      initError = e.toString();
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Connect hooks backed by dialogs
  // ------------------------------------------------------------------
  Future<HostKeyDecision> _askHostKey(
      String host, String keyType, String fingerprint) async {
    final ctx = _ctx;
    if (ctx == null) return HostKeyDecision.reject;
    final existing = knownHosts.verify(host, fingerprint);
    return showHostKeyDialog(
      ctx,
      host: host,
      keyType: keyType,
      fingerprint: fingerprint,
      changed: existing == false,
    );
  }

  Future<String?> _askSecret(String prompt,
      {bool obscure = true, String? initial}) async {
    final ctx = _ctx;
    if (ctx == null) return null;
    return showPromptDialog(
      ctx,
      title: prompt,
      obscure: obscure,
      initialValue: initial,
    );
  }

  // ------------------------------------------------------------------
  // Credential resolution for a session profile
  // ------------------------------------------------------------------
  Future<SshCredentials?> resolveCredentials(SessionProfile profile) async {
    var username = profile.username ?? '';
    String? password;
    String? keyPem;
    String? keyPass;

    final credId = profile.credentialId;
    if (credId != null && vault.state == VaultState.unlocked) {
      final entry = vault.byId(credId);
      if (entry != null) {
        username = entry.username ?? username;
        password = entry.password;
        keyPass = entry.passphrase;
      }
    }

    final keyPath = profile.privateKeyPath;
    if (profile.authMethod == AuthMethod.publicKey && keyPath != null) {
      try {
        keyPem = await File(keyPath).readAsString();
      } catch (e) {
        keyPem = null;
      }
      if (keyPem == null) {
        // The key file is unreadable; fall back to password auth below.
      }
    }

    if (username.isEmpty) {
      username = await _askSecret('Username for ${profile.host}',
              obscure: false, initial: '') ??
          '';
      if (username.isEmpty) return null;
    }

    if (password == null && keyPem == null) {
      password = await _askSecret(
        'Password for $username@${profile.host}',
        obscure: true,
      );
      if (password == null || password.isEmpty) return null;
    }

    return SshCredentials(
      username: username,
      password: password,
      privateKeyPem: keyPem,
      keyPassphrase: keyPass,
    );
  }

  // ------------------------------------------------------------------
  // Vault management
  // ------------------------------------------------------------------
  Future<bool> unlockVault(String masterPassword) async {
    final ok = await vault.unlock(masterPassword);
    notifyListeners();
    return ok;
  }

  Future<void> createVault(String masterPassword) async {
    await vault.initialize(masterPassword);
    notifyListeners();
  }

  void lockVault() {
    vault.lock();
    notifyListeners();
  }

  @override
  void dispose() {
    settings.dispose();
    super.dispose();
  }
}
