/// Session configuration model - the persisted description of one connectable
/// target (SSH / local shell / telnet / serial), fully mirroring the session
/// settings sheet of MobaXterm.
library;

import 'forward_rule.dart';

enum SessionType { ssh, localShell, telnet, serial }

enum AuthMethod { password, publicKey }

enum ReconnectPolicy { never, onDrop, always }

class SessionProfile {
  SessionProfile({
    required this.id,
    required this.name,
    required this.type,
    this.host,
    this.port = 22,
    this.username,
    this.authMethod = AuthMethod.password,
    this.credentialId,
    this.privateKeyPath,
    this.jumpViaSessionId,
    this.x11Forwarding = false,
    this.compression = false,
    this.startupCommand,
    this.keepAliveSeconds = 15,
    this.forwards = const [],
    this.serialBaudRate = 115200,
    this.serialDevice,
    this.group = '',
    this.autoOpenSftp = true,
    this.reconnect = ReconnectPolicy.onDrop,
    this.color = 0,
    this.createdMs = 0,
    this.lastUsedMs = 0,
  });

  String id;
  String name;
  SessionType type;

  // ---- network target ----
  String? host;
  int port;
  String? username;

  // ---- auth ----
  AuthMethod authMethod;

  /// Reference into the encrypted credential vault.
  String? credentialId;
  String? privateKeyPath;

  /// Cascade through another saved SSH session (jump host).
  String? jumpViaSessionId;

  // ---- ssh advanced ----
  bool x11Forwarding;
  bool compression;
  String? startupCommand;
  int keepAliveSeconds;
  List<ForwardRule> forwards;

  // ---- serial ----
  int serialBaudRate;
  String? serialDevice;

  // ---- organisation / ui ----
  String group;
  bool autoOpenSftp;
  ReconnectPolicy reconnect;

  /// Material color seed used for the tab indicator (0-4).
  int color;
  int createdMs;
  int lastUsedMs;

  String get displayHost => host ?? '';

  String get subtitle {
    switch (type) {
      case SessionType.ssh:
        return '${username == null || username!.isEmpty ? '' : '$username@'}$host:$port';
      case SessionType.localShell:
        return 'local shell';
      case SessionType.telnet:
        return 'telnet $host:$port';
      case SessionType.serial:
        return 'serial ${serialDevice ?? ''} @${serialBaudRate}bd';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'host': host,
        'port': port,
        'username': username,
        'authMethod': authMethod.name,
        'credentialId': credentialId,
        'privateKeyPath': privateKeyPath,
        'jumpViaSessionId': jumpViaSessionId,
        'x11Forwarding': x11Forwarding,
        'compression': compression,
        'startupCommand': startupCommand,
        'keepAliveSeconds': keepAliveSeconds,
        'forwards': forwards.map((f) => f.toJson()).toList(),
        'serialBaudRate': serialBaudRate,
        'serialDevice': serialDevice,
        'group': group,
        'autoOpenSftp': autoOpenSftp,
        'reconnect': reconnect.name,
        'color': color,
        'createdMs': createdMs,
        'lastUsedMs': lastUsedMs,
      };

  factory SessionProfile.fromJson(Map<String, dynamic> json) => SessionProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        type: SessionType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => SessionType.ssh,
        ),
        host: json['host'] as String?,
        port: (json['port'] as num?)?.toInt() ?? 22,
        username: json['username'] as String?,
        authMethod: AuthMethod.values.firstWhere(
          (a) => a.name == json['authMethod'],
          orElse: () => AuthMethod.password,
        ),
        credentialId: json['credentialId'] as String?,
        privateKeyPath: json['privateKeyPath'] as String?,
        jumpViaSessionId: json['jumpViaSessionId'] as String?,
        x11Forwarding: json['x11Forwarding'] as bool? ?? false,
        compression: json['compression'] as bool? ?? false,
        startupCommand: json['startupCommand'] as String?,
        keepAliveSeconds: (json['keepAliveSeconds'] as num?)?.toInt() ?? 15,
        forwards: (json['forwards'] as List<dynamic>? ?? [])
            .map((e) => ForwardRule.fromJson(e as Map<String, dynamic>))
            .toList(),
        serialBaudRate: (json['serialBaudRate'] as num?)?.toInt() ?? 115200,
        serialDevice: json['serialDevice'] as String?,
        group: json['group'] as String? ?? '',
        autoOpenSftp: json['autoOpenSftp'] as bool? ?? true,
        reconnect: ReconnectPolicy.values.firstWhere(
          (r) => r.name == json['reconnect'],
          orElse: () => ReconnectPolicy.onDrop,
        ),
        color: (json['color'] as num?)?.toInt() ?? 0,
        createdMs: (json['createdMs'] as num?)?.toInt() ?? 0,
        lastUsedMs: (json['lastUsed'] as num?)?.toInt() ?? 0,
      );

  SessionProfile copyWith() => SessionProfile.fromJson(toJson());
}
