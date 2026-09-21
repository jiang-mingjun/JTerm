/// Port-forwarding rule model (-L / -R / -D), the equivalent of the
/// MobaXterm tunneling page.
library;

enum ForwardType { local, remote, dynamic }

class ForwardRule {
  ForwardRule({
    required this.id,
    required this.type,
    this.localHost = '127.0.0.1',
    required this.localPort,
    this.remoteHost,
    this.remotePort,
    this.autoStart = true,
    this.enabled = true,
  });

  final String id;
  ForwardType type;

  /// Bind address on the local machine (L/D) or on the remote (R).
  String localHost;
  int localPort;

  /// Destination for -L / -R rules.
  String? remoteHost;
  int? remotePort;

  bool autoStart;
  bool enabled;

  bool get isValid {
    switch (type) {
      case ForwardType.dynamic:
        return localPort > 0;
      case ForwardType.local:
      case ForwardType.remote:
        return localPort > 0 &&
            (remoteHost ?? '').isNotEmpty &&
            (remotePort ?? 0) > 0;
    }
  }

  /// Same notation as OpenSSH, e.g. `L 127.0.0.1:8080 -> intranet:80`.
  String describe() {
    switch (type) {
      case ForwardType.local:
        return 'L $localHost:$localPort -> $remoteHost:$remotePort';
      case ForwardType.remote:
        return 'R $remoteHost:$remotePort -> $localHost:$localPort';
      case ForwardType.dynamic:
        return 'D $localHost:$localPort (SOCKS5)';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'localHost': localHost,
        'localPort': localPort,
        'remoteHost': remoteHost,
        'remotePort': remotePort,
        'autoStart': autoStart,
        'enabled': enabled,
      };

  factory ForwardRule.fromJson(Map<String, dynamic> json) => ForwardRule(
        id: json['id'] as String,
        type: ForwardType.values.firstWhere((t) => t.name == json['type']),
        localHost: json['localHost'] as String? ?? '127.0.0.1',
        localPort: (json['localPort'] as num).toInt(),
        remoteHost: json['remoteHost'] as String?,
        remotePort: (json['remotePort'] as num?)?.toInt(),
        autoStart: json['autoStart'] as bool? ?? true,
        enabled: json['enabled'] as bool? ?? true,
      );
}
