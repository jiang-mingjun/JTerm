/// Session configuration model - the persisted description of one connectable
/// target (SSH / local shell / telnet / serial), fully mirroring the session
/// settings sheet of MobaXterm.
library;

import 'forward_rule.dart';

enum SessionType { ssh, localShell, telnet, serial }

enum AuthMethod { password, publicKey, agent }

enum ReconnectPolicy { never, onDrop, always }

enum ProxyKind { none, socks5, httpConnect }

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
    this.agentForwarding = false,
    this.compression = false,
    this.startupCommand,
    this.keepAliveSeconds = 15,
    this.forwards = const [],
    this.serialBaudRate = 115200,
    this.serialDevice,
    this.serialDataBits = 8,
    this.serialParity = 'none',
    this.serialStopBits = 1,
    this.group = '',
    this.notes = '',
    this.autoOpenSftp = true,
    this.followTerminalFolder = true,
    this.logSession = false,
    this.autoConnect = false,
    this.saved = true,
    this.reconnect = ReconnectPolicy.onDrop,
    this.proxyKind = ProxyKind.none,
    this.proxyHost,
    this.proxyPort = 1080,
    this.proxyUsername,
    this.scrollback = 20000,
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
  bool agentForwarding;
  bool compression;
  String? startupCommand;
  int keepAliveSeconds;
  List<ForwardRule> forwards;

  // ---- outbound proxy (SOCKS5 / HTTP CONNECT) ----
  ProxyKind proxyKind;
  String? proxyHost;
  int proxyPort;
  String? proxyUsername;

  // ---- serial ----
  int serialBaudRate;
  String? serialDevice;
  int serialDataBits;
  String serialParity;
  int serialStopBits;

  // ---- organisation / ui ----
  String group;
  String notes;
  bool autoOpenSftp;
  bool followTerminalFolder;
  bool logSession;
  bool autoConnect;

  /// Quick-connect entries stay in history but out of the bookmark tree.
  bool saved;
  ReconnectPolicy reconnect;
  int scrollback;

  /// Material color seed used for the tab indicator (0-4).
  int color;
  int createdMs;
  int lastUsedMs;

  String get displayHost => host ?? '';

  String get subtitle {
    switch (type) {
      case SessionType.ssh:
        final via = jumpViaSessionId == null ? '' : ' · jump';
        final px = proxyKind == ProxyKind.none ? '' : ' · proxy';
        return '${username == null || username!.isEmpty ? '' : '$username@'}$host:$port$via$px';
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
        'agentForwarding': agentForwarding,
        'compression': compression,
        'startupCommand': startupCommand,
        'keepAliveSeconds': keepAliveSeconds,
        'forwards': forwards.map((f) => f.toJson()).toList(),
        'serialBaudRate': serialBaudRate,
        'serialDevice': serialDevice,
        'serialDataBits': serialDataBits,
        'serialParity': serialParity,
        'serialStopBits': serialStopBits,
        'group': group,
        'notes': notes,
        'autoOpenSftp': autoOpenSftp,
        'followTerminalFolder': followTerminalFolder,
        'logSession': logSession,
        'autoConnect': autoConnect,
        'saved': saved,
        'reconnect': reconnect.name,
        'proxyKind': proxyKind.name,
        'proxyHost': proxyHost,
        'proxyPort': proxyPort,
        'proxyUsername': proxyUsername,
        'scrollback': scrollback,
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
        agentForwarding: json['agentForwarding'] as bool? ?? false,
        compression: json['compression'] as bool? ?? false,
        startupCommand: json['startupCommand'] as String?,
        keepAliveSeconds: (json['keepAliveSeconds'] as num?)?.toInt() ?? 15,
        forwards: (json['forwards'] as List<dynamic>? ?? [])
            .map((e) => ForwardRule.fromJson(e as Map<String, dynamic>))
            .toList(),
        serialBaudRate: (json['serialBaudRate'] as num?)?.toInt() ?? 115200,
        serialDevice: json['serialDevice'] as String?,
        serialDataBits: (json['serialDataBits'] as num?)?.toInt() ?? 8,
        serialParity: json['serialParity'] as String? ?? 'none',
        serialStopBits: (json['serialStopBits'] as num?)?.toInt() ?? 1,
        group: json['group'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        autoOpenSftp: json['autoOpenSftp'] as bool? ?? true,
        followTerminalFolder: json['followTerminalFolder'] as bool? ?? true,
        logSession: json['logSession'] as bool? ?? false,
        autoConnect: json['autoConnect'] as bool? ??
            json['launchAtStartup'] as bool? ??
            false,
        saved: json['saved'] as bool? ?? true,
        reconnect: ReconnectPolicy.values.firstWhere(
          (r) => r.name == json['reconnect'],
          orElse: () => ReconnectPolicy.onDrop,
        ),
        proxyKind: ProxyKind.values.firstWhere(
          (k) => k.name == json['proxyKind'],
          orElse: () => ProxyKind.none,
        ),
        proxyHost: json['proxyHost'] as String?,
        proxyPort: (json['proxyPort'] as num?)?.toInt() ?? 1080,
        proxyUsername: json['proxyUsername'] as String?,
        scrollback: (json['scrollback'] as num?)?.toInt() ?? 20000,
        color: (json['color'] as num?)?.toInt() ?? 0,
        createdMs: (json['createdMs'] as num?)?.toInt() ?? 0,
        lastUsedMs: (json['lastUsedMs'] as num?)?.toInt() ??
            (json['lastUsed'] as num?)?.toInt() ??
            0,
      );

  SessionProfile copyWith() => SessionProfile.fromJson(toJson());
}
