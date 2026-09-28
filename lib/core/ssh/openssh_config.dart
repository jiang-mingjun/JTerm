/// Parser for OpenSSH client configuration (`~/.ssh/config`).
///
/// Produces one [SessionProfile] per concrete `Host` pattern. `Host *` blocks
/// supply defaults. The first value obtained for each keyword wins, matching
/// OpenSSH. `ProxyJump a,b` becomes a jump chain (client -> a -> b -> target).
library;

import '../models/forward_rule.dart';
import '../models/session_profile.dart';

class OpenSshConfig {
  static List<SessionProfile> parse(String text, {String? home}) {
    final blocks = _blocks(text);
    final names = <String>{};
    for (final b in blocks) {
      for (final p in b.patterns) {
        if (!_isWildcard(p) && p != '*') names.add(p);
      }
    }

    final profiles = <SessionProfile>[];
    final byName = <String, SessionProfile>{};
    for (final name in names) {
      final opt = <String, List<String>>{};
      for (final b in blocks) {
        if (!b.patterns.any((p) => _glob(p, name))) continue;
        for (final e in b.options.entries) {
          opt.putIfAbsent(e.key, () => e.value);
        }
      }
      final hostName = _first(opt, 'hostname') ?? name;
      final user = _first(opt, 'user');
      final port = int.tryParse(_first(opt, 'port') ?? '') ?? 22;
      final id = 'sshcfg-${_slug(name)}';
      final identity = _expand(_first(opt, 'identityfile'), home);
      final profile = SessionProfile(
        id: id,
        name: name,
        type: SessionType.ssh,
        host: hostName,
        port: port,
        username: user,
        authMethod:
            identity != null ? AuthMethod.publicKey : AuthMethod.password,
        privateKeyPath: identity,
        x11Forwarding: _yes(_first(opt, 'forwardx11')),
        agentForwarding: _yes(_first(opt, 'forwardagent')),
        compression: _yes(_first(opt, 'compression')),
        keepAliveSeconds:
            int.tryParse(_first(opt, 'serveraliveinterval') ?? '') ?? 15,
        forwards: _forwards(opt),
        group: 'OpenSSH',
        createdMs: DateTime.now().millisecondsSinceEpoch,
      );
      profiles.add(profile);
      byName[name] = profile;
    }

    for (final name in names) {
      final opt = <String, List<String>>{};
      for (final b in blocks) {
        if (!b.patterns.any((p) => _glob(p, name))) continue;
        for (final e in b.options.entries) {
          opt.putIfAbsent(e.key, () => e.value);
        }
      }
      final jump = _first(opt, 'proxyjump');
      if (jump == null || jump.isEmpty || jump.toLowerCase() == 'none') {
        continue;
      }
      final hops = jump.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
      String? previousId;
      SessionProfile? previous;
      for (final hop in hops) {
        final existing = byName[hop];
        if (existing != null) {
          if (previous != null && (existing.jumpViaSessionId ?? '').isEmpty) {
            existing.jumpViaSessionId = previous.id;
          }
          previous = existing;
          previousId = existing.id;
          continue;
        }
        final parsed = _parseHop(hop);
        final id = 'sshcfg-jump-${_slug(hop)}';
        final created = byName[hop] ??
            profiles.cast<SessionProfile?>().firstWhere(
                  (p) => p!.id == id,
                  orElse: () => null,
                );
        if (created != null) {
          previous = created;
          previousId = created.id;
          continue;
        }
        final hopProfile = SessionProfile(
          id: id,
          name: hop,
          type: SessionType.ssh,
          host: parsed.host,
          port: parsed.port,
          username: parsed.user,
          jumpViaSessionId: previousId,
          group: 'OpenSSH',
          createdMs: DateTime.now().millisecondsSinceEpoch,
        );
        profiles.add(hopProfile);
        byName[hop] = hopProfile;
        previous = hopProfile;
        previousId = id;
      }
      final target = byName[name];
      if (target != null && previousId != null && previousId != target.id) {
        target.jumpViaSessionId = previousId;
      }
    }
    return profiles;
  }

  static List<ForwardRule> _forwards(Map<String, List<String>> opt) {
    final rules = <ForwardRule>[];
    var n = 0;
    for (final spec in opt['localforward'] ?? const <String>[]) {
      final rule = _local(spec, n++);
      if (rule != null) rules.add(rule);
    }
    for (final spec in opt['remoteforward'] ?? const <String>[]) {
      final rule = _remote(spec, n++);
      if (rule != null) rules.add(rule);
    }
    for (final spec in opt['dynamicforward'] ?? const <String>[]) {
      final port = int.tryParse(spec.split(':').last.trim());
      if (port == null) continue;
      rules.add(ForwardRule(
        id: 'fwd-$n',
        type: ForwardType.dynamic,
        localPort: port,
      ));
      n++;
    }
    return rules;
  }

