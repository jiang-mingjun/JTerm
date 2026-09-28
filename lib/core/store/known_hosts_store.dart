/// Trust-on-first-use host key store, the equivalent of ~/.ssh/known_hosts.
library;

import 'json_store.dart';

class KnownHost {
  KnownHost({
    required this.fingerprint,
    required this.host,
    required this.keyType,
    required this.firstSeenMs,
  });

  final String fingerprint; // SHA256 base64 (OpenSSH format)
  String host;
  String keyType;
  int firstSeenMs;

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'host': host,
        'keyType': keyType,
        'firstSeenMs': firstSeenMs,
      };

  factory KnownHost.fromJson(Map<String, dynamic> json) => KnownHost(
        fingerprint: json['fingerprint'] as String,
        host: json['host'] as String,
        keyType: json['keyType'] as String? ?? 'ssh-ed25519',
        firstSeenMs: (json['firstSeenMs'] as num?)?.toInt() ?? 0,
      );
}

class KnownHostsStore {
  KnownHostsStore(this.store);

  final JsonStore store;
  final List<KnownHost> _hosts = [];

  List<KnownHost> get hosts => List.unmodifiable(_hosts);

  Future<void> load() async {
    final data = await store.read();
    if (data == null) return;
    _hosts
      ..clear()
      ..addAll((data['hosts'] as List<dynamic>? ?? [])
          .map((e) => KnownHost.fromJson(e as Map<String, dynamic>)));
  }

  /// Returns:
  ///  - `true`  -> fingerprint known and matching
  ///  - `false` -> fingerprint CHANGED for this host (danger!)
  ///  - `null`  -> host never seen before (caller should ask the user)
  bool? verify(String host, String fingerprint) {
    var sawHost = false;
    for (final h in _hosts) {
      if (h.host == host) {
        sawHost = true;
        if (h.fingerprint == fingerprint) return true;
      }
    }
    return sawHost ? false : null;
  }

  Future<void> trust(String host, String fingerprint, String keyType) async {
    _hosts.removeWhere((h) => h.host == host && h.fingerprint == fingerprint);
    _hosts.add(KnownHost(
      fingerprint: fingerprint,
      host: host,
      keyType: keyType,
      firstSeenMs: DateTime.now().millisecondsSinceEpoch,
    ));
    await _persist();
  }

  Future<void> forget(String host) async {
    _hosts.removeWhere((h) => h.host == host);
    await _persist();
  }

  Future<void> _persist() =>
      store.write({'hosts': _hosts.map((h) => h.toJson()).toList()});
}
