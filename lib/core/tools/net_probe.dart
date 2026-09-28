/// Small network checks used by the tools menu: TCP connect and ICMP ping.
library;

import 'dart:io';

class ProbeResult {
  ProbeResult({required this.ok, required this.detail, this.elapsed});

  final bool ok;
  final String detail;
  final Duration? elapsed;
}

Future<ProbeResult> probeTcp(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final watch = Stopwatch()..start();
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    watch.stop();
    socket.destroy();
    return ProbeResult(
      ok: true,
      detail: '$host:$port 可以连接',
      elapsed: watch.elapsed,
    );
  } catch (error) {
    watch.stop();
    return ProbeResult(
      ok: false,
      detail: '$host:$port 失败: $error',
      elapsed: watch.elapsed,
    );
  }
}

Future<ProbeResult> probePing(String host) async {
  final watch = Stopwatch()..start();
  try {
    final result = await Process.run('ping', ['-c', '4', '-W', '2', host]);
    watch.stop();
    final text = '${result.stdout}${result.stderr}'.trim();
    return ProbeResult(
      ok: result.exitCode == 0,
      detail: text.isEmpty ? 'ping 没有输出' : text,
      elapsed: watch.elapsed,
    );
  } catch (error) {
    watch.stop();
    return ProbeResult(ok: false, detail: '$error', elapsed: watch.elapsed);
  }
}
