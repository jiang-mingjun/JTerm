/// Port forwarding engine - drives the -L / -R / -D rules attached to one
/// SSH connection. Local forwards listen on a [ServerSocket] and spawn one
/// direct-tcpip channel per connection; remote forwards bridge incoming
/// server channels to a local address; dynamic forwards run a SOCKS5 server.
library;

import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../models/forward_rule.dart';
import '../ssh/ssh_connection.dart';

class ActiveForward {
  ActiveForward(this.rule, {this.listeningPort, this.error});

  final ForwardRule rule;
  final int? listeningPort;
  String? error;
  bool active = true;
}

class PortForwardEngine {
  PortForwardEngine(this.connection);

  final SshConnection connection;
  final List<ActiveForward> active = [];

  final List<ServerSocket> _localServers = [];
  final List<SSHRemoteForward> _remoteForwards = [];
  final List<SSHDynamicForward> _dynamicForwards = [];
  final List<StreamSubscription> _subs = [];

  Future<ActiveForward> start(ForwardRule rule) async {
    final entry = ActiveForward(rule);
    active.add(entry);
    try {
      switch (rule.type) {
        case ForwardType.local:
          await _startLocal(rule, entry);
        case ForwardType.remote:
          await _startRemote(rule, entry);
        case ForwardType.dynamic:
          await _startDynamic(rule, entry);
      }
    } catch (e) {
      entry.active = false;
      entry.error = e.toString();
    }
    return entry;
  }

  // -L localHost:localPort -> remoteHost:remotePort
  Future<void> _startLocal(ForwardRule rule, ActiveForward entry) async {
    final server = await ServerSocket.bind(rule.localHost, rule.localPort);
    _localServers.add(server);
    server.listen((socket) async {
      try {
        final channel = await connection.client!.forwardLocal(
          rule.remoteHost!,
          rule.remotePort!,
        );
        _pipe(socket, channel);
      } catch (_) {
        socket.destroy();
      }
    }, onError: (Object _) {});
  }

  // -R remoteHost:remotePort -> localHost:localPort
  Future<void> _startRemote(ForwardRule rule, ActiveForward entry) async {
    final fwd = await connection.client!.forwardRemote(
      host: rule.localHost == '0.0.0.0' ? '' : rule.localHost,
      port: rule.localPort,
    );
    if (fwd == null) {
      throw StateError('server refused remote forward');
    }
    _remoteForwards.add(fwd);
    final sub = fwd.connections.listen((channel) async {
      try {
        final socket = await Socket.connect(
          rule.remoteHost!,
          rule.remotePort!,
          timeout: const Duration(seconds: 5),
        );
        _pipe(socket, channel);
      } catch (_) {
        channel.close();
      }
    });
    _subs.add(sub);
  }

  // -D SOCKS5
  Future<void> _startDynamic(ForwardRule rule, ActiveForward entry) async {
    final fwd = await connection.client!.forwardDynamic(
      bindHost: rule.localHost,
      bindPort: rule.localPort,
    );
    _dynamicForwards.add(fwd);
  }

  void _pipe(Socket socket, SSHForwardChannel channel) {
    final s1 = socket.listen(
      (data) => channel.sink.add(data),
      onError: (Object _) => channel.close(),
      onDone: () => channel.close(),
    );
    final s2 = channel.stream.listen(
      socket.add,
      onError: (Object _) => socket.destroy(),
      onDone: () => socket.destroy(),
    );
    _subs.addAll([s1, s2]);
  }

  Future<void> stopAll() async {
    for (final s in _localServers) {
      await s.close();
    }
    _localServers.clear();
    for (final rf in _remoteForwards) {
      rf.close();
    }
    _remoteForwards.clear();
    for (final df in _dynamicForwards) {
      await df.close();
    }
    _dynamicForwards.clear();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    for (final a in active) {
      a.active = false;
    }
    active.clear();
  }
}
