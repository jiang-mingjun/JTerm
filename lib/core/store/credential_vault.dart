/// Encrypted credential vault.
///
/// Secrets (passwords / key passphrases) never touch disk in plain text:
///   master password --PBKDF2(150k)--> AES-256-GCM key
///   payload JSON --AES-256-GCM--> vault file
/// This is a pure-Dart module (cryptography package) and therefore portable
/// to every platform, including HarmonyOS later.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class VaultEntry {
  VaultEntry({
    required this.id,
    required this.name,
    this.username,
    this.password,
    this.keyPath,
    this.passphrase,
  });

  final String id;
  String name;
  String? username;
  String? password;
  String? keyPath;
  String? passphrase;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'password': password,
        'keyPath': keyPath,
        'passphrase': passphrase,
      };

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        username: json['username'] as String?,
        password: json['password'] as String?,
        keyPath: json['keyPath'] as String?,
        passphrase: json['passphrase'] as String?,
      );
}

enum VaultState { empty, locked, unlocked }

class CredentialVault {
  CredentialVault._(this._file);

  static const _pbkdf2Iterations = 150000;

  final File _file;
  final List<VaultEntry> entries = [];

  /// Salt + nonce persisted next to the ciphertext.
  List<int> _salt = [];
  List<int> _nonce = [];
  List<int> _mac = [];
  String _cipherBase64 = '';

  String? _masterKeyInput;

  static Future<CredentialVault> open(String path) async {
    final v = CredentialVault._(File(path));
    await v._loadHeader();
    return v;
  }

  VaultState get state {
    if (!_file.existsSync() || _cipherBase64.isEmpty) return VaultState.empty;
    return _masterKeyInput == null ? VaultState.locked : VaultState.unlocked;
  }

  Future<void> _loadHeader() async {
    if (!_file.existsSync()) return;
    try {
      final data =
          jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      _salt = base64Decode(data['salt'] as String? ?? '');
      _nonce = base64Decode(data['nonce'] as String? ?? '');
      _mac = base64Decode(data['mac'] as String? ?? '');
      _cipherBase64 = data['payload'] as String? ?? '';
    } catch (_) {
      // Header unreadable - treat as empty vault.
      _cipherBase64 = '';
    }
  }

  bool get exists => _file.existsSync() && _cipherBase64.isNotEmpty;

  /// Creates a brand new vault protected by [masterPassword].
  Future<void> initialize(String masterPassword) async {
    _masterKeyInput = masterPassword;
    _salt = List.generate(16, (_) => Random.secure().nextInt(256));
    _nonce = List.generate(12, (_) => Random.secure().nextInt(256));
    await _save();
  }

  Future<bool> unlock(String masterPassword) async {
    if (!exists) return false;
    try {
      final key = await _deriveKey(masterPassword);
      // decrypt() of a SecretCipher returns the plain text directly.
      final clearText = await AesGcm.with256bits().decrypt(
          SecretBox(base64Decode(_cipherBase64), nonce: _nonce, mac: Mac(_mac)),
          secretKey: key);
      final payload =
          jsonDecode(utf8.decode(clearText)) as Map<String, dynamic>;
      entries
        ..clear()
        ..addAll((payload['entries'] as List<dynamic>)
            .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>)));
      _masterKeyInput = masterPassword;
      return true;
    } catch (_) {
      return false;
    }
  }

  void lock() {
    _masterKeyInput = null;
    entries.clear();
  }

  VaultEntry? byId(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> addOrUpdate(VaultEntry entry) async {
    final i = entries.indexWhere((e) => e.id == entry.id);
    if (i >= 0) {
      entries[i] = entry;
    } else {
      entries.add(entry);
    }
    await _save();
  }

  Future<void> delete(String id) async {
    entries.removeWhere((e) => e.id == id);
    await _save();
  }

  Future<SecretKey> _deriveKey(String password) async {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: _salt,
    );
  }

  Future<void> _save() async {
    if (_masterKeyInput == null) return;
    final key = await _deriveKey(_masterKeyInput!);
    final payload =
        utf8.encode(jsonEncode({'entries': entries.map((e) => e.toJson()).toList()}));
    final box = await AesGcm.with256bits().encrypt(payload,
        secretKey: key, nonce: _nonce);
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode({
          'version': 1,
          'salt': base64Encode(_salt),
          'nonce': base64Encode(_nonce),
          'mac': base64Encode(box.mac.bytes),
          'payload': base64Encode(box.cipherText),
        }));
  }
}