  static ForwardRule? _local(String spec, int n) {
    final parts = _splitForward(spec);
    if (parts == null) return null;
    return ForwardRule(
      id: 'fwd-$n',
      type: ForwardType.local,
      localHost: parts.bindHost,
      localPort: parts.bindPort,
      remoteHost: parts.destHost,
      remotePort: parts.destPort,
    );
  }

  static ForwardRule? _remote(String spec, int n) {
    final parts = _splitForward(spec);
    if (parts == null) return null;
    return ForwardRule(
      id: 'fwd-$n',
      type: ForwardType.remote,
      localHost: parts.bindHost,
      localPort: parts.bindPort,
      remoteHost: parts.destHost,
      remotePort: parts.destPort,
    );
  }

  static _Fwd? _splitForward(String spec) {
    final bits = spec.trim().split(RegExp(r'\s+'));
    if (bits.length != 2) return null;
    final bind = _hostPort(bits[0], defaultHost: '127.0.0.1');
    final dest = _hostPort(bits[1], defaultHost: '127.0.0.1');
    if (bind == null || dest == null) return null;
    return _Fwd(bind.$1, bind.$2, dest.$1, dest.$2);
  }

  static (String, int)? _hostPort(String text, {required String defaultHost}) {
    if (!text.contains(':')) {
      final port = int.tryParse(text);
      if (port == null) return null;
      return (defaultHost, port);
    }
    final i = text.lastIndexOf(':');
    final host = text.substring(0, i);
    final port = int.tryParse(text.substring(i + 1));
    if (port == null) return null;
    return (host.isEmpty ? defaultHost : host, port);
  }

  static ({String? user, String host, int port}) _parseHop(String hop) {
    String? user;
    var hostPort = hop;
    if (hop.contains('@')) {
      final i = hop.lastIndexOf('@');
      user = hop.substring(0, i);
      hostPort = hop.substring(i + 1);
    }
    var host = hostPort;
    var port = 22;
    if (hostPort.startsWith('[')) {
      final end = hostPort.indexOf(']');
      if (end > 0) {
        host = hostPort.substring(1, end);
        final rest = hostPort.substring(end + 1);
        if (rest.startsWith(':')) port = int.tryParse(rest.substring(1)) ?? 22;
      }
    } else if (hostPort.contains(':')) {
      final i = hostPort.lastIndexOf(':');
      host = hostPort.substring(0, i);
      port = int.tryParse(hostPort.substring(i + 1)) ?? 22;
    }
    return (user: user, host: host, port: port);
  }

  static List<_Block> _blocks(String text) {
    final blocks = <_Block>[];
    _Block? cur;
    for (final raw in text.split('\n')) {
      var line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final hash = line.indexOf(' #');
      if (hash >= 0) line = line.substring(0, hash).trim();
      final sep = line.indexOf(RegExp(r'\s'));
      // Host / keyword tokens are separated by whitespace or `=`.
      final eq = line.indexOf('=');
      final cut = (sep < 0)
          ? eq
          : (eq < 0 ? sep : (sep < eq ? sep : eq));
      if (cut <= 0) continue;
      final key = line.substring(0, cut).trim().toLowerCase();
      var value = line.substring(cut + 1).trim();
      if (value.startsWith('=')) value = value.substring(1).trim();
      if (key == 'host') {
        cur = _Block(value.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList());
        blocks.add(cur);
      } else if (cur != null && value.isNotEmpty) {
        cur.options.putIfAbsent(key, () => []).add(value);
      }
    }
    return blocks;
  }

  static String? _first(Map<String, List<String>> opt, String key) {
    final v = opt[key];
    if (v == null || v.isEmpty) return null;
    return v.first;
  }

  static bool _yes(String? v) {
    if (v == null) return false;
    final s = v.toLowerCase();
    return s == 'yes' || s == 'true' || s == 'on';
  }

  static bool _isWildcard(String p) => p.contains('*') || p.contains('?');

  static bool _glob(String pattern, String name) {
    if (pattern == '*') return true;
    final re = RegExp(
      '^${pattern.split('').map((c) {
        if (c == '*') return '.*';
        if (c == '?') return '.';
        return RegExp.escape(c);
      }).join()}\$',
      caseSensitive: false,
    );
    return re.hasMatch(name);
  }

  static String? _expand(String? path, String? home) {
    if (path == null || path.isEmpty) return null;
    if (path == '~') return home;
    if (path.startsWith('~/') && home != null) {
      return '$home/${path.substring(2)}';
    }
    return path;
  }

  static String _slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]+'), '-');
}

class _Block {
  _Block(this.patterns);
  final List<String> patterns;
  final Map<String, List<String>> options = {};
}

class _Fwd {
  _Fwd(this.bindHost, this.bindPort, this.destHost, this.destPort);
  final String bindHost;
  final int bindPort;
  final String destHost;
  final int destPort;
}
