/// Parser and importer for OpenSSH `~/.ssh/config`.
library;

import '../models/session_profile.dart';
import '../store/session_repository.dart';

class ParsedSshHost {
  ParsedSshHost(this.alias);

  final String alias;
  String? hostName;
  String? user;
  int port = 22;
  String? identityFile;
  String? proxyJump;
  bool forwardX11 = false;
  bool compression = false;

  String get targetHost =>
      (hostName == null || hostName!.isEmpty) ? alias : hostName!;
}

class SshConfigImportResult {
  SshConfigImportResult({required this.created, required this.skipped});

  final int created;
  final int skipped;
}

List<ParsedSshHost> parseSshConfig(String text) {
  final hosts = <ParsedSshHost>[];
  var current = <ParsedSshHost>[];

  for (final raw in text.split('\n')) {
    var line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final comment = line.indexOf(' #');
    if (comment > 0) line = line.substring(0, comment).trim();
    final parts = _split(line);
    if (parts.isEmpty) continue;
    final key = parts.first.toLowerCase();
    final value = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    if (key == 'host') {
      current = [];
      for (final alias in parts.skip(1)) {
        if (alias.contains('*') || alias.contains('?') || alias.contains('!')) {
          continue;
        }
        final host = ParsedSshHost(alias);
        current.add(host);
        hosts.add(host);
      }
      continue;
    }
    if (current.isEmpty || value.isEmpty) continue;
    for (final host in current) {
      switch (key) {
        case 'hostname':
          host.hostName = value;
        case 'user':
          host.user = value;
        case 'port':
          host.port = int.tryParse(value) ?? host.port;
        case 'identityfile':
          host.identityFile = value;
        case 'proxyjump':
          host.proxyJump = value.split(',').first.trim();
        case 'forwardx11':
          host.forwardX11 = _yes(value);
        case 'compression':
          host.compression = _yes(value);
      }
    }
  }
  return hosts;
}

Future<SshConfigImportResult> importSshConfig(
  String text,
  SessionRepository repo, {
  required String home,
}) async {
  final parsed = parseSshConfig(text);
  final byAlias = <String, SessionProfile>{};
  var skipped = 0;

  for (final host in parsed) {
    final id = 'sshcfg-${host.alias}';
    if (repo.byId(id) != null || byAlias.containsKey(host.alias)) {
      skipped++;
      continue;
    }
    byAlias[host.alias] = SessionProfile(
      id: id,
      name: host.alias,
      type: SessionType.ssh,
      host: host.targetHost,
      port: host.port,
      username: host.user,
      authMethod:
          host.identityFile == null ? AuthMethod.password : AuthMethod.publicKey,
      privateKeyPath: host.identityFile == null
          ? null
          : expandHome(host.identityFile!, home),
      x11Forwarding: host.forwardX11,
      compression: host.compression,
      group: 'OpenSSH',
      createdMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  for (final host in parsed) {
    final profile = byAlias[host.alias];
    final jump = host.proxyJump;
    if (profile == null || jump == null || jump.isEmpty) continue;
    profile.jumpViaSessionId = await _resolveJump(jump, byAlias, repo);
  }

  final saved = <SessionProfile>{};
  for (final profile in byAlias.values) {
    if (saved.add(profile)) await repo.upsert(profile);
  }
  return SshConfigImportResult(created: saved.length, skipped: skipped);
}

Future<String?> _resolveJump(
  String spec,
  Map<String, SessionProfile> created,
  SessionRepository repo,
) async {
  final known = created[spec];
  if (known != null) return known.id;

  var user = '';
  var hostPort = spec;
  if (spec.contains('@')) {
    final at = spec.indexOf('@');
    user = spec.substring(0, at);
    hostPort = spec.substring(at + 1);
  }
  var host = hostPort;
  var port = 22;
  final colon = hostPort.lastIndexOf(':');
  if (colon > 0 && !hostPort.startsWith('[')) {
    host = hostPort.substring(0, colon);
    port = int.tryParse(hostPort.substring(colon + 1)) ?? 22;
  }
  for (final profile in created.values) {
    if (profile.host == host && profile.port == port) return profile.id;
  }

  final id = 'sshcfg-jump-$host-$port';
  final existing = repo.byId(id);
  if (existing != null) return existing.id;
  final profile = SessionProfile(
    id: id,
    name: spec,
    type: SessionType.ssh,
    host: host,
    port: port,
    username: user.isEmpty ? null : user,
    group: 'OpenSSH',
    createdMs: DateTime.now().millisecondsSinceEpoch,
  );
  created[spec] = profile;
  return id;
}

String expandHome(String path, String home) {
  if (path == '~') return home;
  if (path.startsWith('~/')) return '$home/${path.substring(2)}';
  return path;
}

bool _yes(String value) {
  final v = value.toLowerCase();
  return v == 'yes' || v == 'true' || v == 'on';
}

List<String> _split(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var quote = '';
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quote.isNotEmpty) {
      if (ch == quote) {
        quote = '';
      } else {
        buf.write(ch);
      }
      continue;
    }
    if (ch == '"' || ch == "'") {
      quote = ch;
      continue;
    }
    if (ch == ' ' || ch == '\t' || ch == '=') {
      if (buf.isNotEmpty) {
        out.add(buf.toString());
        buf.clear();
      }
      continue;
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}
